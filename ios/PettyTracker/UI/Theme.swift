import SwiftUI

/// The Petty palette: cool grays around a blue-green accent, plain and functional.
extension Color {
    static let trackerBackground = Color(light: 0xF3F5F6, dark: 0x0E1113, pureBlack: 0x000000)
    static let trackerElevated = Color(light: 0xFFFFFF, dark: 0x181D20, pureBlack: 0x0B0D0E)
    static let trackerText = Color(light: 0x1B2328, dark: 0xE6EBEE)
    static let trackerHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.09) : .black.withAlphaComponent(0.08)
    })
    static let trackerAccent = Color(light: 0x0F7A8A, dark: 0x4FC1C9)
    static let trackerOnAccent = Color(light: 0xFFFFFF, dark: 0x0B1F22)
    static let trackerPrimaryContainer = Color(light: 0xE2F1F3, dark: 0x173238)
    static let trackerOnPrimaryContainer = Color(light: 0x0F6573, dark: 0x7FD3D9)
    static let trackerOK = Color(light: 0x2F7D55, dark: 0x6CC79A)
    static let trackerOKContainer = Color(light: 0xE3F1E9, dark: 0x1C3229)
    static let trackerSoon = Color(light: 0x9A6400, dark: 0xE2B04A)
    static let trackerSoonContainer = Color(light: 0xF6EEDC, dark: 0x362C17)
    static let trackerPast = Color(light: 0xB23A31, dark: 0xEE8277)
    static let trackerPastContainer = Color(light: 0xF7E4E2, dark: 0x3A201E)

    init(light: UInt32, dark: UInt32, pureBlack: UInt32? = nil) {
        self.init(uiColor: UIColor { traits in
            let hex = if traits.userInterfaceStyle == .dark {
                UserDefaults.standard.bool(forKey: Appearance.pureBlackKey) ? pureBlack ?? dark : dark
            } else {
                light
            }
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

enum Appearance {
    /// Device-only preference for true-black dark surfaces on OLED screens; not part of backups.
    static let pureBlackKey = "appearance.pureBlack"
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
    /// The canvas and card surfaces shared by every list and form.
    func trackerListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.trackerBackground)
    }
}

/// A list whose rows sit on the Petty elevated surface rather than the system default.
struct TrackerList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List {
            content.listRowBackground(Color.trackerElevated)
        }
        .trackerListStyle()
    }
}

/// The form counterpart of `TrackerList`, for editors and settings.
struct TrackerForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content.listRowBackground(Color.trackerElevated)
        }
        .trackerListStyle()
    }
}

/// Small uppercase section label.
struct Overline: View {
    let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim string: String) { text = Text(verbatim: string) }

    var body: some View {
        text
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}

extension Section where Parent == Overline, Content: View, Footer == EmptyView {
    @MainActor
    init(overline title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Overline(title) })
    }
}
