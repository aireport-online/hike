import Charts
import HikeCore
import SwiftUI

/// Height along the route. Dragging over it reports the distance under the finger, which the
/// map uses to show where on the route that is.
struct ElevationChart: View {
    let samples: [RouteGeometry.Sample]
    @Binding var scrubDistance: Double?

    @State private var selectedKilometres: Double?

    private var selectedSample: RouteGeometry.Sample? {
        guard let selectedKilometres else { return nil }
        let distance = selectedKilometres * 1000
        return samples.min { abs($0.distance - distance) < abs($1.distance - distance) }
    }

    var body: some View {
        let elevations = samples.map(\.elevation)
        let lowest = elevations.min() ?? 0
        let highest = elevations.max() ?? 0
        let padding = max(10, (highest - lowest) * 0.12)
        let lower = (lowest - padding).rounded(.down)
        let upper = (highest + padding).rounded(.up)
        let length = max((samples.last?.distance ?? 0) / 1000, 0.1)

        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let selectedSample {
                    Text("\(HikeFormat.distance(selectedSample.distance)) · \(HikeFormat.elevation(selectedSample.elevation)) hoogte")
                        .foregroundStyle(.primary)
                } else {
                    Text("Hoogteprofiel · \(HikeFormat.elevation(lowest)) – \(HikeFormat.elevation(highest))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()

            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Afstand", sample.distance / 1000),
                        yStart: .value("Basis", lower),
                        yEnd: .value("Hoogte", sample.elevation)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.25))

                    LineMark(
                        x: .value("Afstand", sample.distance / 1000),
                        y: .value("Hoogte", sample.elevation)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                if let selectedSample {
                    RuleMark(x: .value("Afstand", selectedSample.distance / 1000))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("Afstand", selectedSample.distance / 1000),
                        y: .value("Hoogte", selectedSample.elevation)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(60)
                }
            }
            .chartXScale(domain: 0...length)
            .chartYScale(domain: lower...upper)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let kilometres = value.as(Double.self) {
                            Text("\(kilometres.formatted(.number.precision(.fractionLength(0...1)))) km")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let metres = value.as(Double.self) {
                            Text("\(Int(metres)) m")
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedKilometres)
            .onChange(of: selectedKilometres) { _, kilometres in
                scrubDistance = kilometres.map { $0 * 1000 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hoogteprofiel van \(HikeFormat.elevation(lowest)) tot \(HikeFormat.elevation(highest))")
    }
}
