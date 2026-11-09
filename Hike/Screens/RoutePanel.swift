import HikeCore
import SwiftUI

/// The signpost plate at the bottom of the map: what the planned route adds up to, and what to
/// do with it.
struct RoutePanel: View {
    @Environment(PlannerModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let pace: Pace
    var onShowRoutes: () -> Void
    var onSave: () -> Void

    @State private var showsDiscardConfirmation = false
    @State private var shareItem: ShareItem?

    /// Depth of the plate's pointed end; content keeps clear of it.
    private let point: CGFloat = 18

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
                        .frame(height: 92)
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
        .foregroundStyle(Brand.ink)
        .padding(.leading, 16)
        .padding(.trailing, 12 + point)
        .padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .background {
            SignpostShape(point: point)
                .fill(Brand.yellow)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
        .overlay {
            SignpostShape(point: point)
                .stroke(Brand.ink, lineWidth: Brand.outline)
        }
        .overlay(alignment: .trailing) {
            // The blaze sits on the tip of the plate, as it does on a mountain-trail signpost.
            BlazeMark()
                .frame(width: 9, height: 24)
                .padding(.trailing, 6)
        }
        // The plate is yellow by day and by night, so everything on it stays dark-on-light.
        .environment(\.colorScheme, .light)
        .tint(Brand.ink)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
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
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "hand.tap")
                .font(.system(size: 34, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                Text("TIK OP DE KAART")
                    .font(.sign(28, relativeTo: .title2))
                Text("Elk volgend punt wordt over wandelpaden verbonden.")
                    .font(.text(15, relativeTo: .subheadline))
                    .foregroundStyle(Brand.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if model.canUndo {
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(OutlineButtonStyle(onYellow: true))
                .accessibilityLabel("Herstel")
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Route

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text((model.currentRouteName ?? "Nieuwe route").uppercased())
                .font(.sign(26, relativeTo: .title2))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model.currentRouteName != nil, model.hasUnsavedChanges {
                Text("GEWIJZIGD")
                    .font(.signLabel(13))
                    .foregroundStyle(Brand.ink.opacity(0.7))
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
                        Label("Mijn routes", systemImage: "signpost.right")
                    }
                    Button(role: .destructive) {
                        startOver()
                    } label: {
                        Label("Nieuwe route", systemImage: "plus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 36, height: 30)
                    .overlay {
                        RoundedRectangle(cornerRadius: Brand.corner)
                            .strokeBorder(Brand.ink, lineWidth: Brand.outline)
                    }
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Meer")
        }
    }

    @ViewBuilder
    private var statistics: some View {
        if model.waypoints.count < 2 {
            Text("Tik op de kaart voor het volgende punt.")
                .font(.text(15, relativeTo: .subheadline))
                .foregroundStyle(Brand.ink.opacity(0.75))
        } else {
            HStack(alignment: .top, spacing: 0) {
                statistic(HikeFormat.distance(model.stats.distance), symbol: "arrow.left.and.right", label: "Afstand")
                divider
                statistic(HikeFormat.elevation(model.stats.ascent), symbol: "arrow.up", label: "Stijgen")
                divider
                statistic(HikeFormat.elevation(model.stats.descent), symbol: "arrow.down", label: "Dalen")
                divider
                statistic(HikeFormat.duration(model.stats.duration(pace: pace)), symbol: "clock", label: "Wandeltijd")
            }
            .opacity(model.isComplete ? 1 : 0.45)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Brand.ink.opacity(0.3))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 6)
    }

    /// A figure set large with its unit small beside it, under a pictogram, as on a signpost.
    private func statistic(_ value: String, symbol: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(height: 14)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ForEach(Array(HikeFormat.tokens(value).enumerated()), id: \.offset) { _, token in
                    Text(token.text)
                        .font(token.isFigure ? .sign(30, relativeTo: .title) : .signLabel(15, relativeTo: .footnote))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private func routingFailure(_ error: RoutingError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error.localizedDescription)
                    .font(.text(14, relativeTo: .footnote))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.blaze)
            }
            HStack(spacing: 8) {
                Button("Opnieuw") { model.retryFailedLegs() }
                Button("Rechte lijn") { model.useStraightLinesForFailedLegs() }
                    .accessibilityIdentifier("straightLineFallbackButton")
            }
            .buttonStyle(OutlineButtonStyle(onYellow: true, compact: true))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Brand.corner))
        .overlay {
            RoundedRectangle(cornerRadius: Brand.corner)
                .strokeBorder(Brand.ink, lineWidth: Brand.outline)
        }
    }

    private func selectedWaypoint(index: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(waypointTitle(index: index).uppercased())
                    .font(.sign(17, relativeTo: .subheadline))
                Text("Houd vast om te verslepen")
                    .font(.text(13, relativeTo: .caption))
                    .foregroundStyle(Brand.ink.opacity(0.7))
            }
            Spacer(minLength: 0)
            Button {
                if let id = model.selectedWaypointID {
                    model.removeWaypoint(id: id)
                }
            } label: {
                Label("Verwijder", systemImage: "trash")
            }
            .buttonStyle(OutlineButtonStyle(onYellow: true, compact: true))
        }
    }

    private func waypointTitle(index: Int) -> String {
        if index == 0 {
            return "Startpunt"
        }
        if index == model.waypoints.count - 1 {
            return "Eindpunt"
        }
        return "Punt \(index)"
    }

    private var actions: some View {
        @Bindable var model = model

        return HStack(spacing: 8) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .bold))
            }
            .buttonStyle(OutlineButtonStyle(onYellow: true))
            .disabled(!model.canUndo)
            .accessibilityLabel("Herstel")

            SignSwitch(
                options: [
                    SignSwitch<LegMode>.Option(value: .trail, title: "Paden"),
                    SignSwitch<LegMode>.Option(value: .straight, title: "Recht")
                ],
                selection: $model.legMode,
                onYellow: true
            )
            .accessibilityLabel("Volgende stuk")

            Button("Bewaar", action: onSave)
                .buttonStyle(InkButtonStyle())
                .disabled(!model.isComplete || (model.currentRouteName != nil && !model.hasUnsavedChanges))
                .accessibilityIdentifier("saveButton")
        }
    }

    // MARK: - Actions

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
