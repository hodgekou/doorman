<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="Doorman 图标">
</p>

<h1 align="center">Doorman</h1>

<p align="center">离开工位，Mac 自动锁好。</p>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="README.ja.md">日本語</a> · <a href="https://hodgekou.github.io/doorman/">官网</a>
</p>

<p align="center">
  <a href="https://github.com/hodgekou/doorman/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/hodgekou/doorman"></a>
  <a href="https://github.com/hodgekou/doorman/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/hodgekou/doorman/actions/workflows/ci.yml/badge.svg"></a>
</p>

---

Doorman 是一个 macOS 菜单栏小工具。它通过你随身带的 Apple Watch 或 iPhone 判断你是否在电脑旁：离开工位，Mac 自动锁屏；正在打字、动鼠标时，绝不会锁。回来后用 macOS 自己的方式解锁——用 Apple Watch 解锁、触控 ID 或密码。

<p align="center">
  <img src="docs/assets/zh/settings-overview-light.png" width="720" alt="Doorman 概览">
</p>

## 功能

- **离开就锁**：手表、手机上不用装任何东西。
- **用着电脑时不会锁**：只要你在操作键盘、鼠标或触控板，就不会被锁屏。
- **锁屏前有倒计时**：锁屏前 5 秒提示，动一下鼠标就取消。
- **不碰你的密码**：Doorman 只负责锁屏，不保存、也不会替你输入密码。
- **看得见信号**：实时显示设备信号，灵敏度有「灵敏 / 均衡 / 宽松」三档可选。
- **三种语言**：简体中文、English、日本語，随时切换。

| 菜单栏 | 锁屏前倒计时 |
|---|---|
| <img src="docs/assets/zh/menu-light.png" width="320" alt="菜单栏"> | <img src="docs/assets/zh/warning-light.png" width="420" alt="锁屏前倒计时"> |

## 系统要求

- macOS 13 或更新版本
- Apple Watch 或 iPhone（建议与 Mac 登录同一个 Apple ID）

## 安装

**方式一：一条命令安装（推荐）**

打开「终端」，粘贴下面这行并回车：

```sh
curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash
```

它会下载最新版本，校验完整性和签名后安装到「应用程序」并自动打开。以后想更新，再运行一次同一条命令即可。

**方式二：下载安装包**

1. 下载 [Doorman.dmg](https://github.com/hodgekou/doorman/releases/latest/download/Doorman.dmg)（[所有版本](https://github.com/hodgekou/doorman/releases)）。
2. 打开后把 Doorman 拖到「应用程序」文件夹。
3. 第一次打开时，macOS 会提示无法验证开发者：打开「系统设置 › 隐私与安全性」，在页面下方点「仍要打开」，再打开一次 Doorman。

> Doorman 目前还没有经过 Apple 公证，所以从安装包首次打开时需要第 3 步。用命令安装不会遇到这个提示。

想从源码构建，见[开发说明](DEVELOPMENT.md)。

## 使用

1. **跟着首次引导走一遍**：允许蓝牙和通知，选择你的手表或手机，可以顺便试锁一次。
2. **之后就不用管了**：Doorman 待在屏幕右上角的菜单栏里。点图标可以看到当前状态、设备信号，也可以「立即锁屏」或「暂停」一段时间。
3. **回来时解锁**：推荐在「系统设置 › 触控 ID 与密码」里开启「用 Apple Watch 解锁」，戴着手表回来，唤醒屏幕即可。
4. **调整**：点菜单栏图标 › 设置…
   - 「离开检测」：锁得太快或太慢时换一档灵敏度。
   - 「随身设备」：更换设备，或给设备起个好认的名字。
   - 「通用」：切换语言、开启登录时自动启动。

<img src="docs/assets/zh/settings-detection-light.png" width="720" alt="离开检测设置">

## 常见问题

**我只看屏幕、不碰键鼠时会被锁吗？**
只有设备信号同时变弱时才会。锁屏前会先出现 5 秒倒计时，动一下鼠标就取消。

**为什么回来时 Doorman 不帮我解锁？**
蓝牙信号可以被伪造，用它解锁不安全。macOS 自带的「用 Apple Watch 解锁」安全得多，所以解锁交给系统。

**用手表还是手机好？**
推荐 Apple Watch，它一直戴在手上。手机也可以，但如果手机放在桌上，你走开后它的信号依然很强，就不会锁屏。

**系统再次请求蓝牙权限？**
每次重新安装后系统可能会再问一次，允许即可。

**我的数据会被上传吗？**
不会。Doorman 不联网，只在本机保存最近 30 天的锁屏记录，也不会记录你的按键内容。

## 卸载

在终端运行：

```sh
curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash -s -- --uninstall
```

加上 `--purge` 会同时删除设置和锁屏记录。也可以先在菜单栏退出 Doorman，再把「应用程序」里的 Doorman 移到废纸篓。

## 反馈

遇到问题或有建议，欢迎提 [Issue](https://github.com/hodgekou/doorman/issues)。

灵感来自 [BLEUnlock](https://github.com/ts1/BLEUnlock)。
