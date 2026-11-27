# Doorman 开发说明

面向参与开发的人。使用说明见 [README](README.zh-CN.md)。

## 构建与测试

只需要 Xcode Command Line Tools（Swift 6），不需要 Xcode。

```sh
swift build                 # 编译
scripts/test.sh             # 核心逻辑单测（swift-testing）
scripts/check-l10n.sh       # 检查英文、日文翻译是否齐全、占位符是否一致
scripts/build-app.sh        # 打包 dist/Doorman.app（ad-hoc 签名）
scripts/install.sh          # 打包并安装到 /Applications，然后启动
scripts/make-icon.sh        # 重新生成 App 图标
```

蓝牙、通知、登录项都需要以 `.app` 形式运行；直接 `swift run` 只适合看日志。

## 代码结构

```
Sources/DoormanCore/   纯逻辑，不依赖 AppKit / CoreBluetooth，可单测、可回放轨迹
  Config.swift           可调参数（初定值，待真机标定）
  MedianFilter.swift     中值滤波 + 样本最大年龄
  PresenceMachine.swift  设备在场状态机
  LockGate.swift         活动守卫：键鼠空闲 + 锁前倒计时，轮次号
  LockExecution.swift    执行前复核、锁屏尝试追踪、会话证据
  ProductState.swift     自动锁屏可用 / 仅提醒 / 监控未就绪
  LockLog.swift          诊断记录（本地、30 天、500 条）
Sources/Doorman/       菜单栏 App
  App/                   AppModel：把三层状态接到系统上
  Bluetooth/             CoreBluetooth 采样
  System/                键鼠空闲、会话观察、锁屏方式、通知、登录项
  UI/                    菜单栏弹出窗口、设置窗口、首次引导、锁前倒计时
  Localization/          英文、日文翻译表
  Support/               设置、诊断记录存储、本地化入口
Tests/DoormanCoreTests/ 单测，以及「用着电脑时不会锁」的轨迹回放
Support/               Info.plist、entitlements、图标、InfoPlist.strings
docs/                  GitHub Pages 网站
```

## 工作原理

```
蓝牙 RSSI ─▶ 中值滤波 ─▶ 在场状态：在场 / 离开中 / 已离开 / 失联
                                │ 想要锁屏
                                ▼
            活动守卫：键鼠空闲 ≥ 10 秒？
              否 → 拦截，继续观察
              是 → 5 秒倒计时（任何操作都会取消这一轮）
                                │
                                ▼
        执行前复核：现读空闲时长、核对轮次号和会话状态
                                │
                                ▼
                锁屏 ─▶ 通过会话信号确认已锁
```

- 两个阈值之间留有间隔（默认 −60 / −80 dBm），避免在临界距离来回切换。
- 信号完全消失时等待 60 秒（可调）才判定失联；睡眠唤醒后先重新采样，15 秒内找不到设备显示「监控未就绪」，不锁屏。
- 执行前复核在 `AppModel.executeLock` 里，和系统锁屏调用在同一个同步函数中，中间不 `await`。

## 安全相关的实现细节

- 默认锁屏方式调用私有函数 `SACLockScreenImmediate`，不能上架 Mac App Store，未来系统可能失效；「诊断与实验」里可以切换其他方式。
- 键鼠空闲时长通过 `CGEventSource.secondsSinceLastEventType` 读取，只读时间戳。
- 设备通过 CoreBluetooth 标识在本机重连，不读取系统私有蓝牙数据库。
- 只锁屏、不解锁；不保存、不代输登录密码。

## 本地化

界面支持简体中文、英文、日文，可在运行时切换。所有面向用户的文案都写成 `L("中文原文")`（带参数时用 `L("…%@…", value)`，需要调换顺序用 `%1$@`），并在 `Sources/Doorman/Localization/Strings.en.swift`、`Strings.ja.swift` 中补上翻译，然后运行 `scripts/check-l10n.sh`。

系统蓝牙授权弹窗的文案通过 `Support/Localization/*.lproj/InfoPlist.strings` 本地化，跟随系统语言。

## 界面截图

用示例数据把各界面按三种语言渲染成 PNG（不启动蓝牙，不写入用户设置）：

```sh
scripts/build-app.sh debug
DOORMAN_SNAPSHOT_DIR=/tmp/doorman-snap dist/Doorman.app/Contents/MacOS/Doorman
```

深色模式截图受离屏渲染限制，背景可能缺失，以真机为准。

## 构建环境注意事项

- 只装 Command Line Tools 时，SwiftUI 的 `@State` 宏不可用（没有 SwiftUIMacros 插件），界面局部状态统一用 `ObservableObject` + `@StateObject`。
- `swift test` 偶尔找不到 swift-testing 的宏插件，`scripts/test.sh` 会显式传入插件目录。
