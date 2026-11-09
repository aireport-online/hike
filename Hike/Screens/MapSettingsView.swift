import HikeCore
import SwiftUI

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var mapStyleRaw: String
    @Binding var showsTrails: Bool
    @Binding var paceRaw: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Kaart") {
                    ForEach(MapStyle.allCases) { style in
                        Button {
                            mapStyleRaw = style.rawValue
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.title)
                                        .foregroundStyle(Color(.label))
                                    Text(style.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                                Spacer(minLength: 0)
                                if style.rawValue == mapStyleRaw {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Gemarkeerde wandelroutes", isOn: $showsTrails)
                } footer: {
                    Text("Toont bewegwijzerde routes zoals GR-paden, E-paden en nationale langeafstandspaden als gekleurde lijnen op de kaart.")
                }

                Section {
                    Picker("Tempo", selection: $paceRaw) {
                        ForEach(Pace.allCases, id: \.rawValue) { pace in
                            Text(pace.title).tag(pace.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Wandeltijd")
                } footer: {
                    Text("Normaal rekent met 4 km per uur, 300 m stijgen en 500 m dalen per uur, zonder pauzes.")
                }

                Section("Bronnen") {
                    Text("Kaartgegevens © OpenStreetMap-bijdragers. Topografische kaart: OpenTopoMap (CC-BY-SA), hoogtegegevens SRTM. Wandelroutes: Waymarked Trails. Routeberekening: BRouter. Zoeken: Photon van Komoot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kaart en tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}
