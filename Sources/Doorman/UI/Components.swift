import AppKit
import Charts
import SwiftUI
import DoormanCore

// 说明：macOS 27 SDK 中 @State / @Binding 等是宏，Command Line Tools 不带 SwiftUI 宏插件。
// 本项目的界面局部状态一律用 ObservableObject + @StateObject，传值用 Binding 参数而非 @Binding。

// MARK: - 语义色

/// 全局统一的状态语义：绿 = 正常，橙 = 需要留意，红 = 即将发生 / 异常，蓝 = 信息，灰 = 中性。
enum Tone {
    case good, warn, bad, info, neutral

    var color: Color {
        switch self {
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        case .info: return .blue
        case .neutral: return .secondary
        }
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.color).frame(width: 7, height: 7)
            Text(text).font(AppFont.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.14), in: Capsule())
        .foregroundStyle(tone.color)
    }
}

struct Badge: View {
    let text: String
    var tone: Tone = .info

    var body: some View {
        Text(text)
            .font(AppFont.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tone.color.opacity(0.15), in: Capsule())
            .foregroundStyle(tone.color)
    }
}

// MARK: - 卡片

extension View {
    /// 浅色底的分组卡片，用于概览和弹出窗口。
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

// MARK: - 信号格与设备图标

struct SignalBars: View {
    let rssi: Int?

    var body: some View {
        Image(systemName: "cellularbars", variableValue: level)
            .foregroundStyle(rssi == nil ? Color.secondary : Color.primary)
            .help(rssi.map { "\($0) dBm" } ?? "无信号")
    }

    private var level: Double {
        guard let rssi else { return 0 }
        switch rssi {
        case (-55)...: return 1
        case (-65)...: return 0.75
        case (-75)...: return 0.5
        case (-85)...: return 0.25
        default: return 0.05
        }
    }
}

enum DeviceGlyph {
    static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("watch") { return "applewatch" }
        if n.contains("iphone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("airpods") { return "airpodspro" }
        if n.contains("macbook") || n.contains("imac") || n.contains("mac mini") { return "laptopcomputer" }
        if n.contains("keyboard") || n.contains("键盘") || n.contains("keys") { return "keyboard" }
        if n.contains("mouse") || n.contains("鼠标") || n.contains("mx master") || n.contains("trackpad") { return "computermouse" }
        return "dot.radiowaves.left.and.right"
    }

    /// 随身佩戴、适合做主设备的类型
    static func isWearable(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("watch") || n.contains("iphone")
    }
}

// MARK: - 迷你信号曲线

struct Sparkline: View {
    let points: [SignalPoint]
    let leaveRSSI: Int
    var seconds: TimeInterval = 60

    var body: some View {
        let now = points.last?.date ?? Date()
        let start = now.addingTimeInterval(-seconds)
        let visible = points.filter { $0.estimate != nil && $0.date >= start }
        Chart {
            RuleMark(y: .value("离开阈值", leaveRSSI))
                .foregroundStyle(Color.red.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(visible) { point in
                LineMark(
                    x: .value("时间", point.date),
                    y: .value("信号", point.estimate ?? 0),
                    series: .value("段", point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartYScale(domain: -100 ... -30)
        .chartXScale(domain: start ... now)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .clipped()
    }
}

// MARK: - 问题横幅

struct IssueBanner: View {
    let message: String
    let actionTitle: String
    var tone: Tone = .warn
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(tone.color)
            Text(message)
                .font(AppFont.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.color.opacity(0.12))
        )
    }
}

// MARK: - 权限行

struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(AppFont.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.body.weight(.medium))
                Text(detail).font(AppFont.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            switch status {
            case .granted:
                Label("已允许", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(AppFont.callout.weight(.medium))
            case .notNeeded:
                Text("不需要").foregroundStyle(.secondary).font(AppFont.callout)
            case .notDetermined:
                Button("允许…", action: action).buttonStyle(.borderedProminent).controlSize(.small)
            case .denied:
                VStack(alignment: .trailing, spacing: 2) {
                    Text("已拒绝").foregroundStyle(.red).font(AppFont.caption.weight(.semibold))
                    Button("打开系统设置", action: action).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 悬停高亮的菜单行

@MainActor
final class HoverState: ObservableObject {
    @Published var hovering = false
}

struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @StateObject private var hover = HoverState()

    init(_ title: String, symbol: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.tertiary).font(AppFont.callout)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover.hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.hovering = $0 }
    }
}

// MARK: - Dock 图标

/// 菜单栏 App 平时不显示 Dock 图标；有窗口打开时显示，全部关闭后隐藏。
@MainActor
enum DockPresence {
    private static var openWindows = 0

    static func windowOpened() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func windowClosed() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

// MARK: - 表单脚注

/// grouped Form 的 footer 默认右对齐，长句读起来别扭；统一左对齐。
struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 字号

/// 全局字号。macOS HIG 默认正文 13pt、辅助文字 10–12pt，桌面距离下偏小；
/// 这里整体放大到主流 Mac 效率类 App 的水平：正文 15pt，辅助文字不低于 12pt。
enum AppFont {
    static let largeTitle = Font.system(size: 30, weight: .bold)
    static let title = Font.system(size: 24, weight: .bold)
    static let title2 = Font.system(size: 20, weight: .semibold)
    static let title3 = Font.system(size: 17, weight: .regular)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
    static let callout = Font.system(size: 14)
    static let caption = Font.system(size: 13)
    static let caption2 = Font.system(size: 12)
    /// 侧边栏
    static let sidebar = Font.system(size: 15)
}

// MARK: - 帮助问号

@MainActor
final class HelpTipState: ObservableObject {
    @Published var showing = false
}

/// 标准的小问号：鼠标悬停时弹出说明，移开即关闭。
struct HelpTip: View {
    let text: String
    @StateObject private var state = HelpTipState()

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(AppFont.callout)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { state.showing = $0 }
            .popover(isPresented: $state.showing, arrowEdge: .bottom) {
                Text(text)
                    .font(AppFont.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 300, alignment: .leading)
                    .padding(14)
            }
            .accessibilityLabel(Text("说明"))
            .accessibilityHint(Text(text))
    }
}

/// 术语标签：灰色文字 + 小问号
struct Term: View {
    let title: String
    let help: String

    init(_ title: String, _ help: String) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            HelpTip(help)
        }
    }
}

/// 诊断页术语说明
enum Glossary {
    static let presence = "根据蓝牙信号判断随身设备在不在你身边。\n在场：信号够强。\n离开中：信号变弱，正在倒计时。\n已离开：倒计时结束。\n失联：一段时间收不到任何信号。"
    static let gate = "设备判定离开后的一道保险：键盘、鼠标、触控板空闲满设定时间（默认 10 秒）才会出现锁屏倒计时；刚有操作就拦截，不锁屏。倒计时期间碰一下就取消这一轮。"
    static let request = "Doorman 发出锁屏命令后，等系统确认屏幕是否真的锁上。\n执行前放弃：调用锁屏前一刻发现你在操作，已取消。\n锁屏未确认：几秒内没等到系统确认。"
    static let session = "系统报告的屏幕当前状态：未锁、已锁或未知。只反映事实，不区分是你锁的还是 Doorman 锁的。"
    static let rssi = "原始：最新一次蓝牙读数。\n滤波：最近几次读数的中位数，用来过滤偶发跳变，离开判断以它为准。\n单位 dBm，越接近 0 信号越强。"
    static let idle = "距离你最后一次操作键盘、鼠标或触控板过了多久。只读取时间，不记录按键内容。"
    static let product = "综合以上信息，Doorman 此刻能否自动锁屏：自动锁屏可用、仅提醒，或监控未就绪。"
    static let lockCalls = "本次运行中，Doorman 因为你离开而真正调用系统锁屏的次数，不含手动锁屏。用来验证「用着电脑时不会被锁」。"
    static let lockMethod = "M0 是正式开发前的可行性验证。这里可以切换不同的锁屏实现，比较哪种能稳定锁屏、并被系统确认。"
}
