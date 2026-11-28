<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="Doorman icon">
</p>

<h1 align="center">Doorman</h1>

<p align="center">Walk away, and your Mac locks itself.</p>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="https://hodgekou.github.io/doorman/">Website</a>
</p>

<p align="center">
  <a href="https://github.com/hodgekou/doorman/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/hodgekou/doorman"></a>
  <a href="https://github.com/hodgekou/doorman/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/hodgekou/doorman/actions/workflows/ci.yml/badge.svg"></a>
</p>

---

Doorman is a small macOS menu bar app. It uses the Apple Watch or iPhone you carry to tell whether you're at your Mac: walk away and the Mac locks; keep typing and it never will. When you come back, unlock the way you already do — Apple Watch, Touch ID or your password.

<p align="center">
  <img src="docs/assets/en/settings-overview-light.png" width="720" alt="Doorman overview">
</p>

## Features

- **Locks when you leave** — nothing to install on your watch or phone.
- **Never locks while you work** — as long as you're using the keyboard, mouse or trackpad, it won't lock.
- **A countdown first** — a 5-second warning before locking; move the mouse to cancel.
- **Doesn't touch your password** — Doorman only locks. It never stores or types your password.
- **See the signal** — a live chart of your device's signal, and three sensitivity presets: Sensitive, Balanced, Relaxed.
- **Three languages** — English, 简体中文 and 日本語, switchable any time.

| Menu bar | Countdown before locking |
|---|---|
| <img src="docs/assets/en/menu-light.png" width="320" alt="Menu bar"> | <img src="docs/assets/en/warning-light.png" width="420" alt="Countdown before locking"> |

## Requirements

- macOS 13 or later
- An Apple Watch or iPhone (ideally signed in to the same Apple ID as your Mac)

## Install

**Option 1: one command (recommended)**

Open Terminal, paste this line and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash
```

It downloads the latest release, verifies its integrity and signature, installs Doorman in Applications and opens it. Builds with in-app updates check daily. Choose **Check for Updates…** from the menu for a manual check, or turn off daily checks in General settings. For older builds, rerun the installer once.

**Option 2: download the disk image**

1. Download [Doorman.dmg](https://github.com/hodgekou/doorman/releases/latest/download/Doorman.dmg) ([all releases](https://github.com/hodgekou/doorman/releases)).
2. Open it and drag Doorman into the Applications folder.
3. The first time you open it, macOS says it can't verify the developer: go to *System Settings › Privacy & Security*, click **Open Anyway** near the bottom, then open Doorman again.

> Doorman isn't notarized by Apple yet, which is why step 3 is needed for the disk image. The one-command install doesn't run into this.

Want to build from source? See [DEVELOPMENT.md](DEVELOPMENT.md).

## How to use

1. **Follow the first-run guide** — allow Bluetooth and notifications, pick your watch or phone, and try a test lock if you like.
2. **Then forget about it** — Doorman lives in the menu bar at the top right. Click its icon to see the status and signal, lock now, or pause for a while.
3. **Unlock when you're back** — turn on *Unlock with Apple Watch* in *System Settings › Touch ID & Password*, then just wake the screen when you return.
4. **Adjust** — click the menu bar icon › Settings…
   - *Leave Detection*: pick another sensitivity if it locks too soon or too late.
   - *Device*: switch devices, or give yours a friendlier name.
   - *General*: change the language or open Doorman at login.

<img src="docs/assets/en/settings-detection-light.png" width="720" alt="Leave detection settings">

## FAQ

**Will it lock while I'm reading without touching anything?**
Only if your device's signal also drops. You'll see a 5-second countdown first; move the mouse to cancel.

**Why doesn't Doorman unlock my Mac when I come back?**
Bluetooth signals can be spoofed, so unlocking with them isn't safe. macOS's own Apple Watch Unlock is far more secure, so Doorman leaves unlocking to it.

**Watch or phone?**
An Apple Watch works best because it's always on your wrist. A phone works too, but if you leave it on the desk its signal stays strong after you walk away, so your Mac won't lock.

**macOS asks for Bluetooth access again?**
It may ask after each reinstall. Just allow it.

**Is any of my data uploaded?**
No. Doorman uses the network only to check for and download updates. It keeps the last 30 days of lock history on your Mac and never records what you type.

## Uninstall

Run in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/hodgekou/doorman/main/install.sh | bash -s -- --uninstall
```

Add `--purge` to also remove settings and lock history. Or quit Doorman from the menu bar and move it from Applications to the Trash.

## Feedback

Found a problem or have an idea? Please open an [issue](https://github.com/hodgekou/doorman/issues).

Inspired by [BLEUnlock](https://github.com/ts1/BLEUnlock).

[MIT license](LICENSE) · © 2026 hodgekou
