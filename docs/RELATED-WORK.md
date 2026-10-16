# 相关项目与我们的位置（诚实版）

> 这份文档是**提交前检索的结果**。写它的理由很简单：
> 上一版 README 里我们说过"这个方向没人做过"，后来一查，**是错的**。
> 所以这次先把生态查清楚，再说我们到底站在哪。

---

## 一、最接近我们的项目

### 1. [pocket-desk-agent / PDAgent](https://github.com/techgniouss/pdagent)（Python · MIT · PyPI 有包）

**用 Telegram 从任何设备远程控制 Windows PC。** 已完成的功能里，和我们重合的：

```
✅ 截图 / 键盘快捷键 / 剪贴板 / 窗口切换 / 睡眠 / 关机
✅ ★隐私屏（blank the display with privacy mode）★      ← 我们也做了关屏
✅ ★开机自启（pdagent startup enable）★                 ← 我们也做了
✅ ★从手机触发构建 Android APK 并取回（/build、/getapk）★ ← 我们也做了
✅ AI 自然语言控制 PC（Gemini agentic computer use）
✅ OCR 点击、宏录制、任务计划（survives restarts）、live remote desktop
```

**结论**：**"手机遥控电脑 + 从手机编译 APK"这两件事，它做得很完整，比我们成熟得多。**

**它的路线**：Telegram bot + 出站长轮询（不需要开端口）。
**我们的路线**：dsh 的 agent 会话 + adb 通道。

### 2. [sinonchum/android-autonomous-dev-agent](https://github.com/sinonchum/android-autonomous-dev-agent)（TypeScript · MIT）

**"真机上的自主 Android 交付循环"**。它的循环：

```
需求 → 计划 → 实现 → 构建 → 修编译错误
     → ★装 APK 到真机★ → ★冷启动★ → ★查 logcat★ → ★截图★
     → 复审规格 / 代码质量 → 记录经验
```

它的原话（很值得引用）：

> "代码存在不算完成。编译成功不算完成。
>  只有 APK 被构建、安装、启动、通过 logcat 检查、并在有设备时视觉验证之后，才算完成。"

**结论**：**"改完代码 → 装真机 → 启动 → 查 logcat → 截图验证"这个闭环，它做过。**
我们的"自检三项"（进程 / 前台 / 崩溃日志）和它的"cold launch + inspect logcat"思路一致。

### 3. 同名的 [SCSpotato/dsh-remote](https://github.com/SCSpotato/dsh-remote)（⭐98 · Kotlin）

和我们**同一个名字**，做的是 **dsh 的手机端 + 远程访问**。
它的路线：`dsh web` → Tailscale 组网 → Caddy HTTPS 反代 → Android App。
（走网络；我们走 adb 通道。）

### 4. 其它相关

- [shaobeichen/dsh-pocket](https://github.com/shaobeichen/dsh-pocket) ⭐1792 —— dsh web + 手机扫码，生态里最成熟的
- [DSH-APP/DSHA](https://github.com/DSH-APP/DSHA) ⭐1384 —— 手机里跑 dsh（PRoot）
- [liguobao/ds-harness-remote](https://github.com/liguobao/ds-harness-remote) ⭐344 —— P2P + 端到端加密
- [self-defining-systems/sdo](https://github.com/self-defining-systems/sdo) —— agentic 部署运维
- [c9r-io/orchestrator](https://github.com/c9r-io/orchestrator) —— self-bootstrap
- [sandgardenhq/sgai](https://github.com/sandgardenhq/sgai) —— self-modification 相关文档

---

## 二、那我们到底还剩什么？

**先把不该说的去掉**：

```
❌ "第一个把 dsh 接进手机"        —— dsh-pocket ⭐1792 一早就有
❌ "手机遥控电脑"                 —— PDAgent 做得很完整
❌ "手机触发编译 APK"             —— PDAgent 有 /build + /getapk
❌ "AI 改代码 → 装真机 → 验证"    —— android-autonomous-dev-agent 做过
❌ "关屏/隐私屏"                  —— PDAgent 有
❌ "开机自启"                     —— PDAgent 有
```

**剩下这几点，是我们目前**没找到**完全相同做法的**（注意用词：**没找到**，不是"没人做过"）：

```
① ★"装完自检 + 自动回滚"★
   概念：新版本装上去 → 自动验证（进程/前台/崩溃）→
        不过就【自动装回上一个可用版本】+ 重启
   检索结果：PDAgent 的 /build+/getapk 是"构建并取回"，
             android-autonomous-dev-agent 是"验证后报告"，
             ★两者都没有描述"失败自动回滚"这一步★
   （但也可能有人做了没写出来 —— 所以不敢称首创）

② ★"网页兜底"★
   App 崩了/回滚也失败时，走 adb reverse 的浏览器通道照常可用
   （这条更像是我们场景下的自然产物：因为走的是 adb 通道，
     浏览器和 App 共享同一条链路，App 挂了浏览器还能进）

③ ★"整套链路完全不经网络"★
   adb reverse 作为唯一通路（不用局域网、不用公网、不用内网穿透、不开端口）
   PDAgent 走 Telegram（要公网）；dsh-pocket 走局域网/公网；
   ds-harness-remote 走 P2P。★我们这条是全程本地物理通道★

④ 逆向 dsh 的认证自己做代理（读本机 secret 签 cookie）
   —— 这是本项目特有的，因为只有我们要接的是 dsh 的 127.0.0.1
```

---

## 三、最诚实的自我评价

```
· 我们【没有】发明任何单个技术
· 我们【没有】比现有项目做得更好（成熟度差得远）
· 我们的价值在于【一个特定的组合】：
    "完全本地物理通道 + dsh 原生体验 + 带安全带的自我迭代"
· 这套组合适合的场景很窄：
    设备在同一处、不想组网、网络被隔离、只想自己用
· 而且整个过程是【从 dsh 官方源码 + 第一原理推出来的】，
    没有参考上面任何项目（是做完之后才去查的）
```

**如果有人在别处见过"自检 + 自动回滚 + 兜底"的 Android 自我迭代实现，欢迎告诉我们 —— 我们会把这条更正。**

---

*检索时间：2026-10-17 凌晨 · 检索方式：GitHub API 搜索 + 全网搜索 + 读取相关项目 README*
