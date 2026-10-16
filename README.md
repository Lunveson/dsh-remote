# dsh-remote

**从手机上访问电脑上的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）—— 走 adb 通道，不经过网络。**

---

## ★ 先说清楚：这不是第一个，也不是唯一 ★

"用手机访问 dsh"已经有相当多方案了。本项目的价值**不在"首创"**，而在于**换了一条技术路线**（不经过网络）。

### 生态对比（按 star 排序，仅列公开可见的部分）

| 项目 | 路线 | 走网络？ | 特点 |
|---|---|---|---|
| [shaobeichen/dsh-pocket](https://github.com/shaobeichen/dsh-pocket) ⭐1792 | dsh web + 手机扫码 | ✅ 局域网/公网 | 成熟度最高，有 npm 包 |
| [DSH-APP/DSHA](https://github.com/DSH-APP/DSHA) ⭐1384 | 手机里跑 dsh（PRoot + Ubuntu） | — | 把 dsh 装进手机本身 |
| [ningbainb/deepseek-harness-desktop](https://github.com/ningbainb/deepseek-harness-desktop) ⭐822 | 桌面客户端 + 移动远程 | ✅ | 一体化桌面方案 |
| [Clarklevis1995/dsh-mobile](https://github.com/Clarklevis1995/dsh-mobile) ⭐523 | 原生 iOS 客户端 + WebSocket | ✅ | iOS 原生体验 |
| [saya-ch/dsh-mobile](https://github.com/saya-ch/dsh-mobile) ⭐479 | Android App + 远程访问插件 | ✅ | 插件化 |
| [liguobao/ds-harness-remote](https://github.com/liguobao/ds-harness-remote) ⭐344 | P2P 优先 + 端到端加密 | ✅ | 多端、加密 |
| [SCSpotato/dsh-remote](https://github.com/SCSpotato/dsh-remote) ⭐98 | Tailscale + Caddy HTTPS 反代 | ✅ | 与我们同名，走网络 |
| **本项目** | **adb reverse + cookie 代理 + polyfill** | **❌ 不经过网络** | 见下 |

（以上只是搜索到的公开仓库，排序和 star 数会变化；如果漏了你的项目，欢迎补充。）

### 本项目的三个差异点

```
① 走 adb 通道（adb reverse）
   手机 → 127.0.0.1 → adb → 电脑本地端口
   · 不用组网、不用内网穿透、不开任何入站端口
   · 不怕 WiFi"设备隔离"（校园网/公司网常见）
   · adb 是"已建立的出站连接"，防火墙拦不住

② 逆向 cookie 认证
   dsh web 用"一次性 launch token + 签名 cookie"认证，
   正常做法是拿 dsh 打印的带 token URL 去换 cookie。
   本项目直接读本机 secret 自己签名 cookie 注入请求 ——
   免去了"扫码/复制带 token 的 URL"这一步。

③ WebView polyfill
   旧手机的系统 WebView（如 103）缺 Promise.withResolvers / AbortSignal.any，
   dsh 前端会直接崩。本项目拦截 HTML 在 <head> 注入补丁，把它救活。
```

### 什么时候该用这个项目 / 什么时候不该

| 场景 | 建议 |
|---|---|
| 手机和电脑在一处，只想自己用 | ✅ 本项目（最省事，连网络都不用配） |
| 网络被隔离，连不上电脑 | ✅ 本项目（走 adb，不走网络） |
| 不想开端口 / 不想组网 / 不想装 Tailscale | ✅ 本项目 |
| 想在外面（公网）连家里的电脑 | ❌ 用 [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) 或 [ds-harness-remote](https://github.com/liguobao/ds-harness-remote) |
| 想完全不依赖电脑，手机里跑 dsh | ❌ 用 [DSHA](https://github.com/DSH-APP/DSHA) 或 [DSHBox](https://github.com/WSK-build/DSHBox) |
| 想要原生 App 的完整体验 | ❌ 用 [dsh-mobile](https://github.com/Clarklevis1995/dsh-mobile) 系列 |

---

## 这个项目是怎么来的

### 起因

想在床上用手机操作电脑上的 dsh。试过几条路：

```
· 远程桌面工具：能看能用，但每次切换网络都要重连；
  手机端体验本质是"投屏"，不是原生界面
· 官方桌面版：只监听 127.0.0.1，外部访问不了
```

### 三个卡点

```
① 网络不通
   手机和电脑不在同一网络（校园网有"设备隔离"，同一 WiFi 也互不可见）

② 就算同网也没用
   dsh GUI 只绑 127.0.0.1，不对外

③ 有认证门
   dsh web 用"一次性 launch token + 签名 cookie"，没有 token 就 401
```

### 推的过程

```
【卡点① 网络】→ 想到 adb
  adb 本来就是"开发调试通道"，是【已建立的出站连接】，
  不需要任何入站规则 → 防火墙拦不住。
  用 adb reverse 把手机的端口转到电脑本地端口。
  ★关键一招★：不去和防火墙斗争，而是换一条不需要入站的路。

【卡点③ 认证】→ 读 dsh 的源码
  dsh 是 MIT 开源（2026 年 8 月），允许阅读和逆向。
  从 app.asar 里找到 cookie 的生成逻辑：
    名 = "dsh-auth-" + base64url(sha256(Host))
    值 = "v1." + base64url(payload) + "." + base64url(HMAC-SHA256(secret, body))
  又找到 secret 存在 ~/.dsh/.credentials.yaml。
  于是自己写一个代理：读 secret → 给每个请求签 cookie → 转发。
  ★于是就不需要"一次性 token"了★

【踩坑】三个认证细节，每个都让请求 401：
  · secret 是 base64url 编码的 32 字节，HMAC 的 key 必须用【解码后】的字节
  · Cookie 头必须插在请求头【第一个空行之前】
  · HTTP/1.1 是 keep-alive，代理只处理首个请求会导致后续请求没有 cookie
    → 非 WebSocket 请求一律改成 Connection: close

【卡点② 手机端显示】→ 极简 WebView App
  装完发现：手机的系统 WebView 是 2022 年的 103 版，
  而 dsh 前端用了 Promise.withResolvers（Chrome 119+）等新 API，
  页面直接 JS 报错 → 连不上。
  解法：用 WebViewClient.shouldInterceptRequest 拦下主文档 HTML，
  在 <head> 里注入一小段 polyfill 再交给 WebView。
  ★旧内核也能跑新前端，不用下载任何东西、不用 VPN★
```

### 与已有项目的关系

**做到最后才发现**社区已经有很多同类项目（见上面的对比表）。

本项目**没有参考它们**，是从 dsh 官方源码 + 第一原理推出来的 ——
所以路线和细节都不太一样（比如用 adb 通道而不是网络、用 polyfill 而不是升级 WebView）。

**提交前又专门检索了一遍**，找到两个高度重合的项目：

- **[pocket-desk-agent / PDAgent](https://github.com/techgniouss/pdagent)** ——
  已经做了"手机遥控电脑 + 隐私屏 + 开机自启 + 从手机触发构建 Android APK 并取回"，
  比我们成熟得多。
- **[sinonchum/android-autonomous-dev-agent](https://github.com/sinonchum/android-autonomous-dev-agent)** ——
  做了"改代码 → 装真机 → 冷启动 → 查 logcat → 截图验证"的自主交付循环。

**所以**：这些能力我们**不是**首创者，成熟度也差得远。

**我们目前没找到完全相同做法的**（注意用词：**没找到**，不是"没人做过"）：

```
① 装完自检 + ★失败自动回滚★（自动装回上一个可用版本并重启）
② 网页兜底（App 崩了/回滚失败时，浏览器走同一条 adb 通道照样能用）
③ 全程不经网络（只靠 adb reverse：不组网、不穿透、不开端口）
```

完整的对比、引用和检索过程见 **[docs/RELATED-WORK.md](docs/RELATED-WORK.md)**。

**教训**：自己推出来 ≠ 没人做过。世界上聪明人很多，
很多"我觉得只有我会想到"的办法，别人可能早就想到了。
先查全生态，再谈"有没有人做过"。

---

## 它怎么工作

```
【手机】浏览器 或 App
   ↓  http://127.0.0.1:19387   （手机本地地址）
   ↓  adb reverse：手机的 19387 → 电脑的 23554
【电脑】dsh-link 代理
   ↓  读取本机 secret，自动签名并注入认证 cookie
【电脑】dsh GUI（127.0.0.1:19387）
   ↓
和电脑上一模一样的界面
```

三件事各自解决一个具体问题：

| 问题 | 解法 |
|---|---|
| 电脑的 GUI 只监听 127.0.0.1，外部进不来 | **adb reverse** 把手机端口转到电脑 |
| dsh 用一次性 token + 签名 cookie 认证 | **代理读取本机 secret 自己签名** cookie |
| 旧手机 WebView 缺新 JS API，前端崩溃 | **App 拦截 HTML 注入 polyfill** |

---

## 目录

```
dsh-remote/
├── java/                    ★电脑端：Java 版（推荐，自带 adb reverse 自动维护）
│   ├── DshLink.java            代理 + cookie 签名 + adb reverse 维护
│   ├── start.bat               双击启动（有窗口，能看日志）
│   ├── start-silent.vbs        双击启动（无窗口，后台静默）
│   ├── stop-silent.vbs         双击停止
│   └── dsh-link.ps1 / dsh-link-stop.ps1
│
├── python/                  电脑端：Python 版（脚本短，好改）
│   ├── dsh_proxy.py            代理 + cookie 签名
│   ├── tcp_forward.py          纯 TCP 转发（无 cookie 注入，备用）
│   └── start.bat
│
└── android/                 ★手机端：一个极简 WebView App
    └── app/src/main/java/com/rptchat/dshremote/MainActivity.java
```

---

## 快速开始

### 前置

```
① 电脑装了 dsh（DeepSeek Harness），能正常打开
② 电脑有 Java 17+（脚本会自动找：JAVA_HOME → PATH → 常见安装位置）
③ 有 adb（Android SDK platform-tools）
④ 手机通过【无线调试】或 USB 连上电脑（adb devices 能看到它）
```

### 第 1 步：电脑端启动

```
双击  java\start-silent.vbs        （无窗口）
或    java\start.bat               （有窗口，看得到日志）
```

它会自动：
- 找 java / adb
- 编译 `DshLink.java`（首次运行）
- 起代理（`127.0.0.1:23554`）
- **每 3 秒检查一次 `adb reverse`，断了自动重做**

### 第 2 步：手机端访问

**方式 A（最简单）：手机浏览器**

```
http://127.0.0.1:19387
```

**方式 B（推荐）：装手机端 App**

用 Android Studio 或 gradle 编译 `android/`，装到手机，点图标即用。

### 停止

```
双击  java\stop-silent.vbs
```

---

## 关于"无线调试"（不用 USB 线的连法）

如果手机和电脑不在同一网段（比如校园网有设备隔离），可以：

```
1. 手机开【个人热点】→ 电脑连这个热点
   （热点通常没有"设备隔离"，能互访）
2. 手机 → 设置 → 开发者选项 → 无线调试 → 配对
3. 电脑：adb pair <热点IP:配对端口> <6位配对码>
4. 电脑：adb connect <热点IP:连接端口>
```

---

## 已知的坑（血泪，别再踩）

```
【认证】
① dsh 的 secret 在 ~/.dsh/.credentials.yaml，
   是 base64url 编码的 32 字节 —— HMAC 的 key 必须用【解码后】的字节
② Cookie 头必须插在请求头【第一个空行之前】
③ dsh 有 Host/Origin 检查，Origin ≠ Host 就 403
④ ★keep-alive 陷阱★：代理只处理第一个请求的话，
   同一连接上的后续请求拿不到 cookie
   → 非 WebSocket 请求一律改成 Connection: close

【网络】
⑤ Windows 防火墙挡入站端口（加规则要管理员）→ 用 adb reverse 绕
⑥ 校园网常有"设备隔离"，同 WiFi 设备互不可见 → 走手机热点
⑦ 手机无线调试界面显示的是校园网 IP，但 adbd 监听所有网卡
   → 用【热点 IP】（= 热点网关）能连

【脚本编码】(Windows 三种文件格式各不相同)
⑧ .bat  必须 CRLF 换行 + 本地编码（GBK）—— 用 LF/UTF-8 会被 cmd 冲烂
⑨ .ps1  用 UTF-8 with BOM（Windows PowerShell 5.1 才认 UTF-8）
⑩ .vbs  用本地编码 + CRLF 最稳
   （本仓库的启动脚本全部改成纯 ASCII 英文，规避这些坑）

【前端】
⑪ 旧 WebView(103) 缺 Promise.withResolvers / AbortSignal.any
   → 用 shouldInterceptRequest 拦 HTML 注入 polyfill 解决
```

---

## 说明与边界

```
· dsh 本身是 DeepSeek 的项目（MIT 许可证），本项目只是它的一个"外部接入层"
· 代理做的是【本机访问本机】：读本机 ~/.dsh/.credentials.yaml 的 secret，
  为访问本机 dsh 的请求签名 —— 不涉及任何远程凭证、不联网
· 请只在自己拥有/授权的机器上使用
· 本项目不包含、也不分发 dsh 自身的任何代码
```

## License

MIT（见 `LICENSE`）
