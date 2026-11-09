import HikeCore
import SwiftUI

/// Finds a place to plan around: a town, a summit, a lake, a mountain hut.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss

    /// Places near this point are listed first.
    let near: Coordinate?
    var onPick: (Place) -> Void

    @State private var query = ""
    @State private var places: [Place] = []
    @State private var isSearching = false
    @State private var failure: String?

    private let client = PhotonClient()

    var body: some View {
        NavigationStack {
            List(places) { place in
                Button {
                    onPick(place)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: place.kind))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .foregroundStyle(Color(.label))
                            if !place.detail.isEmpty {
                                Text(place.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if places.isEmpty {
                    placeholder
                }
            }
            .navigationTitle("Zoeken")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Plaats, berg, meer of hut"
            )
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
            }
            .task(id: query) {
                await search()
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure {
            ContentUnavailableView("Zoeken lukt niet", systemImage: "wifi.slash", description: Text(failure))
        } else if isSearching {
            ProgressView()
        } else if text.count < 2 {
            ContentUnavailableView(
                "Waar wil je wandelen?",
                systemImage: "mountain.2",
                description: Text("Zoek door heel Europa op plaatsnaam, bergtop, meer, pas of berghut.")
            )
        } else {
            ContentUnavailableView.search(text: text)
        }
    }

    private func symbol(for kind: Place.Kind) -> String {
        switch kind {
        case .peak: return "mountain.2.fill"
        case .water: return "water.waves"
        case .hut: return "house.lodge.fill"
        case .settlement: return "building.2.fill"
        case .other: return "mappin"
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            places = []
            failure = nil
            isSearching = false
            return
        }
        // Wait for a pause in typing before asking the server.
        isSearching = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        do {
            let found = try await client.search(text, near: near)
            guard !Task.isCancelled else { return }
            places = found
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            places = []
            failure = error.localizedDescription
        }
        isSearching = false
    }
}
