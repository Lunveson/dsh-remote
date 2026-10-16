# dsh-remote

**用手机访问电脑上的 [DeepSeek Harness](https://github.com/deepseek-ai)（dsh）。**

不用 Todesk、不用插 USB 线、不怕 WiFi 隔离、不怕防火墙。

> DSH 桌面版（2026-09-25 预览上线）只监听 `127.0.0.1`，只能在本机用。
> 本项目让你**从手机上**访问它 —— 走 adb 通道，绕过防火墙和网络隔离。

---

## 它做了什么

```
【手机】浏览器 或 App
   ↓  http://127.0.0.1:19387   （手机本地地址）
   ↓  adb reverse：手机的 19387 → 电脑的 23554
【电脑】dsh-link 代理
   ↓  读取本地 secret，自动签名并注入认证 cookie
【电脑】dsh GUI（127.0.0.1:19387）
   ↓
和电脑上一模一样的界面
```

三件事各自解决一个硬问题：

| 问题 | 解法 |
|---|---|
| 电脑的 GUI 只监听 127.0.0.1，外部进不来 | **adb reverse** 把手机端口转到电脑（adb 是出站连接，防火墙拦不住） |
| dsh 用一次性 token + 签名 cookie 认证 | **代理读取本地 secret，自己签名 cookie** 注入每个请求 |
| 旧手机 WebView 缺新 JS API，前端崩溃 | **App 拦截 HTML，在 `<head>` 注入 polyfill** |

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
② 电脑有 Java 17+（脚本会自动找）
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
- 编译 `DshLink.java`（首次）
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

详见 `docs/wireless-debug.md`。

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
  为访问本机 dsh 的请求签名 —— 不涉及任何远程凭证
· 请只在自己拥有/授权的机器上使用
· 本项目不包含、也不分发 dsh 自身的任何代码
```

## License

MIT（见 `LICENSE`）
