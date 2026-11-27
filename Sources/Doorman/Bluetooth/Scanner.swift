@preconcurrency import CoreBluetooth
import Foundation

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var hasName: Bool
    var rssi: Int
    /// 首次出现时间。列表按它排序，位置不随信号跳动。
    let firstSeen: Date
    var lastSeen: Date
}

enum PermissionStatus: Equatable {
    case granted
    case notDetermined
    case denied
    case notNeeded
}

enum BluetoothAvailability: Equatable {
    case unknown
    case poweredOn
    case poweredOff
    case unauthorized
    case unsupported
}

/// CoreBluetooth 采样。
/// - 绑定设备用 CBPeer.identifier（本机生成，只当重连线索），启动时 retrievePeripherals 找回。
/// - 主动模式：连接后每秒 readRSSI；被动模式：扫描广播取 RSSI。
/// - 每个样本带上发起时的 epoch，唤醒后旧 epoch 的读数会被状态机丢弃。
/// 不读取任何系统私有蓝牙数据库。
@MainActor
final class Scanner: NSObject {
    var onSample: (@MainActor (_ rssi: Int, _ epoch: Int) -> Void)?
    var onAvailability: (@MainActor (BluetoothAvailability) -> Void)?
    var onDiscoveredChange: (@MainActor ([DiscoveredDevice]) -> Void)?

    /// 由 AppModel 与 PresenceMachine.epoch 保持同步。
    var epoch = 0
    var mode: SamplingMode = .active {
        didSet { if mode != oldValue { refreshMode() } }
    }

    private(set) var availability: BluetoothAvailability = .unknown
    private var central: CBCentralManager?
    private var boundID: UUID?
    private var boundPeripheral: CBPeripheral?
    private var running = false
    private var discoveryEnabled = false
    private var discovered: [UUID: DiscoveredDevice] = [:]
    private var rssiTimer: Timer?
    private var pendingReadEpoch: Int?
    private var lastDiscoveryEmit = Date.distantPast

    /// 设备列表只显示这个强度以上的设备
    private let discoveryMinimumRSSI = -85
    /// 多久没再收到广播就从列表移除
    private let discoveryStaleAfter: TimeInterval = 30

    override init() {
        super.init()
    }

    /// 蓝牙权限状态（不创建 CBCentralManager 也能读）。
    static var permission: PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// 第一次调用时才创建 CBCentralManager，此时系统会弹出蓝牙授权。
    func start() {
        running = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else {
            resumeWork()
        }
    }

    /// 暂停：停止扫描并断开连接。
    func stop() {
        running = false
        stopRSSITimer()
        central?.stopScan()
        if let p = boundPeripheral, p.state != .disconnected {
            central?.cancelPeripheralConnection(p)
        }
    }

    func bind(_ id: UUID?) {
        guard id != boundID else { return }
        if let p = boundPeripheral, p.state != .disconnected {
            central?.cancelPeripheralConnection(p)
        }
        stopRSSITimer()
        boundPeripheral = nil
        boundID = id
        resumeWork()
    }

    func setDiscovery(_ enabled: Bool) {
        discoveryEnabled = enabled
        if !enabled {
            discovered.removeAll()
            onDiscoveredChange?([])
        }
        updateScan()
    }

    // MARK: - 内部

    private func resumeWork() {
        guard let central, central.state == .poweredOn, running else { return }
        if let boundID, boundPeripheral == nil {
            boundPeripheral = central.retrievePeripherals(withIdentifiers: [boundID]).first
            boundPeripheral?.delegate = self
        }
        if mode == .active { connectIfNeeded() }
        updateScan()
    }

    private func refreshMode() {
        stopRSSITimer()
        if mode == .passive, let p = boundPeripheral, p.state != .disconnected {
            central?.cancelPeripheralConnection(p)
        }
        resumeWork()
    }

    private func connectIfNeeded() {
        guard mode == .active, running, let central, let p = boundPeripheral else { return }
        switch p.state {
        case .disconnected:
            central.connect(p, options: nil)
        case .connected:
            startRSSITimer()
        default:
            break
        }
    }

    /// 主动模式已连接时不需要扫描（省电）；被动模式、未连上或打开设备列表时扫描。
    private func updateScan() {
        guard let central, central.state == .poweredOn else { return }
        let activeConnected = mode == .active && boundPeripheral?.state == .connected
        let needScan = running && (discoveryEnabled || (boundID != nil && !activeConnected))
        if needScan {
            // 被动采样需要每个广播包都上报 RSSI；重复上报有耗电代价，M0 用数据决定是否保留。
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        } else if central.isScanning {
            central.stopScan()
        }
    }

    private func startRSSITimer() {
        guard rssiTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readRSSI() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rssiTimer = timer
        updateScan()
    }

    private func stopRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        pendingReadEpoch = nil
    }

    private func readRSSI() {
        guard running, let p = boundPeripheral, p.state == .connected else { return }
        pendingReadEpoch = epoch
        p.readRSSI()
    }

    fileprivate func handleState(_ state: CBManagerState) {
        let next: BluetoothAvailability
        switch state {
        case .poweredOn: next = .poweredOn
        case .poweredOff, .resetting: next = .poweredOff
        case .unauthorized: next = .unauthorized
        case .unsupported: next = .unsupported
        default: next = .unknown
        }
        if next != .poweredOn {
            stopRSSITimer()
            boundPeripheral = nil
        }
        availability = next
        onAvailability?(next)
        if next == .poweredOn { resumeWork() }
    }

    fileprivate func handleDiscover(_ peripheral: CBPeripheral, localName: String?, rssi: Int) {
        guard rssi < 0 else { return }
        let id = peripheral.identifier

        if id == boundID {
            if boundPeripheral == nil {
                boundPeripheral = peripheral
                peripheral.delegate = self
            }
            if mode == .passive || peripheral.state != .connected {
                onSample?(rssi, epoch)
            }
            connectIfNeeded()
        }

        guard discoveryEnabled, rssi >= discoveryMinimumRSSI else { return }
        let now = Date()
        let realName = localName ?? peripheral.name
        let isNew = discovered[id] == nil
        if var existing = discovered[id] {
            existing.rssi = rssi
            existing.lastSeen = now
            if let realName, !existing.hasName {
                existing.name = realName
                existing.hasName = true
            }
            discovered[id] = existing
        } else {
            discovered[id] = DiscoveredDevice(
                id: id,
                name: realName ?? L("未命名设备（%@）", String(id.uuidString.prefix(8))),
                hasName: realName != nil,
                rssi: rssi,
                firstSeen: now,
                lastSeen: now
            )
        }

        // 广播很密集：新设备出现时立即刷新，否则每秒最多刷新一次，避免列表不停跳动
        guard isNew || now.timeIntervalSince(lastDiscoveryEmit) >= 1 else { return }
        lastDiscoveryEmit = now
        let cutoff = now.addingTimeInterval(-discoveryStaleAfter)
        discovered = discovered.filter { $0.value.lastSeen >= cutoff }
        onDiscoveredChange?(discovered.values.sorted { $0.firstSeen < $1.firstSeen })
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == boundID else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        startRSSITimer()
    }

    fileprivate func handleDisconnected(_ peripheral: CBPeripheral) {
        guard peripheral.identifier == boundID else { return }
        stopRSSITimer()
        updateScan()
        // CoreBluetooth 的 connect 不会超时，设备回到范围内会自动连上
        connectIfNeeded()
    }

    fileprivate func handleRSSI(_ peripheral: CBPeripheral, rssi: Int) {
        guard peripheral.identifier == boundID, let readEpoch = pendingReadEpoch else { return }
        pendingReadEpoch = nil
        onSample?(rssi, readEpoch)
    }
}

// CBCentralManager 用 queue: nil 创建，回调都在主线程。
extension Scanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated { self.handleState(state) }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let value = RSSI.intValue
        MainActor.assumeIsolated { self.handleDiscover(peripheral, localName: name, rssi: value) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { self.handleConnected(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { self.handleDisconnected(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { self.handleDisconnected(peripheral) }
    }
}

extension Scanner: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        let value = RSSI.intValue
        MainActor.assumeIsolated { self.handleRSSI(peripheral, rssi: value) }
    }
}
