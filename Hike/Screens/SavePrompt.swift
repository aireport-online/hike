import SwiftUI

/// Asks for the route's name on a signpost plate laid over the map.
struct SavePrompt: View {
    @Binding var name: String
    var onCancel: () -> Void
    var onSave: () -> Void

    @FocusState private var nameIsFocused: Bool

    private let point: CGFloat = 20

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                Text("ROUTE OPSLAAN")
                    .font(.sign(28, relativeTo: .title2))
                    .accessibilityAddTraits(.isHeader)

                TextField("Naam van je wandeling", text: $name)
                    .font(.text(18))
                    .focused($nameIsFocused)
                    .submitLabel(.done)
                    .onSubmit(onSave)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Brand.corner))
                    .overlay {
                        RoundedRectangle(cornerRadius: Brand.corner)
                            .strokeBorder(Brand.ink, lineWidth: Brand.outline)
                    }
                    .accessibilityIdentifier("saveNameField")

                HStack(spacing: 10) {
                    Button("Annuleer", action: onCancel)
                        .buttonStyle(OutlineButtonStyle(onYellow: true))
                    Button("Opslaan", action: onSave)
                        .buttonStyle(InkButtonStyle())
                        .accessibilityIdentifier("confirmSaveButton")
                }
            }
            .foregroundStyle(Brand.ink)
            .padding(.leading, 18)
            .padding(.trailing, 14 + point)
            .padding(.vertical, 18)
            .frame(maxWidth: 440, alignment: .leading)
            .background {
                SignpostShape(point: point).fill(Brand.yellow)
            }
            .overlay {
                SignpostShape(point: point).stroke(Brand.ink, lineWidth: Brand.outline)
            }
            .overlay(alignment: .trailing) {
                BlazeMark()
                    .frame(width: 10, height: 26)
                    .padding(.trailing, 6)
            }
            .environment(\.colorScheme, .light)
            .tint(Brand.ink)
            .padding(.horizontal, 18)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { nameIsFocused = true }
    }
}
