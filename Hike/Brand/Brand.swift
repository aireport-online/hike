import CoreText
import SwiftUI
import UIKit

/// The "Wegwijzer" identity: the yellow hiking signpost and the white-red-white blaze painted
/// along Europe's trails. Signal yellow plates, charcoal ink, one accent of blaze red, and
/// condensed signage lettering.
enum Brand {
    // MARK: Colours

    /// Signpost yellow. Always carries ink-coloured content, in light and dark mode alike.
    static let yellow = Color(uiColor: UI.yellow)
    /// Charcoal: lettering on yellow, the route outline, primary buttons.
    static let ink = Color(uiColor: UI.ink)
    /// The red of a trail blaze. An accent only: rules, warnings, the selected mark.
    static let blaze = Color(uiColor: UI.blaze)
    /// Background of sheets and white controls.
    static let paper = Color(uiColor: UI.paper)
    /// Page background behind plates and cards.
    static let ground = Color(uiColor: UI.ground)
    /// Lettering and outlines on paper: ink by day, near-white by night.
    static let line = Color(uiColor: UI.line)

    enum UI {
        static let yellow = UIColor(red: 1.0, green: 0.831, blue: 0.0, alpha: 1)
        static let ink = UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        static let blaze = UIColor(red: 0.890, green: 0.149, blue: 0.180, alpha: 1)
        static let paper = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : .white
        }
        static let ground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.07, alpha: 1)
                : UIColor(red: 0.969, green: 0.961, blue: 0.937, alpha: 1)
        }
        static let line = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.95, alpha: 1) : ink
        }
    }

    // MARK: Measures

    /// Width of outlines around white controls and plates.
    static let outline: CGFloat = 1.5
    /// Corners are nearly square, like cut sheet metal.
    static let corner: CGFloat = 4

    // MARK: Fonts

    enum FontName {
        static let sign = "BarlowCondensed-Bold"
        static let signLight = "BarlowCondensed-SemiBold"
        static let text = "Barlow-Medium"
        static let textStrong = "Barlow-SemiBold"

        static let all = [sign, signLight, text, textStrong]
    }

    /// Makes the bundled fonts available. Call once, before the first view is built.
    static func registerFonts() {
        for name in FontName.all {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing font file \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Signage lettering for headings and figures. Meant to be set in capitals.
    static func sign(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font {
        .custom(Brand.FontName.sign, size: size, relativeTo: style)
    }

    /// Lighter signage lettering for units and small captions.
    static func signLabel(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        .custom(Brand.FontName.signLight, size: size, relativeTo: style)
    }

    /// Running text.
    static func text(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Brand.FontName.text, size: size, relativeTo: style)
    }

    static func textStrong(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Brand.FontName.textStrong, size: size, relativeTo: style)
    }
}
