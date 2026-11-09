import HikeCore
import SwiftUI
import UniformTypeIdentifiers

struct SavedRoutesView: View {
    @Environment(PlannerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let pace: Pace

    @State private var isImporting = false
    @State private var routeAwaitingConfirmation: HikeRoute?
    @State private var shareItem: ShareItem?

    private static let gpxTypes: [UTType] = [UTType(filenameExtension: "gpx") ?? .xml, .xml]

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.savedRoutes) { route in
                    Button {
                        requestOpen(route)
                    } label: {
                        RouteRow(route: route, pace: pace, isCurrent: route.id == model.currentRouteID)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            model.delete(route)
                        } label: {
                            Label("Verwijder", systemImage: "trash")
                        }
                        Button {
                            if let url = model.export(route) {
                                shareItem = ShareItem(url: url)
                            }
                        } label: {
                            Label("Deel", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
            .overlay {
                if model.savedRoutes.isEmpty {
                    ContentUnavailableView(
                        "Nog geen routes",
                        systemImage: "bookmark",
                        description: Text("Plan een wandeling op de kaart en bewaar hem, of importeer een GPX-bestand.")
                    )
                }
            }
            .navigationTitle("Mijn routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Importeer GPX", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.gpxTypes) { result in
                if case .success(let url) = result, model.importGPX(from: url) {
                    dismiss()
                }
            }
            .confirmationDialog(
                "Je huidige route is niet opgeslagen",
                isPresented: Binding(
                    get: { routeAwaitingConfirmation != nil },
                    set: { if !$0 { routeAwaitingConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Toch openen", role: .destructive) {
                    if let route = routeAwaitingConfirmation {
                        open(route)
                    }
                }
                Button("Annuleer", role: .cancel) {}
            }
            .sheet(item: $shareItem) { item in
                ActivityView(url: item.url)
            }
        }
    }

    private func requestOpen(_ route: HikeRoute) {
        if model.hasUnsavedChanges, model.isComplete, route.id != model.currentRouteID {
            routeAwaitingConfirmation = route
        } else {
            open(route)
        }
    }

    private func open(_ route: HikeRoute) {
        model.open(route)
        dismiss()
    }
}

private struct RouteRow: View {
    let route: HikeRoute
    let pace: Pace
    let isCurrent: Bool

    var body: some View {
        let stats = route.stats
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // Concrete label colours: inside a button, .primary and friends follow the tint.
                Text(route.name)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                    .lineLimit(2)
                Text(summary(stats))
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .monospacedDigit()
                Text(route.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Geopend")
            }
        }
        .padding(.vertical, 2)
    }

    private func summary(_ stats: RouteStats) -> String {
        var parts = [HikeFormat.distance(stats.distance)]
        if stats.maxElevation != nil {
            parts.append("↑ " + HikeFormat.elevation(stats.ascent))
            parts.append("↓ " + HikeFormat.elevation(stats.descent))
        }
        parts.append(HikeFormat.duration(stats.duration(pace: pace)))
        return parts.joined(separator: " · ")
    }
}
