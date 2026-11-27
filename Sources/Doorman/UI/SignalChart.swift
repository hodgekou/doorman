import Charts
import SwiftUI

/// 实时信号图：灰点为原始读数，主色线为平滑后的信号，虚线为「回到身边 / 判定离开」阈值。最近 120 秒。
struct SignalChart: View {
    let points: [SignalPoint]
    let presentRSSI: Int
    let leaveRSSI: Int
    var seconds: TimeInterval = 120

    var body: some View {
        let now = points.last?.date ?? Date()
        let start = now.addingTimeInterval(-seconds)
        let visible = points.filter { $0.date >= start }
        Chart {
            // 超过 3 秒没有读数的时段：灰色底，表示「无信号」
            ForEach(Self.gaps(in: visible)) { gap in
                RectangleMark(
                    xStart: .value(L("开始"), gap.start),
                    xEnd: .value(L("结束"), gap.end),
                    yStart: .value(L("下"), -100),
                    yEnd: .value(L("上"), -30)
                )
                .foregroundStyle(Color.gray.opacity(0.14))
            }
            RuleMark(y: .value(L("回到身边"), presentRSSI))
                .foregroundStyle(Color.green.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            RuleMark(y: .value(L("判定离开"), leaveRSSI))
                .foregroundStyle(Color.red.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ForEach(visible.filter { $0.raw != nil }) { point in
                PointMark(
                    x: .value(L("时间"), point.date),
                    y: .value(L("原始读数"), point.raw ?? 0)
                )
                .symbolSize(12)
                .foregroundStyle(Color.gray.opacity(0.45))
            }
            ForEach(visible.filter { $0.estimate != nil }) { point in
                LineMark(
                    x: .value(L("时间"), point.date),
                    y: .value(L("信号"), point.estimate ?? 0),
                    series: .value(L("段"), point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartYScale(domain: -100 ... -30)
        .chartXScale(domain: start ... now)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-40, -60, -80, -100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)").font(AppFont.caption2) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [start, now.addingTimeInterval(-seconds / 2), now]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Self.relativeLabel(date, now: now)).font(AppFont.caption2) }
                }
            }
        }
        .clipped()
        .frame(minHeight: 160, idealHeight: 220)
    }

    struct Gap: Identifiable {
        let id: Int
        let start: Date
        let end: Date
    }

    /// 连续的无信号点合并成一段，前后各扩半秒让单点空档也可见
    static func gaps(in points: [SignalPoint]) -> [Gap] {
        var result: [Gap] = []
        var start: Date?
        var last: Date?
        func close() {
            if let s = start, let l = last {
                result.append(Gap(id: result.count, start: s.addingTimeInterval(-0.5), end: l.addingTimeInterval(0.5)))
            }
            start = nil
            last = nil
        }
        for point in points {
            if point.estimate == nil {
                if start == nil { start = point.date }
                last = point.date
            } else {
                close()
            }
        }
        close()
        return result
    }

    private static func relativeLabel(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 5 { return L("现在") }
        if seconds % 60 == 0 { return L("%d 分钟前", seconds / 60) }
        return L("%d 秒前", seconds)
    }
}
