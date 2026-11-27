import SwiftUI
import DoormanCore

@MainActor
final class DevicePickerState: ObservableObject {
    @Published var selectedID: UUID?
    @Published var namedOnly = true
    /// 点「按信号排序」时的快照；nil 时按出现先后排序，位置不随信号跳动
    @Published var signalOrder: [UUID]?
}

/// 设备选择器：先点选，再确认。设置窗口和首次引导共用。
struct DevicePicker: View {
    @ObservedObject var model: AppModel
    var listHeight: CGFloat = 240
    var onBound: (() -> Void)?
    @StateObject private var ui = DevicePickerState()

    init(model: AppModel, listHeight: CGFloat = 240, onBound: (() -> Void)? = nil) {
        self.model = model
        self.listHeight = listHeight
        self.onBound = onBound
    }

    private var visible: [DiscoveredDevice] {
        let list = model.discovered.filter { !ui.namedOnly || $0.hasName }
        guard let order = ui.signalOrder else { return list }
        func rank(_ d: DiscoveredDevice) -> Int { order.firstIndex(of: d.id) ?? Int.max }
        return list.sorted { (rank($0), $0.firstSeen) < (rank($1), $1.firstSeen) }
    }

    /// 推荐：信号最强的手表或手机
    private var recommendedID: UUID? {
        model.discovered
            .filter { $0.hasName && DeviceGlyph.isWearable($0.name) }
            .max { $0.rssi < $1.rssi }?
            .id
    }

    private var selected: DiscoveredDevice? {
        model.discovered.first { $0.id == ui.selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("只显示有名称的设备", isOn: $ui.namedOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(ui.signalOrder == nil ? "按信号排序" : "恢复默认顺序") {
                    ui.signalOrder = ui.signalOrder == nil
                        ? model.discovered.sorted { $0.rssi > $1.rssi }.map(\.id)
                        : nil
                }
                .buttonStyle(.link)
            }
            .font(AppFont.callout)

            ScrollView {
                VStack(spacing: 0) {
                    if visible.isEmpty {
                        emptyState
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, device in
                        row(device)
                        if index < visible.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
            // 高度随内容变化，最多 listHeight，避免设备少时留下大片空白
            .frame(height: visible.isEmpty ? min(listHeight, 150) : min(listHeight, CGFloat(visible.count) * 37 + 2))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1))
            )

            HStack {
                if let selected {
                    Image(systemName: DeviceGlyph.symbol(for: selected.name)).foregroundStyle(.secondary)
                    Text(selected.name).lineLimit(1)
                } else {
                    Text("在列表中点选你的设备").foregroundStyle(.secondary)
                }
                Spacer()
                Button("使用这台设备") {
                    guard let selected else { return }
                    model.bind(selected)
                    onBound?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || selected?.id == model.settings.boundDeviceID)
            }
            .font(AppFont.callout)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if model.bluetooth == .poweredOn {
                ProgressView().controlSize(.small)
                Text("正在寻找附近的设备…").foregroundStyle(.secondary)
                Text("确认手表或手机已解锁并放在 Mac 旁边").font(AppFont.caption).foregroundStyle(.tertiary)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(AppFont.title2).foregroundStyle(.secondary)
                Text(model.bluetoothHint).font(AppFont.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.horizontal, 20)
    }

    private func row(_ device: DiscoveredDevice) -> some View {
        let isSelected = device.id == ui.selectedID
        let isBound = device.id == model.settings.boundDeviceID
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(AppFont.body)
            Image(systemName: DeviceGlyph.symbol(for: device.name))
                .font(AppFont.title3)
                .frame(width: 24)
                .foregroundStyle(device.hasName ? Color.primary : Color.secondary)
            Text(device.name)
                .foregroundStyle(device.hasName ? Color.primary : Color.secondary)
                .lineLimit(1)
            if isBound {
                Badge(text: "当前使用", tone: .good)
            } else if device.id == recommendedID {
                Badge(text: "推荐", tone: .info)
            }
            Spacer()
            SignalBars(rssi: device.rssi)
            Text("\(device.rssi)")
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { ui.selectedID = device.id }
    }
}
