import SwiftUI

extension Color {
    static let keepOnAccent = Color(light: 0xFFFFFF, dark: 0x00382D)
    static let keepBackground = Color(light: 0xF6F8F6, dark: 0x101413)
    static let keepPrimaryContainer = Color(light: 0xCDE9DF, dark: 0x145143)
    static let keepOnPrimaryContainer = Color(light: 0x0A2B23, dark: 0xAFEFDD)
    static let keepSoon = Color(light: 0x8A5100, dark: 0xFFB961)
    static let keepSoonContainer = Color(light: 0xFFDDB8, dark: 0x693C00)
    static let keepPast = Color(light: 0xB0302A, dark: 0xFFB4AB)
    static let keepPastContainer = Color(light: 0xFADAD6, dark: 0x8C1D18)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

extension RecordKind {
    var label: String {
        switch self {
        case .warranty: String(localized: "Warranty")
        case .subscription: String(localized: "Subscription")
        case .document: String(localized: "Document")
        }
    }

    var symbol: String {
        switch self {
        case .warranty: "shippingbox"
        case .subscription: "arrow.triangle.2.circlepath"
        case .document: "doc.text"
        }
    }
}

extension View {
    /// The calm green-grey canvas shared by every list screen.
    func keepListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.keepBackground)
    }
}
