import AppKit
import SwiftUI
import DoormanCore

/// 首次引导窗口。
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private weak var model: AppModel?

    func show(model: AppModel) {
        self.model = model
        if window == nil {
            let view = OnboardingView(model: model) { [weak self] in self?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "欢迎使用 Doorman"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 700, height: 620))
            window.delegate = self
            window.center()
            self.window = window
        }
        if window?.isVisible != true {
            model.startDiscovery()
            DockPresence.windowOpened()
        }
        model.refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            model?.stopDiscovery()
            DockPresence.windowClosed()
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, device, tryIt, unlock
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var testedLock = false
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let onFinish: () -> Void
    @StateObject private var state = OnboardingState()

    init(model: AppModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 40)
                .padding(.top, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .font(AppFont.body)
        .frame(width: 700, height: 620)
    }

    // MARK: 步骤内容

    @ViewBuilder
    private var content: some View {
        switch state.step {
        case .welcome: welcome
        case .permissions: permissions
        case .device: device
        case .tryIt: tryIt
        case .unlock: unlock
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 8) {
                Text("离开工位，Mac 自动锁好").font(AppFont.largeTitle.weight(.bold))
                Text("Doorman 通过你随身带的 Apple Watch 或 iPhone 判断你是否在电脑旁。")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                feature("applewatch.radiowaves.left.and.right", "感知你的随身设备", "手表或手机上不用安装任何东西")
                feature("keyboard", "用着电脑时不会锁", "只要你在敲键盘、动鼠标，就不会被锁屏")
                feature("lock.shield", "不碰你的密码", "回来后用 Apple Watch、触控 ID 或密码解锁")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("需要两个权限", "蓝牙用来感知设备；通知用来在出问题时提醒你。")
            VStack(spacing: 4) {
                PermissionRow(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: "蓝牙",
                    detail: "必需",
                    status: model.bluetoothPermission,
                    action: model.requestBluetoothPermission
                )
                Divider()
                PermissionRow(
                    symbol: "bell.badge",
                    title: "通知",
                    detail: "建议开启",
                    status: model.notificationPermission,
                    action: model.requestNotificationPermission
                )
            }
            .card(padding: 16)
            if model.bluetoothPermission == .denied {
                Label("蓝牙权限被拒绝了。请在系统设置中打开 Doorman 的蓝牙开关，回来后会自动刷新。", systemImage: "info.circle")
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("选择你的随身设备", "推荐 Apple Watch：一直戴在身上，信号最稳定。把设备放在键盘旁，点选信号最强的那台。")
            DevicePicker(model: model, listHeight: 230)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("试一试", "拿着\(model.deviceName)走到门口，再走回来，看看曲线的变化。")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: model.deviceSymbol).font(AppFont.title3)
                    Text(model.deviceName).font(AppFont.headline)
                    Spacer()
                    StatusPill(text: model.presence.friendlyTitle, tone: model.presence.tone)
                    SignalBars(rssi: model.estimate)
                }
                SignalChart(
                    points: model.signalHistory,
                    presentRSSI: model.settings.presentRSSI,
                    leaveRSSI: model.settings.leaveRSSI
                )
                .frame(height: 170)
                Text("走开时曲线应掉到红线以下；回来后回到绿线附近。差得太远可以之后在「离开检测」里换一档灵敏度。")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .card(padding: 14)

            HStack(spacing: 12) {
                Button("测试锁屏") {
                    state.testedLock = true
                    model.lockNow()
                }
                Text(lockTestResult)
                    .font(AppFont.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unlock: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("回来时，这样解锁", "Doorman 只负责离开时锁屏，不保存也不代输你的登录密码。")
            VStack(alignment: .leading, spacing: 14) {
                feature("applewatch", "用 Apple Watch 解锁（推荐）", "戴着手表回来，唤醒屏幕即可。需要在系统设置中开启一次。")
                feature("touchid", "触控 ID", "带触控 ID 的 Mac 或妙控键盘")
                feature("key", "密码", "随时可用")
            }
            .card(padding: 16)
            Button("打开「触控 ID 与密码」设置") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: 底栏

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == state.step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: step == state.step ? 18 : 7, height: 7)
                }
            }
            Spacer()
            if state.step != .welcome {
                Button("返回") { move(-1) }
                    .controlSize(.large)
            }
            Button(primaryTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
    }

    private var primaryTitle: String {
        switch state.step {
        case .welcome: return "开始设置"
        case .tryIt: return state.testedLock ? "继续" : "跳过测试"
        case .unlock: return "开始使用"
        default: return "继续"
        }
    }

    private var canContinue: Bool {
        switch state.step {
        case .permissions: return model.bluetoothPermission == .granted
        case .device: return model.settings.boundDeviceID != nil
        default: return true
        }
    }

    private func advance() {
        if state.step == .unlock {
            model.completeOnboarding()
            onFinish()
            return
        }
        move(1)
    }

    private func move(_ delta: Int) {
        if let next = OnboardingStep(rawValue: state.step.rawValue + delta) {
            state.step = next
        }
    }

    private var lockTestResult: String {
        guard state.testedLock else { return "会立即锁定屏幕，用来确认这台 Mac 能被自动锁屏" }
        switch model.attempt {
        case .pending: return "正在确认…"
        case .observedLocked: return "✓ 锁屏正常"
        case .unconfirmed: return "没能确认锁屏，之后可在「诊断与实验」里换一种锁屏方式"
        default: return model.lockMethodCanLock ? "已发送锁屏" : "当前锁屏方式不可用"
        }
    }

    // MARK: 小组件

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.title.weight(.bold))
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(AppFont.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).font(AppFont.callout)
            }
        }
    }
}
