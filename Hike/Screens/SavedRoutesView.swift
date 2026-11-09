import HikeCore
import SwiftUI
import UniformTypeIdentifiers

/// The saved routes as plates on a signpost.
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
                        RoutePlate(route: route, pace: pace, isCurrent: route.id == model.currentRouteID)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 7, leading: 18, bottom: 7, trailing: 14))
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
                        .tint(Brand.ink)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                // The pole the plates hang on.
                ZStack {
                    Brand.ground
                    if !model.savedRoutes.isEmpty {
                        Rectangle()
                            .fill(Brand.line)
                            .frame(width: 10)
                    }
                }
                .ignoresSafeArea()
            }
            .overlay {
                if model.savedRoutes.isEmpty {
                    emptyState
                }
            }
            .signTitle("Mijn routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit") { dismiss() }
                        .font(.textStrong(17))
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
        .tint(Brand.line)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "signpost.right")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Brand.line)
            Text("NOG GEEN ROUTES")
                .font(.sign(26, relativeTo: .title2))
                .foregroundStyle(Brand.line)
            Text("Plan een wandeling op de kaart en bewaar hem, of importeer een GPX-bestand.")
                .font(.text(16))
                .foregroundStyle(Brand.line.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(32)
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

/// One saved route as a signpost plate: where to, how far, how long.
private struct RoutePlate: View {
    let route: HikeRoute
    let pace: Pace
    let isCurrent: Bool

    private let point: CGFloat = 18

    var body: some View {
        let stats = route.stats

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(route.name.uppercased())
                    .font(.sign(22, relativeTo: .title3))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 12) {
                    figure("arrow.left.and.right", HikeFormat.distance(stats.distance))
                    if stats.maxElevation != nil {
                        figure("arrow.up", HikeFormat.elevation(stats.ascent))
                    }
                    figure("clock", HikeFormat.duration(stats.duration(pace: pace)))
                }
                Text(route.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.text(12, relativeTo: .caption))
                    .foregroundStyle(Brand.ink.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Brand.ink)
        .padding(.leading, 22)
        .padding(.trailing, point + 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SignpostShape(point: point).fill(Brand.yellow)
        }
        .overlay(alignment: .leading) {
            // The blaze is painted on the blunt end of the plate.
            BlazeMark()
                .frame(width: 9)
                .padding(.vertical, 12)
                .padding(.leading, 6)
        }
        .overlay {
            SignpostShape(point: point)
                .stroke(Brand.ink, lineWidth: isCurrent ? 3 : Brand.outline)
        }
        .contentShape(SignpostShape(point: point))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func figure(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(value)
                .font(.signLabel(17, relativeTo: .subheadline))
                .monospacedDigit()
        }
    }
}
