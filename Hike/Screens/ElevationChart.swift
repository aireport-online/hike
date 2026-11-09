import Charts
import HikeCore
import SwiftUI

/// Height along the route, drawn as a solid silhouette on the signpost plate. Dragging over it
/// reports the distance under the finger, which the map uses to show where on the route that is.
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
                    Text("\(HikeFormat.distance(selectedSample.distance)) · \(HikeFormat.elevation(selectedSample.elevation)) HOOGTE")
                } else {
                    Text("HOOGTEPROFIEL · \(HikeFormat.elevation(lowest)) – \(HikeFormat.elevation(highest))")
                        .foregroundStyle(Brand.ink.opacity(0.7))
                }
            }
            .font(.signLabel(13))
            .monospacedDigit()

            Chart {
                ForEach(samples) { sample in
                    AreaMark(
                        x: .value("Afstand", sample.distance / 1000),
                        yStart: .value("Basis", lower),
                        yEnd: .value("Hoogte", sample.elevation)
                    )
                    .foregroundStyle(Brand.ink)
                }

                if let selectedSample {
                    RuleMark(x: .value("Afstand", selectedSample.distance / 1000))
                        .foregroundStyle(Brand.blaze)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("Afstand", selectedSample.distance / 1000),
                        y: .value("Hoogte", selectedSample.elevation)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(50)
                }
            }
            .chartXScale(domain: 0...length)
            .chartYScale(domain: lower...upper)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let kilometres = value.as(Double.self) {
                            Text("\(kilometres.formatted(.number.precision(.fractionLength(0...1)))) km")
                                .font(.signLabel(11))
                                .fixedSize()
                                .foregroundStyle(Brand.ink.opacity(0.8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                        .foregroundStyle(Brand.ink.opacity(0.35))
                    AxisValueLabel {
                        if let metres = value.as(Double.self) {
                            // Formatted the same way as the figures above the chart.
                            Text(HikeFormat.elevation(metres))
                                .font(.signLabel(11))
                                .foregroundStyle(Brand.ink.opacity(0.8))
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
