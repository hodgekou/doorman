import AppKit
import SwiftUI
import DoormanCore

@MainActor
final class WarningModel: ObservableObject {
    @Published var remaining = 0
    @Published var total = 5
    @Published var deviceName = ""
}

/// 锁前倒计时：每块屏幕一个非激活的置顶面板。
/// 不抢焦点、点击穿透（ignoresMouseEvents），键盘输入照常进入当前应用；
/// 取消靠读取键鼠空闲时长判断，不靠点击倒计时本身。
@MainActor
final class WarningOverlay {
    private let model = WarningModel()
    private var panels: [NSPanel] = []
    private var until: Instant?

    func show(until: Instant, total: Int, deviceName: String) {
        self.until = until
        model.total = max(1, total)
        model.deviceName = deviceName
        update(now: .now)
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // 全屏应用和所有桌面空间上都可见（外接显示器、全屏场景待真机验证）
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: WarningView(model: model))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func update(now: Instant) {
        guard let until else { return }
        model.remaining = max(0, Int((until - now).secondsValue.rounded(.up)))
    }

    func hide() {
        until = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

struct WarningView: View {
    @ObservedObject var model: WarningModel

    private var progress: Double {
        Double(model.remaining) / Double(model.total)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: model.remaining)
                    Text("\(model.remaining)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 96, height: 96)
                Text(L("看起来你离开了"))
                    .font(AppFont.title2.weight(.semibold))
                Text(L("%1$@ 信号变弱，%2$d 秒后锁定这台 Mac", model.deviceName, model.remaining))
                    .foregroundStyle(.secondary)
                Label(L("动一下鼠标或键盘即可取消"), systemImage: "cursorarrow.motionlines")
                    .font(AppFont.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}
