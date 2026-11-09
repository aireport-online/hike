import HikeCore
import SwiftUI

/// The card at the bottom of the map: what the planned route adds up to, and what to do with it.
struct RoutePanel: View {
    @Environment(PlannerModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let pace: Pace
    var onShowRoutes: () -> Void

    @State private var showsSavePrompt = false
    @State private var saveName = ""
    @State private var showsDiscardConfirmation = false
    @State private var shareItem: ShareItem?

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            if model.waypoints.isEmpty {
                emptyState
            } else {
                header
                statistics
                if verticalSizeClass != .compact, model.profile.count >= 2 {
                    ElevationChart(samples: model.profile, scrubDistance: $model.scrubDistance)
                        .frame(height: 96)
                }
                if let error = model.routingError {
                    routingFailure(error)
                }
                if let index = model.selectedWaypointIndex {
                    selectedWaypoint(index: index)
                }
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: 560, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: -1)
                .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity)
        .alert("Route opslaan", isPresented: $showsSavePrompt) {
            TextField("Naam", text: $saveName)
            Button("Opslaan") { model.save(name: saveName) }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Geef je wandeling een naam.")
        }
        .confirmationDialog(
            "Deze route is niet opgeslagen",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Gooi weg en begin opnieuw", role: .destructive) { model.startNewRoute() }
            Button("Annuleer", role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ActivityView(url: item.url)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tik op de kaart om te beginnen")
                    .font(.headline)
                Text("Elk volgend punt wordt over wandelpaden verbonden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.canUndo {
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Herstel")
            } else if !model.savedRoutes.isEmpty {
                Button("Mijn routes", action: onShowRoutes)
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Route

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.currentRouteName ?? "Nieuwe route")
                .font(.headline)
                .lineLimit(1)
            if model.currentRouteName != nil, model.hasUnsavedChanges {
                Text("gewijzigd")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.isRouting {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    model.fitRoute()
                } label: {
                    Label("Toon hele route", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button {
                    share()
                } label: {
                    Label("Deel als GPX", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.isComplete)

                Section {
                    Button {
                        model.closeLoop()
                    } label: {
                        Label("Terug naar start", systemImage: "arrow.triangle.capsulepath")
                    }
                    .disabled(model.waypoints.count < 2 || model.isLoop)
                    Button {
                        model.reverseRoute()
                    } label: {
                        Label("Keer route om", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(model.waypoints.count < 2)
                }

                Section {
                    Button(action: onShowRoutes) {
                        Label("Mijn routes", systemImage: "bookmark")
                    }
                    Button(role: .destructive) {
                        startOver()
                    } label: {
                        Label("Nieuwe route", systemImage: "plus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 36, height: 30)
            }
            .accessibilityLabel("Meer")
        }
    }

    @ViewBuilder
    private var statistics: some View {
        if model.waypoints.count < 2 {
            Text("Tik op de kaart voor het volgende punt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 0) {
                statistic(HikeFormat.distance(model.stats.distance), label: "Afstand")
                statistic("↑ " + HikeFormat.elevation(model.stats.ascent), label: "Stijgen")
                statistic("↓ " + HikeFormat.elevation(model.stats.descent), label: "Dalen")
                statistic(HikeFormat.duration(model.stats.duration(pace: pace)), label: "Wandeltijd")
            }
            .opacity(model.isComplete ? 1 : 0.5)
        }
    }

    private func statistic(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func routingFailure(_ error: RoutingError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("Opnieuw") { model.retryFailedLegs() }
                Button("Rechte lijn") { model.useStraightLinesForFailedLegs() }
                    .accessibilityIdentifier("straightLineFallbackButton")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func selectedWaypoint(index: Int) -> some View {
        HStack {
            Text(waypointTitle(index: index))
                .font(.subheadline)
            Spacer(minLength: 0)
            Button(role: .destructive) {
                if let id = model.selectedWaypointID {
                    model.removeWaypoint(id: id)
                }
            } label: {
                Label("Verwijder punt", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func waypointTitle(index: Int) -> String {
        if index == 0 {
            return "Startpunt · houd vast om te verslepen"
        }
        if index == model.waypoints.count - 1 {
            return "Eindpunt · houd vast om te verslepen"
        }
        return "Punt \(index) · houd vast om te verslepen"
    }

    private var actions: some View {
        @Bindable var model = model

        return HStack(spacing: 10) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(height: 22)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canUndo)
            .accessibilityLabel("Herstel")

            Picker("Volgende stuk", selection: $model.legMode) {
                Text("Over paden").tag(LegMode.trail)
                Text("Rechte lijn").tag(LegMode.straight)
            }
            .pickerStyle(.segmented)

            Button {
                promptForSave()
            } label: {
                Text("Bewaar")
                    .frame(height: 22)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.isComplete || (model.currentRouteName != nil && !model.hasUnsavedChanges))
            .accessibilityIdentifier("saveButton")
        }
    }

    // MARK: - Actions

    private func promptForSave() {
        Task {
            saveName = await model.suggestedName()
            showsSavePrompt = true
        }
    }

    private func share() {
        if let url = model.exportCurrentRoute() {
            shareItem = ShareItem(url: url)
        }
    }

    private func startOver() {
        if model.hasUnsavedChanges, model.isComplete {
            showsDiscardConfirmation = true
        } else {
            model.startNewRoute()
        }
    }
}
