import SwiftUI
import Charts
import LatchDomain

/// The center **live timeline**: a header, then five stacked lanes. Four are genuine live lanes
/// (CPU, Memory, Network, Energy watts-estimate) drawing the per-target ring buffer over the
/// selected range; the fifth, Frame time, is gated as a hint (no live counter for an external
/// attach — the Time Profiler run is the ground truth). (SPEC §1, §8; PLAN slice 11)
struct TimelineView: View {
    let model: VitalsModel

    /// The plot column starts after the 170px gutter + its 1px divider.
    private static let gutterWidth: CGFloat = 171

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LatchTheme.hairline)
            ZStack(alignment: .topLeading) {
                lanes
                MarkerOverlay(model: model)
                    .padding(.leading, Self.gutterWidth)
            }
        }
        .background(LatchTheme.center)
    }

    private var lanes: some View {
        VStack(spacing: 0) {
            ForEach(LaneKind.allCases) { lane in
                LaneRow(lane: lane, model: model)
                if lane != LaneKind.allCases.last {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Circle().fill(LatchTheme.critical).frame(width: 8, height: 8)
            Text("Live timeline").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LatchTheme.textPrimary)
            Text("sampling · ~1 Hz").font(.system(size: 11))
                .foregroundStyle(LatchTheme.textFaint)
            Spacer()
            Text("\(model.visibleSamples.count) samples · \(model.range.label) window")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(LatchTheme.textFaint)
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(LatchTheme.timelineHeader)
    }
}

/// One lane: a fixed gutter (color swatch, name, scale hint, big current value) beside its plot.
/// The gutter and plot share the row so they stay aligned. The frame lane shows a hint instead
/// of a chart — it has no live series. (SPEC §8)
private struct LaneRow: View {
    let lane: LaneKind
    let model: VitalsModel

    var body: some View {
        HStack(spacing: 0) {
            gutter.frame(width: 170)
            Divider().overlay(LatchTheme.hairline)
            plot.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LatchTheme.laneGutter)
    }

    private var gutter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(lane.color).frame(width: 9, height: 9)
                Text(lane.title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LatchTheme.textSecondary)
                Spacer()
                Text(lane.scaleHint).font(.system(size: 9)).foregroundStyle(LatchTheme.textFaint)
            }
            Text(lane.formattedValue(from: model.latest))
                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                .foregroundStyle(lane.isLive ? .white : LatchTheme.textFaint)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private var plot: some View {
        if lane.isLive {
            LaneChart(lane: lane, samples: model.visibleSamples)
        } else {
            Text("Frame time is a deep-run signal — record a Time Profiler trace to inspect it.")
                .font(.system(size: 11)).foregroundStyle(LatchTheme.textFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }
}

/// Vertical **detection markers** across the plot column: one line per live-hint detection whose
/// sample is still inside the visible window, colored by severity, dashed until selected. Clicking a
/// marker opens that detection's detail — the same feed the inbox drives. Deep runs have no marker
/// (they aren't a point on the live stream — inbox only). (SPEC §8; PLAN slice 12)
private struct MarkerOverlay: View {
    let model: VitalsModel

    /// Match the lane chart's internal horizontal padding so a marker lines up with its samples.
    private static let plotInset: CGFloat = 8

    private var markers: [(detection: Detection, fraction: Double)] {
        model.detections.compactMap { detection in
            model.markerFraction(for: detection).map { (detection, $0) }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - Self.plotInset * 2, 1)
            ForEach(markers, id: \.detection.id) { marker in
                markerLine(marker.detection, isSelected: marker.detection.id == model.selectedDetectionID)
                    .position(
                        x: Self.plotInset + usable * marker.fraction,
                        y: geometry.size.height / 2
                    )
                    .frame(width: 11, height: geometry.size.height)
            }
        }
    }

    private func markerLine(_ detection: Detection, isSelected: Bool) -> some View {
        let color = detection.severity.color
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(color.opacity(isSelected ? 1 : 0.5))
                .frame(width: isSelected ? 2 : 1)
            Triangle().fill(color).frame(width: 7, height: 6)
        }
        .frame(width: 11)
        .contentShape(Rectangle())
        .onTapGesture { model.selectDetection(detection.id) }
    }
}

/// A small downward flag at the top of a marker.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A filled area + line plot of one live lane over its visible samples, styled to the lane color.
/// Axes are hidden for the pro-tool timeline look; the value is read off the gutter. (SPEC §8)
private struct LaneChart: View {
    let lane: LaneKind
    let samples: [MetricSample]

    private var points: [(index: Int, value: Double)] {
        samples.enumerated().compactMap { offset, sample in
            lane.value(from: sample).map { (index: offset, value: $0) }
        }
    }

    var body: some View {
        Chart(points, id: \.index) { point in
            AreaMark(x: .value("t", point.index), y: .value(lane.title, point.value))
                .foregroundStyle(lane.color.opacity(0.18))
            LineMark(x: .value("t", point.index), y: .value(lane.title, point.value))
                .foregroundStyle(lane.color)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}
