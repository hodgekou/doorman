import AppKit
import SwiftUI
import DoormanCore

/// 菜单栏弹出窗口：一眼看清是否被保护，常用操作一步到位。
struct MenuPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: 12) {
            header(summary)
            deviceCard(summary)
            if let issue = summary.issue {
                IssueBanner(message: issue.message, actionTitle: issue.actionTitle) {
                    model.perform(issue.fix)
                }
            }
            actions
            if let last = model.lastLockDescription {
                Text(last)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 0) {
                MenuRow("设置…", symbol: "gearshape", shortcut: "⌘,") { model.openSettings(model.settingsSection ?? .overview) }
                    .keyboardShortcut(",")
                MenuRow("退出 Doorman", symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .font(AppFont.body)
        .frame(width: 350)
    }

    private func header(_ summary: StatusSummary) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("Doorman").font(AppFont.headline)
            Spacer()
            StatusPill(text: summary.headline, tone: summary.tone)
        }
    }

    @ViewBuilder
    private func deviceCard(_ summary: StatusSummary) -> some View {
        if model.settings.boundDeviceID != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: model.deviceSymbol)
                        .font(AppFont.title3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.deviceName).font(AppFont.body.weight(.medium)).lineLimit(1)
                        Text(summary.deviceDetail ?? summary.detail).font(AppFont.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    SignalBars(rssi: model.estimate)
                }
                Sparkline(points: model.signalHistory, leaveRSSI: model.settings.leaveRSSI)
                    .frame(height: 34)
            }
            .card(padding: 12)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(AppFont.title2)
                    .foregroundStyle(.secondary)
                Text(summary.detail).font(AppFont.callout).foregroundStyle(.secondary)
            }
            .card(padding: 12)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                model.lockNow()
            } label: {
                Label("立即锁屏", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if model.paused {
                Button {
                    model.resume()
                } label: {
                    Label("恢复", systemImage: "play.fill")
                }
                .controlSize(.large)
            } else {
                Menu {
                    Button("15 分钟") { model.pause(minutes: 15) }
                    Button("1 小时") { model.pause(minutes: 60) }
                    Button("3 小时") { model.pause(minutes: 180) }
                    Divider()
                    Button("直到我恢复") { model.pause(minutes: nil) }
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
                .menuStyle(.borderedButton)
                .controlSize(.large)
                .fixedSize()
                .disabled(model.settings.boundDeviceID == nil)
            }
        }
    }
}
