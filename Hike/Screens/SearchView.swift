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
                    HStack(spacing: 14) {
                        Image(systemName: symbol(for: place.kind))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Brand.line)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name.uppercased())
                                .font(.sign(21, relativeTo: .title3))
                                .foregroundStyle(Brand.line)
                            Text(subtitle(for: place))
                                .font(.text(14, relativeTo: .subheadline))
                                .foregroundStyle(Brand.line.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Brand.line.opacity(0.5))
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Brand.paper)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.paper.ignoresSafeArea())
            .overlay {
                if places.isEmpty {
                    placeholder
                }
            }
            .signTitle("Zoeken")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Plaats, berg, meer of hut"
            )
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                        .font(.textStrong(17))
                }
            }
            .task(id: query) {
                await search()
            }
        }
        .tint(Brand.line)
    }

    @ViewBuilder
    private var placeholder: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let failure {
            message("ZOEKEN LUKT NIET", symbol: "wifi.slash", detail: failure)
        } else if isSearching {
            ProgressView()
        } else if text.count < 2 {
            message(
                "WAAR WIL JE WANDELEN?",
                symbol: "mountain.2",
                detail: "Zoek door heel Europa op plaatsnaam, bergtop, meer, pas of berghut."
            )
        } else {
            message("NIETS GEVONDEN", symbol: "magnifyingglass", detail: "Geen plaats gevonden voor \u{201C}\(text)\u{201D}.")
        }
    }

    private func message(_ title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Brand.line)
            Text(title)
                .font(.sign(26, relativeTo: .title2))
                .foregroundStyle(Brand.line)
            Text(detail)
                .font(.text(16))
                .foregroundStyle(Brand.line.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func subtitle(for place: Place) -> String {
        let kind: String
        switch place.kind {
        case .peak: kind = "Top"
        case .water: kind = "Water"
        case .hut: kind = "Hut"
        case .settlement: kind = "Plaats"
        case .other: kind = ""
        }
        return [kind, place.detail].filter { !$0.isEmpty }.joined(separator: " · ")
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
