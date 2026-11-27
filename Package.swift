// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Doorman",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Doorman", targets: ["Doorman"]),
    ],
    targets: [
        // 纯逻辑：滤波、在场状态机、活动守卫闸门、执行前复核、锁屏尝试追踪、诊断记录。
        // 不依赖 AppKit / CoreBluetooth，可单测、可回放真机轨迹。
        .target(name: "DoormanCore"),
        // 菜单栏 App：CoreBluetooth 采样、系统锁屏、会话观察、预警窗口、设置界面。
        .executableTarget(
            name: "Doorman",
            dependencies: ["DoormanCore"]
        ),
        .testTarget(
            name: "DoormanCoreTests",
            dependencies: ["DoormanCore"]
        ),
    ]
)
