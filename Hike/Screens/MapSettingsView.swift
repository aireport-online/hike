import HikeCore
import SwiftUI

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var mapStyleRaw: String
    @Binding var showsTrails: Bool
    @Binding var paceRaw: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Kaart") {
                        VStack(spacing: 8) {
                            ForEach(MapStyle.allCases) { style in
                                styleRow(style)
                            }
                        }
                    }

                    section("Wandelroutes") {
                        Toggle(isOn: $showsTrails) {
                            Text("Bewegwijzerde routes zoals GR-paden, E-paden en langeafstandspaden als gekleurde lijnen op de kaart.")
                                .font(.text(15, relativeTo: .subheadline))
                                .foregroundStyle(Brand.line.opacity(0.75))
                        }
                        .tint(Brand.blaze)
                    }

                    section("Tempo") {
                        VStack(alignment: .leading, spacing: 8) {
                            SignSwitch(
                                options: Pace.allCases.map { SignSwitch<String>.Option(value: $0.rawValue, title: $0.title) },
                                selection: $paceRaw
                            )
                            Text("Normaal rekent met 4 km per uur, 300 m stijgen en 500 m dalen per uur, zonder pauzes.")
                                .font(.text(14, relativeTo: .footnote))
                                .foregroundStyle(Brand.line.opacity(0.7))
                        }
                    }

                    section("Bronnen") {
                        Text("Kaartgegevens © OpenStreetMap-bijdragers. Topografische kaart: OpenTopoMap (CC-BY-SA), hoogtegegevens SRTM. Wandelroutes: Waymarked Trails. Routeberekening: BRouter. Zoeken: Photon van Komoot. Lettertype: Barlow (SIL Open Font License).")
                            .font(.text(13, relativeTo: .footnote))
                            .foregroundStyle(Brand.line.opacity(0.7))
                    }
                }
                .padding(20)
            }
            .background(Brand.paper.ignoresSafeArea())
            .signTitle("Kaart en tempo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                        .font(.textStrong(17))
                }
            }
        }
        .tint(Brand.line)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SignHeading(title: title)
            content()
        }
    }

    /// The chosen map is a yellow plate with the blaze; the others are plain outlined plates.
    private func styleRow(_ style: MapStyle) -> some View {
        let isOn = style.rawValue == mapStyleRaw
        let colour = isOn ? Brand.ink : Brand.line

        return Button {
            mapStyleRaw = style.rawValue
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title.uppercased())
                        .font(.sign(20, relativeTo: .headline))
                    Text(style.subtitle)
                        .font(.text(14, relativeTo: .caption))
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
                if isOn {
                    BlazeMark()
                        .frame(width: 26, height: 18)
                }
            }
            .foregroundStyle(colour)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Brand.yellow : Color.clear, in: RoundedRectangle(cornerRadius: Brand.corner))
            .overlay {
                RoundedRectangle(cornerRadius: Brand.corner)
                    .strokeBorder(colour, lineWidth: Brand.outline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
