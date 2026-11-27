import AppKit
import SwiftUI

/// 调试截图：把主要界面渲染成 PNG，用于设计走查。
/// 用法：DOORMAN_SNAPSHOT_DIR=/某个目录 dist/Doorman.app/Contents/MacOS/Doorman
/// 只写入该目录下固定文件名的 PNG。
@MainActor
enum SnapshotRenderer {
    static func renderAll(model: AppModel, to directory: URL) {
        let fm = FileManager.default
        guard directory.isFileURL, directory.path.hasPrefix("/") else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (suffix, name) in appearances {
            guard let appearance = NSAppearance(named: name) else { continue }
            render(MenuPopover(model: model), size: fittingSize(MenuPopover(model: model), width: 350),
                   appearance: appearance, to: directory.appendingPathComponent("menu-\(suffix).png"))
            for section in SettingsSection.allCases {
                model.settingsSection = section
                render(SettingsView(model: model), size: CGSize(width: 920, height: 700),
                       appearance: appearance, to: directory.appendingPathComponent("settings-\(section.rawValue)-\(suffix).png"))
            }
            render(OnboardingView(model: model, onFinish: {}), size: CGSize(width: 700, height: 620),
                   appearance: appearance, to: directory.appendingPathComponent("onboarding-\(suffix).png"))
            let warning = WarningModel()
            warning.remaining = 3
            warning.total = 5
            warning.deviceName = model.deviceName
            render(WarningView(model: warning), size: CGSize(width: 900, height: 560),
                   appearance: appearance, to: directory.appendingPathComponent("warning-\(suffix).png"))
        }
    }

    /// 按内容高度截图（菜单栏弹出窗口高度随内容变化）
    private static func fittingSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let probe = NSHostingView(rootView: view.frame(width: width))
        return CGSize(width: width, height: ceil(probe.fittingSize.height))
    }

    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
