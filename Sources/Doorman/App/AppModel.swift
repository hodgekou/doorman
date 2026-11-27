import AppKit
import DoormanCore

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case devices
    case detection
    case permissions
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .devices: return "随身设备"
        case .detection: return "离开检测"
        case .permissions: return "权限与启动"
        case .diagnostics: return "诊断与实验"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "house"
        case .devices: return "applewatch"
        case .detection: return "figure.walk"
        case .permissions: return "checkmark.shield"
        case .diagnostics: return "stethoscope"
        }
    }
}

/// 信号图上的一个点：每秒一个。raw 为 nil 表示这一秒没有样本。
struct SignalPoint: Identifiable {
    let id: Int
    let date: Date
    let raw: Int?
    let estimate: Int?
    /// 断线分段：中间有空档时换一段，折线不跨空档连接
    let segment: Int
}

enum SystemSettingsPane {
    case bluetooth
    case notifications
    case accessibility
    case loginItems

    var url: URL? {
        switch self {
        case .bluetooth: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .loginItems: return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        }
    }
}

/// 把三层状态接到系统上：
/// ① PresenceMachine（在场）→ LockGate（活动守卫）→ ② 执行前复核 + LockMethod → ③ SessionObserver（会话）
/// 所有逻辑都在主线程同步执行。
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            let normalized = settings.normalized()
            if normalized != settings { settings = normalized }
            if settings != oldValue { applySettings(old: oldValue) }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            if let error = LoginItem.setEnabled(launchAtLogin) {
                loginItemError = error
                launchAtLogin = LoginItem.isEnabled
            } else {
                loginItemError = nil
            }
        }
    }

    @Published private(set) var loginItemError: String?
    @Published private(set) var presence: Presence
    @Published private(set) var productState: ProductState = .notReady(.noDeviceBound)
    @Published private(set) var gatePhase: LockGate.Phase = .closed
    @Published private(set) var attempt: LockAttemptStatus = .idle
    @Published private(set) var session: SessionState = .unknown
    @Published private(set) var lastRaw: Int?
    @Published private(set) var estimate: Int?
    @Published private(set) var idleSeconds: Double?
    @Published private(set) var paused = false
    @Published private(set) var autoLockCalls = 0
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var log: LockLog
    @Published private(set) var bluetooth: BluetoothAvailability = .unknown
    @Published private(set) var lastLockSummary = "—"
    @Published private(set) var lockMethodCanLock = false
    @Published var settingsSection: SettingsSection? = .overview
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var lastLockDate: Date?
    @Published private(set) var lastLockLatency: Double?
    @Published private(set) var signalHistory: [SignalPoint] = []
    @Published private(set) var bluetoothPermission: PermissionStatus = Scanner.permission
    @Published private(set) var notificationPermission: PermissionStatus = .notDetermined
    @Published private(set) var accessibilityPermission: PermissionStatus = .notNeeded

    private var pendingRaw: Int?
    private var signalSegment = 0
    private var signalGapPending = false
    private var signalCounter = 0
    private var tickCount = 0
    private let signalHistoryLength = 120
    private let signalGapThreshold: Duration = .seconds(3)

    private var presenceMachine: PresenceMachine
    private var gate: LockGate
    private var tracker: LockAttemptTracker
    private var lockMethod: LockMethod
    private let scanner = Scanner()
    private let sessionObserver = SessionObserver()
    private let overlay = WarningOverlay()
    private let notifier = Notifier()
    private let logStore = LogStore()
    private var timer: Timer?
    private var departureAt: Instant?
    private var lastObservedLockAt: Date?
    private var discoveryActive = false
    /// 截图模式下为 false：示例数据不写入用户设置
    private var persistenceEnabled = true

    init() {
        let loaded = AppSettings.load()
        let config = loaded.config
        settings = loaded
        launchAtLogin = LoginItem.isEnabled
        presenceMachine = PresenceMachine(config: config, now: .now)
        gate = LockGate(config: config)
        tracker = LockAttemptTracker(confirmTimeout: config.confirmTimeout)
        lockMethod = LockMethods.make(loaded.lockMethod)
        presence = .resampling(since: .now)
        log = LogStore().load()
        wire()
        start()
    }

    // MARK: - 用户操作

    /// 用户主动发起，不经过活动守卫。
    func lockNow() {
        guard lockMethod.canLock else {
            notifier.post(id: "manual", title: "Doorman：无法自动锁屏", body: "当前锁屏方式不可用，请按 ⌃⌘Q 锁定。")
            return
        }
        _ = lockMethod.lock()
        tracker.begin(LockRound(reason: .manual), at: .now, departureAt: nil)
        record(.manualLock, reason: .manual, note: lockMethod.kind.title)
        publish()
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
    }

    func bind(_ device: DiscoveredDevice) {
        var s = settings
        s.boundDeviceID = device.id
        s.boundDeviceName = device.name
        s.deviceAlias = ""
        s.deviceKind = .auto
        settings = s
    }

    func unbind() {
        var s = settings
        s.boundDeviceID = nil
        s.boundDeviceName = nil
        settings = s
    }

    func startDiscovery() {
        discoveryActive = true
        scanner.start()
        scanner.setDiscovery(true)
    }

    func stopDiscovery() {
        discoveryActive = false
        scanner.setDiscovery(false)
        if settings.boundDeviceID == nil || paused { scanner.stop() }
    }

    func clearLog() {
        log.clear()
        logStore.save(log)
    }

    func requestAccessibility() {
        ShortcutLock.requestPermission()
    }

    // MARK: - 权限

    /// 未请求过：创建 CBCentralManager 触发系统弹窗；已拒绝：打开系统设置。
    func requestBluetoothPermission() {
        if Scanner.permission == .denied {
            openSystemSettings(.bluetooth)
        } else {
            scanner.start()
        }
        refreshPermissions()
    }

    func requestNotificationPermission() {
        if notificationPermission == .denied {
            openSystemSettings(.notifications)
        } else {
            notifier.requestAuthorization { [weak self] in self?.refreshPermissions() }
        }
    }

    func requestAccessibilityPermission() {
        ShortcutLock.requestPermission()
        openSystemSettings(.accessibility)
    }

    func openSystemSettings(_ pane: SystemSettingsPane) {
        if let url = pane.url { NSWorkspace.shared.open(url) }
    }

    func refreshPermissions() {
        bluetoothPermission = Scanner.permission
        if settings.lockMethod == .shortcut {
            accessibilityPermission = AXIsProcessTrusted() ? .granted : .notDetermined
        } else {
            accessibilityPermission = .notNeeded
        }
        notifier.fetchPermission { [weak self] status in self?.notificationPermission = status }
    }

    // MARK: - 启动与接线

    private func wire() {
        scanner.onSample = { [weak self] rssi, epoch in self?.receiveSample(rssi, epoch: epoch) }
        scanner.onAvailability = { [weak self] availability in self?.bluetoothChanged(availability) }
        scanner.onDiscoveredChange = { [weak self] list in self?.discovered = list }
        sessionObserver.onStateChange = { [weak self] state in self?.sessionChanged(state) }
        sessionObserver.onWillSleep = { [weak self] in self?.systemWillSleep() }
        sessionObserver.onDidWake = { [weak self] in self?.restartMonitoring() }
        sessionObserver.onSessionResignActive = { [weak self] in self?.sessionResignActive() }
        sessionObserver.onSessionBecomeActive = { [weak self] in self?.restartMonitoring() }
    }

    private func start() {
        // 调试截图模式：填充示例数据、渲染界面截图后退出，不启动蓝牙和计时器
        if let dir = ProcessInfo.processInfo.environment["DOORMAN_SNAPSHOT_DIR"] {
            persistenceEnabled = false
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyPreviewState()
                SnapshotRenderer.renderAll(model: self, to: URL(fileURLWithPath: dir, isDirectory: true))
                exit(0)
            }
            return
        }
        notifier.requestAuthorization()
        scanner.mode = settings.samplingMode
        scanner.bind(settings.boundDeviceID)
        scanner.epoch = presenceMachine.epoch
        // 启动即创建 CBCentralManager：首次运行时系统会弹出蓝牙授权
        scanner.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshPermissions()
        publish()

        // 首次运行：打开引导
        if !settings.onboardingCompleted {
            Task { @MainActor [weak self] in
                guard let self else { return }
                OnboardingWindowController.shared.show(model: self)
            }
        }
    }

    // MARK: - 每秒一次

    private func tick() {
        let now = ContinuousClock.now
        sessionObserver.poll()
        idleSeconds = IdleClock.secondsSinceLastInput()

        if paused, let until = pausedUntil, Date() >= until {
            resume()
        }

        if !paused, settings.boundDeviceID != nil {
            handle(presenceMachine.onTick(at: now))
            if gate.isEndedByUser, presenceMachine.isStablyNear(at: now) {
                gate.onStableNear()
            }
            handle(gate.onTick(at: now, lastInputAt: IdleClock.lastInputAt(now: now)))
        }

        if let outcome = tracker.onTick(at: now, session: sessionObserver.state) {
            handle(outcome)
        }
        overlay.update(now: now)
        recordSignalPoint(now: now)

        tickCount += 1
        if tickCount % 5 == 0 {
            refreshPermissions()
        } else {
            bluetoothPermission = Scanner.permission
        }
        publish()
    }

    /// 信号图每秒一个点。采样计时器和这里的计时器各自每秒触发、并不同步，
    /// 某一秒恰好没收到新读数很正常；超过 signalGapThreshold 没有读数才算「无信号」并断线。
    private func recordSignalPoint(now: Instant) {
        let raw = pendingRaw
        pendingRaw = nil
        let fresh = presenceMachine.lastSampleAt.map { now - $0 <= signalGapThreshold } ?? false
        let estimate = fresh ? presenceMachine.estimate : nil
        if estimate == nil {
            signalGapPending = true
        } else if signalGapPending {
            signalGapPending = false
            signalSegment += 1
        }
        signalCounter += 1
        signalHistory.append(SignalPoint(
            id: signalCounter,
            date: Date(),
            raw: raw,
            estimate: estimate,
            segment: signalSegment
        ))
        if signalHistory.count > signalHistoryLength {
            signalHistory.removeFirst(signalHistory.count - signalHistoryLength)
        }
    }

    private func receiveSample(_ rssi: Int, epoch: Int) {
        guard !paused else { return }
        let now = ContinuousClock.now
        let wasNear = presenceMachine.state == .near
        let effects = presenceMachine.onSample(rssi, at: now, epoch: epoch)
        if epoch == presenceMachine.epoch { pendingRaw = rssi }
        if wasNear, case .leaving(_) = presenceMachine.state {
            departureAt = now
        }
        handle(effects)
        publish()
    }

    // MARK: - ① 在场状态机的输出

    private func handle(_ effects: [PresenceEffect]) {
        for effect in effects {
            switch effect {
            case .lockWanted(let reason):
                if reason == .lost { departureAt = presenceMachine.lastSampleAt }
                requestAutoLock(reason)
            case .deviceReturned:
                departureAt = nil
                handle(gate.revoke(.deviceReturned))
            case .monitorNotReady(let issue):
                notifyNotReady(issue)
            }
        }
    }

    private func requestAutoLock(_ reason: LockReason) {
        guard settings.autoLockEnabled, !tracker.isPending else { return }
        gate.onLockWanted(reason)
    }

    // MARK: - 活动守卫的输出

    private func handle(_ effects: [GateEffect]) {
        for effect in effects {
            switch effect {
            case .showWarning(_, let until):
                overlay.show(until: until, total: settings.warningSeconds, deviceName: deviceName)
            case .hideWarning:
                overlay.hide()
            case .blockedByActivity(let round, let idle):
                record(.blockedByActivity, reason: round.reason,
                       note: "设备判定\(round.reason.title)，但 \(Int(idle.secondsValue)) 秒前有键鼠操作，未锁屏")
            case .cancelledByUser(let round):
                record(.warningCancelled, reason: round.reason, note: "预警期间有键鼠输入，本轮结束")
                notifySignalUnstable()
            case .revoked(let round, let why):
                record(.revoked, reason: round.reason, note: why.title)
            case .execute(let round, let warningStartedAt):
                executeLock(round, warningStartedAt: warningStartedAt)
            }
        }
    }

    /// ② 执行前复核 + 调用系统锁屏。
    /// 复核时现读键鼠空闲时长；复核与 lock() 在同一个同步调用里，中间不 await、不切线程。
    private func executeLock(_ round: LockRound, warningStartedAt: Instant) {
        sessionObserver.poll()
        let decision = ExecutionCheck.evaluate(
            round: round,
            currentRoundID: gate.currentRoundID,
            session: sessionObserver.state,
            lastInputAt: IdleClock.lastInputAt(now: .now),
            warningStartedAt: warningStartedAt
        )

        switch decision {
        case .proceed:
            if lockMethod.canLock {
                let called = lockMethod.lock()
                autoLockCalls += 1
                gate.finishExecution()
                tracker.begin(round, at: .now, departureAt: departureAt)
                if !called {
                    record(.lockCallFailed, reason: round.reason, note: "锁屏调用返回失败，等待会话确认")
                }
            } else {
                gate.finishExecution()
                tracker.record(.reminded(round))
                record(.reminded, reason: round.reason)
                lastLockSummary = "仅提醒"
                notifier.post(id: "remind", title: "Doorman：你好像离开了",
                              body: "这台 Mac 当前不支持自动锁屏，请按 ⌃⌘Q 锁定。")
            }

        case .skipAlreadyLocked:
            gate.finishExecution()
            tracker.record(.skippedAlreadyLocked(round))
            record(.skippedAlreadyLocked, reason: round.reason, note: "执行前会话已锁")

        case .abort(let reason):
            tracker.record(.aborted(round, reason))
            if reason == .inputAfterWarning {
                gate.endByUser()
                notifySignalUnstable()
            } else {
                gate.finishExecution()
            }
            lastLockSummary = "执行前放弃"
            record(.abortedBeforeExecution, reason: round.reason, note: "\(reason.title)，0 次锁屏调用")
        }
        publish()
    }

    private func handle(_ outcome: AttemptOutcome) {
        switch outcome {
        case .observedLocked(let round, let latency):
            // 「锁屏后很快解锁」只对自动锁屏有意义；手动 / 测试锁屏不算误锁线索
            lastObservedLockAt = round.reason == .manual ? nil : Date()
            lastLockDate = Date()
            lastLockLatency = latency?.secondsValue
            if let latency {
                lastLockSummary = "\(round.reason.title) · \(String(format: "%.1f", latency.secondsValue)) 秒"
            } else {
                lastLockSummary = round.reason.title
            }
            record(.observedLocked, reason: round.reason, latency: latency?.secondsValue)
        case .unconfirmed(let round):
            lastLockSummary = "未确认"
            record(.unconfirmed, reason: round.reason, note: "确认时限内两路会话信号不一致或缺失")
            notifier.post(id: "unconfirmed", title: "Doorman：锁屏未确认",
                          body: "没能确认这台 Mac 已锁定。如果你还在附近，请按 ⌃⌘Q。")
        case .lateConfirmation(let round, let after):
            record(.lateConfirmation, reason: round.reason, latency: after.secondsValue, note: "确认迟到，请求结果仍为未确认")
        }
    }

    // MARK: - ③ 会话与系统事件

    private func sessionChanged(_ state: SessionState) {
        let before = session
        session = state
        guard state == .unlocked, before != .unlocked else { return }
        if let at = lastObservedLockAt {
            let elapsed = Date().timeIntervalSince(at)
            if elapsed < 15 {
                record(.quickUnlockClue, note: "锁屏后 \(Int(elapsed)) 秒内解锁，误锁线索")
            }
        }
        lastObservedLockAt = nil
        tracker.onUnlocked()
    }

    private func systemWillSleep() {
        handle(gate.revoke(.systemSleep))
        if let round = tracker.cancelPending(.systemSleep) {
            record(.revoked, reason: round.reason, note: "睡眠，作废待确认请求")
        }
        overlay.hide()
        publish()
    }

    private func sessionResignActive() {
        handle(gate.revoke(.sessionSwitched))
        if let round = tracker.cancelPending(.sessionSwitched) {
            record(.revoked, reason: round.reason, note: "切换会话，作废待确认请求")
        }
        overlay.hide()
        scanner.stop()
        publish()
    }

    /// 唤醒、切回会话、恢复监控、重新绑定：作废旧 epoch，进入「重新采样中」。
    private func restartMonitoring() {
        presenceMachine.restart(at: .now)
        scanner.epoch = presenceMachine.epoch
        departureAt = nil
        if !paused, settings.boundDeviceID != nil {
            scanner.start()
        }
        publish()
    }

    private func bluetoothChanged(_ availability: BluetoothAvailability) {
        bluetooth = availability
        let now = ContinuousClock.now
        switch availability {
        case .poweredOn:
            if presenceMachine.isSensorBlocked {
                handle(gate.revoke(.sensorRestored))
                presenceMachine.sensorAvailable(at: now)
            }
        case .poweredOff, .unauthorized, .unsupported:
            guard settings.boundDeviceID != nil else { break }
            let issue: MonitorIssue = availability == .poweredOff ? .bluetoothOff : .bluetoothUnauthorized
            handle(gate.revoke(.sensorUnavailable))
            handle(presenceMachine.sensorUnavailable(issue))
            if settings.sensorPolicy == .lock {
                requestAutoLock(.sensorUnavailable)
            }
        case .unknown:
            break
        }
        scanner.epoch = presenceMachine.epoch
        publish()
    }

    /// minutes 为 nil 表示直到手动恢复。暂停期间停止扫描并断开连接。
    func pause(minutes: Int?) {
        paused = true
        pausedUntil = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        handle(gate.revoke(.paused))
        overlay.hide()
        scanner.stop()
        publish()
    }

    func resume() {
        paused = false
        pausedUntil = nil
        restartMonitoring()
    }

    // MARK: - 设置

    private func applySettings(old: AppSettings) {
        if persistenceEnabled { settings.save() }
        let config = settings.config
        if config != old.config {
            presenceMachine.updateConfig(config)
            gate.config = config
            tracker.confirmTimeout = config.confirmTimeout
        }
        if settings.samplingMode != old.samplingMode {
            scanner.mode = settings.samplingMode
        }
        if settings.lockMethod != old.lockMethod {
            lockMethod = LockMethods.make(settings.lockMethod)
            refreshPermissions()
        }
        if settings.boundDeviceID != old.boundDeviceID {
            handle(gate.revoke(.rebound))
            gate.reset()
            tracker.record(.idle)
            scanner.bind(settings.boundDeviceID)
            restartMonitoring()
            if settings.boundDeviceID == nil, !discoveryActive {
                scanner.stop()
            }
        }
        if !settings.autoLockEnabled, old.autoLockEnabled {
            handle(gate.revoke(.paused))
            gate.reset()
        }
        publish()
    }

    // MARK: - 调试截图用的示例状态

    /// 只在 DOORMAN_SNAPSHOT_DIR 截图模式下调用，不写入用户设置和诊断记录文件。
    func applyPreviewState() {
        var s = AppSettings()
        s.onboardingCompleted = true
        s.boundDeviceID = UUID()
        s.boundDeviceName = "我的 Apple Watch"
        settings = s

        presence = .near
        lastRaw = -57
        estimate = -58
        bluetooth = .poweredOn
        bluetoothPermission = .granted
        notificationPermission = .notDetermined
        accessibilityPermission = .notNeeded
        session = .unlocked
        idleSeconds = 2
        lockMethodCanLock = true
        productState = .autoLockAvailable
        lastLockDate = Date().addingTimeInterval(-3600)
        lastLockLatency = 16.2

        let now = Date()
        signalHistory = (0..<120).map { i in
            let t = Double(i)
            var value = -58.0 + sin(t / 5) * 3
            if (40..<70).contains(i) { value = -58 - min(30, Double(i - 40) * 2.2) }
            if (70..<80).contains(i) { value = -88 + Double(i - 70) * 3 }
            let raw = Int(value + (i % 7 == 0 ? 9 : Double(i % 3) - 1))
            // 第 92–98 秒模拟一段真正的无信号
            if (92..<99).contains(i) {
                return SignalPoint(id: i, date: now.addingTimeInterval(t - 120), raw: nil, estimate: nil, segment: 0)
            }
            return SignalPoint(id: i, date: now.addingTimeInterval(t - 120), raw: raw, estimate: Int(value), segment: i >= 99 ? 1 : 0)
        }

        let names = [("我的 Apple Watch", -54), ("我的 iPhone", -61), ("MX Keys", -66), ("会议室 Apple TV", -78), ("Galaxy Buds", -82)]
        discovered = names.enumerated().map { i, item in
            DiscoveredDevice(id: i == 0 ? (s.boundDeviceID ?? UUID()) : UUID(), name: item.0, hasName: true,
                             rssi: item.1, firstSeen: now.addingTimeInterval(Double(i)), lastSeen: now)
        }

        var sample = LockLog()
        sample.append(LockLogEntry(date: now.addingTimeInterval(-3600), kind: .observedLocked, reason: .away, latencySeconds: 16.2), now: now)
        sample.append(LockLogEntry(date: now.addingTimeInterval(-2400), kind: .blockedByActivity, reason: .away, note: "2 秒前有键盘输入"), now: now)
        sample.append(LockLogEntry(date: now.addingTimeInterval(-1200), kind: .warningCancelled, reason: .away), now: now)
        sample.append(LockLogEntry(date: now.addingTimeInterval(-300), kind: .observedLocked, reason: .lost, latencySeconds: 64.8), now: now)
        log = sample
    }

    // MARK: - 通知与记录

    private func notifySignalUnstable() {
        notifier.post(id: "signal-unstable", title: "Doorman：主设备信号不稳定",
                      body: "已取消这次锁屏。设备回到你身边并稳定 10 秒后，自动锁屏会重新启用。")
    }

    private func notifyNotReady(_ issue: MonitorIssue) {
        let name = settings.boundDeviceName ?? "随身设备"
        switch issue {
        case .bluetoothOff:
            notifier.post(id: "not-ready", title: "Doorman：蓝牙已关闭", body: "离开时不会自动锁屏。打开蓝牙后自动恢复。")
        case .bluetoothUnauthorized:
            notifier.post(id: "not-ready", title: "Doorman 没有蓝牙权限",
                          body: "请在「系统设置 › 隐私与安全性 › 蓝牙」中允许 Doorman。")
        case .notFoundAfterWake:
            notifier.post(id: "not-ready", title: "Doorman：监控未就绪",
                          body: "没有找到\(name)，离开时不会自动锁屏。设备回到附近后自动恢复；一直找不到请重新绑定。")
        }
        record(.monitorNotReady, note: issue.title)
    }

    private func record(_ kind: LockLogEntry.Kind, reason: LockReason? = nil, latency: Double? = nil, note: String? = nil) {
        let now = Date()
        log.append(LockLogEntry(date: now, kind: kind, reason: reason, latencySeconds: latency, note: note), now: now)
        logStore.save(log)
    }

    private func publish() {
        presence = presenceMachine.state
        lastRaw = presenceMachine.lastRaw
        estimate = presenceMachine.estimate
        gatePhase = gate.phase
        attempt = tracker.status
        session = sessionObserver.state
        lockMethodCanLock = lockMethod.canLock
        productState = ProductState.derive(
            hasDevice: settings.boundDeviceID != nil,
            autoLockEnabled: settings.autoLockEnabled,
            paused: paused,
            presence: presenceMachine.state,
            gateEndedByUser: gate.isEndedByUser,
            canLock: lockMethod.canLock
        )
    }
}
