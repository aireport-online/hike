import SwiftUI

/// The main action: charcoal with yellow signage lettering.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sign(20, relativeTo: .headline))
            .textCase(.uppercase)
            .foregroundStyle(Brand.yellow.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(
                Brand.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                in: RoundedRectangle(cornerRadius: Brand.corner)
            )
            .contentShape(Rectangle())
    }
}

/// A secondary action: an outlined plate. `onYellow` keeps the lettering ink-coloured when the
/// button sits on a yellow panel, where it must not turn light in dark mode.
struct OutlineButtonStyle: ButtonStyle {
    var onYellow = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let colour = onYellow ? Brand.ink : Brand.line
        configuration.label
            .font(.sign(compact ? 15 : 18, relativeTo: .subheadline))
            .textCase(.uppercase)
            .foregroundStyle(colour.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, compact ? 10 : 14)
            .frame(minWidth: compact ? 36 : 44, minHeight: compact ? 32 : 44)
            .background(
                colour.opacity(configuration.isPressed ? 0.15 : 0),
                in: RoundedRectangle(cornerRadius: Brand.corner)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Brand.corner)
                    .strokeBorder(colour.opacity(isEnabled ? 1 : 0.35), lineWidth: Brand.outline)
            }
            .contentShape(Rectangle())
    }
}

/// A row of options of which one is switched on, lettered like a signpost.
struct SignSwitch<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    var onYellow = false

    var body: some View {
        let colour = onYellow ? Brand.ink : Brand.line
        let contrast = onYellow ? Brand.yellow : Brand.paper

        HStack(spacing: 0) {
            ForEach(options) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title.uppercased())
                        .font(.sign(16, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isOn ? contrast : colour)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? colour : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Brand.corner))
        .overlay {
            RoundedRectangle(cornerRadius: Brand.corner)
                .strokeBorder(colour, lineWidth: Brand.outline)
        }
    }
}

extension View {
    /// A sheet's title in signage capitals, in place of the system title.
    func signTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(.sign(22, relativeTo: .headline))
                        .foregroundStyle(Brand.line)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
