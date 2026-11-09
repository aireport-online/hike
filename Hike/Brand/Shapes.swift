import SwiftUI

/// A signpost plate: a rectangle whose trailing end is cut to a point.
struct SignpostShape: Shape {
    /// How far the point reaches beyond the body of the plate.
    var point: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let tip = min(point, rect.width / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The white-red-white blaze that marks mountain trails, as painted on rocks and signposts.
struct BlazeMark: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.white
            Brand.blaze
            Color.white
        }
        .overlay {
            Rectangle().strokeBorder(Brand.ink.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// A heading in signage capitals with the red rule under it.
struct SignHeading: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.sign(30, relativeTo: .title))
                .foregroundStyle(Brand.line)
            Rectangle()
                .fill(Brand.blaze)
                .frame(height: 3)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
