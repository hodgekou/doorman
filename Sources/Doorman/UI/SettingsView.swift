import AppKit
import SwiftUI
import DoormanCore

/// 设置窗口：系统设置风格的侧边栏布局。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var model: AppModel?

    func show(model: AppModel) {
        self.model = model
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Doorman"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 920, height: 700))
            window.contentMinSize = NSSize(width: 860, height: 640)
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

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            model?.stopDiscovery()
            DockPresence.windowClosed()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.settingsSection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .font(AppFont.sidebar)
                        .padding(.vertical, 4)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
        } detail: {
            Group {
                switch model.settingsSection ?? .overview {
                case .overview: OverviewPane(model: model)
                case .devices: DevicesPane(model: model)
                case .detection: DetectionPane(model: model)
                case .permissions: PermissionsPane(model: model)
                case .diagnostics: DiagnosticsPane(model: model)
                }
            }
            .font(AppFont.body)
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - 概览

private struct OverviewPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(summary)
                if let issue = summary.issue {
                    IssueBanner(message: issue.message, actionTitle: issue.actionTitle) {
                        model.perform(issue.fix)
                    }
                }
                signalCard
                activityCard
            }
            .padding(24)
        }
    }

    private func hero(_ summary: StatusSummary) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(summary.tone.color.opacity(0.15))
                Image(systemName: summary.heroSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(summary.tone.color)
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline).font(AppFont.title2.weight(.semibold))
                Text(summary.detail).foregroundStyle(.secondary)
            }
            Spacer()
            if model.paused {
                Button("恢复保护") { model.resume() }
                    .controlSize(.large)
            }
            Button {
                model.lockNow()
            } label: {
                Label("立即锁屏", systemImage: "lock.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: model.deviceSymbol).font(AppFont.title3)
                Text(model.settings.boundDeviceID == nil ? "随身设备" : model.deviceName).font(AppFont.headline)
                Spacer()
                if model.settings.boundDeviceID != nil {
                    SignalBars(rssi: model.estimate)
                    Text(model.estimate.map { "\($0) dBm" } ?? "无信号")
                        .font(AppFont.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if model.settings.boundDeviceID == nil {
                VStack(spacing: 10) {
                    Text("选择一台随身设备后，这里会显示它最近 2 分钟的信号变化。")
                        .foregroundStyle(.secondary)
                    Button("选择设备") { model.settingsSection = .devices }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                SignalChart(
                    points: model.signalHistory,
                    presentRSSI: model.settings.presentRSSI,
                    leaveRSSI: model.settings.leaveRSSI
                )
                HStack(spacing: 16) {
                    legend(.accentColor, "信号（已平滑）")
                    legend(.gray, "原始读数", dot: true)
                    legend(.green, "回到身边 \(model.settings.presentRSSI) dBm", dashed: true)
                    legend(.red, "判定离开 \(model.settings.leaveRSSI) dBm", dashed: true)
                    legend(Color.gray.opacity(0.35), "无信号", block: true)
                    Spacer()
                }
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            }
        }
        .card(padding: 16)
    }

    private var activityCard: some View {
        let entries = Array(model.log.entries.filter { $0.kind != .revoked }.suffix(5).reversed())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近活动").font(AppFont.headline)
                Spacer()
                Button("查看全部") { model.settingsSection = .diagnostics }
                    .buttonStyle(.link)
            }
            if entries.isEmpty {
                Text("还没有记录。离开、锁屏、被拦截的锁屏都会出现在这里。")
                    .foregroundStyle(.secondary)
                    .font(AppFont.callout)
            }
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(entry.kind.tone.color)
                        .frame(width: 20)
                    Text(entry.kind.friendlyTitle)
                    if let latency = entry.latencySeconds, entry.kind == .observedLocked {
                        Text("离开后 \(Int(latency.rounded())) 秒").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.secondary)
                }
                .font(AppFont.callout)
            }
        }
        .card(padding: 16)
    }

    private func legend(_ color: Color, _ text: String, dot: Bool = false, dashed: Bool = false, block: Bool = false) -> some View {
        HStack(spacing: 5) {
            if block {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 10)
            } else if dot {
                Circle().fill(color).frame(width: 6, height: 6)
            } else if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(color).frame(width: 4, height: 2) }
                }
            } else {
                Capsule().fill(color).frame(width: 14, height: 3)
            }
            Text(text)
        }
    }
}

// MARK: - 随身设备

private struct DevicesPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.settings.boundDeviceID != nil {
                    HStack(spacing: 12) {
                        Image(systemName: model.deviceSymbol)
                            .font(AppFont.largeTitle)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.deviceName).font(AppFont.title3.weight(.semibold))
                            Text(model.summary.deviceDetail ?? model.summary.detail).foregroundStyle(.secondary).font(AppFont.callout)
                        }
                        Spacer()
                        SignalBars(rssi: model.estimate).font(AppFont.title3)
                        Button("停止使用") { model.unbind() }
                    }
                    .padding(.vertical, 4)
                    TextField("显示名称", text: $model.settings.deviceAlias,
                              prompt: Text(model.settings.boundDeviceName ?? "随身设备"))
                    Picker("设备类型", selection: $model.settings.deviceKind) {
                        ForEach(DeviceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                } else {
                    Label("还没有选择设备", systemImage: "applewatch.slash")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("当前设备")
            }

            Section {
                DevicePicker(model: model)
                    .padding(.vertical, 4)
            } header: {
                Text(model.settings.boundDeviceID == nil ? "选择设备" : "更换设备")
            } footer: {
                FooterText("推荐 Apple Watch：一直戴在身上，信号最稳定。把设备放在键盘旁，信号最强、名称对得上的就是它。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 离开检测

private struct DetectionPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.settings.autoLockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("离开时自动锁屏")
                        Text("关闭后只显示信号，不会锁屏").font(AppFont.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(Sensitivity.allCases) { option in
                    sensitivityRow(option)
                }
                if model.settings.sensitivity == nil {
                    Label("当前使用自定义阈值，可在下方「高级」中修改", systemImage: "slider.horizontal.3")
                        .font(AppFont.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("灵敏度")
            } footer: {
                FooterText("不确定选哪个？先用「均衡」，到「概览」看信号曲线：你走开时曲线应掉到红线以下，坐着时应在绿线附近。")
            }

            Section {
                Picker("键鼠空闲多久后才锁屏", selection: $model.settings.idleThresholdSeconds) {
                    ForEach([5, 10, 30], id: \.self) { Text("\($0) 秒").tag($0) }
                }
                Picker("锁屏前倒计时", selection: $model.settings.warningSeconds) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) 秒").tag($0) }
                }
            } header: {
                Text("用着电脑时不锁屏")
            } footer: {
                FooterText("信号变弱后，还要键盘、鼠标、触控板都没动过这么久，才会出现倒计时。倒计时期间碰一下就取消，这次不会再提示。")
            }

            Section {
                Picker("设备突然没信号后，等待", selection: $model.settings.signalTimeoutSeconds) {
                    ForEach([30, 60, 120], id: \.self) { Text("\($0) 秒").tag($0) }
                }
                Picker("这台 Mac 的蓝牙关闭时", selection: $model.settings.sensorPolicy) {
                    ForEach(SensorPolicy.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("没有信号时")
            } footer: {
                FooterText("设备关机、没电或进电梯时信号会直接消失。等待时间越短锁得越快，但更容易误锁。")
            }

            Section {
                DisclosureGroup("高级") {
                    Picker("回到身边（信号强于）", selection: $model.settings.presentRSSI) {
                        ForEach(Array(stride(from: -45, through: -75, by: -5)), id: \.self) { Text("\($0) dBm").tag($0) }
                    }
                    Picker("判定离开（信号弱于）", selection: $model.settings.leaveRSSI) {
                        ForEach(Array(stride(from: -65, through: -95, by: -5)), id: \.self) { Text("\($0) dBm").tag($0) }
                    }
                    Picker("离开后再观察", selection: $model.settings.leaveDelaySeconds) {
                        ForEach([2, 3, 5, 10, 15, 30], id: \.self) { Text("\($0) 秒").tag($0) }
                    }
                    Picker("采样方式", selection: $model.settings.samplingMode) {
                        ForEach(SamplingMode.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sensitivityRow(_ option: Sensitivity) -> some View {
        let isSelected = model.settings.sensitivity == option
        let v = option.values
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(AppFont.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.title).font(AppFont.body.weight(.medium))
                    if option == .balanced { Badge(text: "推荐") }
                }
                Text(option.detail).font(AppFont.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(v.present) / \(v.leave) dBm · \(v.delay) 秒")
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.settings.apply(option) }
        .padding(.vertical, 2)
    }
}

// MARK: - 权限与启动

private struct PermissionsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: "蓝牙",
                    detail: "必需。用来感知随身设备的信号强弱。",
                    status: model.bluetoothPermission,
                    action: model.requestBluetoothPermission
                )
                PermissionRow(
                    symbol: "bell.badge",
                    title: "通知",
                    detail: "建议开启。锁屏未成功、信号不稳定时提醒你。",
                    status: model.notificationPermission,
                    action: model.requestNotificationPermission
                )
                if model.accessibilityPermission != .notNeeded {
                    PermissionRow(
                        symbol: "accessibility",
                        title: "辅助功能",
                        detail: "当前锁屏方式需要它来发送锁屏快捷键。",
                        status: model.accessibilityPermission,
                        action: model.requestAccessibilityPermission
                    )
                }
            } header: {
                Text("权限")
            } footer: {
                FooterText("每次重新打包安装后签名会变化，系统可能要求重新授权。")
            }

            Section {
                Toggle(isOn: $model.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录时自动启动")
                        Text(model.loginItemError ?? LoginItem.statusDescription)
                            .font(AppFont.caption)
                            .foregroundStyle(model.loginItemError == nil ? Color.secondary : Color.red)
                    }
                }
            } header: {
                Text("启动")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Doorman 只负责离开时锁屏，不会保存或代输你的登录密码。", systemImage: "lock.shield")
                    Label("推荐开启「用 Apple Watch 解锁」：戴着手表回来，唤醒屏幕即可。", systemImage: "applewatch")
                    Label("也可以用触控 ID 或密码。", systemImage: "touchid")
                }
                .font(AppFont.callout)
                .padding(.vertical, 4)
                Button("打开「触控 ID 与密码」设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("回来时怎么解锁")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }
}

// MARK: - 诊断与实验

private struct DiagnosticsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("这里是给调试和真机验证用的工程视图。日常使用不需要关心。")
                    .foregroundStyle(.secondary)

                stateCard
                lockMethodCard
                logCard
            }
            .padding(24)
        }
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("实时状态").font(AppFont.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Term("① 设备在场", Glossary.presence)
                    StatusPill(text: model.presence.title, tone: model.presence.tone)
                    Term("活动守卫", Glossary.gate)
                    StatusPill(text: model.gatePhase.title, tone: model.gatePhase.tone)
                }
                GridRow {
                    Term("② 锁屏请求", Glossary.request)
                    StatusPill(text: model.attempt.title, tone: model.attempt.tone)
                    Term("③ 会话", Glossary.session)
                    StatusPill(text: model.session.title, tone: model.session == .locked ? .info : .neutral)
                }
                GridRow {
                    Term("原始 / 滤波", Glossary.rssi)
                    Text("\(model.lastRaw.map(String.init) ?? "—") / \(model.estimate.map(String.init) ?? "—") dBm").monospacedDigit()
                    Term("键鼠空闲", Glossary.idle)
                    Text(model.idleText).monospacedDigit()
                }
                GridRow {
                    Term("产品状态", Glossary.product)
                    Text(model.productState.title)
                    Term("自动锁屏调用", Glossary.lockCalls)
                    Text("\(model.autoLockCalls) 次（本次运行）").monospacedDigit()
                }
            }
            .font(AppFont.callout)
        }
        .card(padding: 16)
    }

    private var lockMethodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) { Text("锁屏方式（M0 实验）").font(AppFont.headline); HelpTip(Glossary.lockMethod) }
            Picker("方式", selection: $model.settings.lockMethod) {
                ForEach(LockMethodKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
            Text(model.lockMethodStatus).font(AppFont.caption).foregroundStyle(.secondary)
            HStack {
                if model.settings.lockMethod == .shortcut, !model.lockMethodCanLock {
                    Button("申请辅助功能权限") { model.requestAccessibilityPermission() }
                }
                Button("立即测试锁屏") { model.lockNow() }
            }
        }
        .card(padding: 16)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("诊断记录").font(AppFont.headline)
                Spacer()
                Button("清除") { model.clearLog() }
            }
            if model.log.entries.isEmpty {
                Text("暂无记录").foregroundStyle(.secondary).font(AppFont.callout)
            }
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.log.entries.reversed())) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.date.formatted(date: .numeric, time: .standard))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: entry.kind.symbol)
                            .foregroundStyle(entry.kind.tone.color)
                            .frame(width: 16)
                        Text(entry.kind.title)
                        Text(entry.reason?.title ?? "").foregroundStyle(.secondary)
                        if let latency = entry.latencySeconds {
                            Text(String(format: "%.1f 秒", latency)).monospacedDigit()
                        }
                        Text(entry.note ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .font(AppFont.caption)
                }
            }
            Text("仅保存在本机，最近 30 天、最多 500 条。不记录附近的其他设备。")
                .font(AppFont.caption2)
                .foregroundStyle(.tertiary)
        }
        .card(padding: 16)
    }
}
