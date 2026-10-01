import SwiftUI

/// The Hearth palette shared with Enve Book Player: warm Ink and Paper surfaces around an ember accent.
extension Color {
    static let trackerBackground = Color(light: 0xF7F2E9, dark: 0x0C0A09, pureBlack: 0x000000)
    static let trackerElevated = Color(light: 0xFFFFFF, dark: 0x191512, pureBlack: 0x0C0C0D)
    static let trackerText = Color(light: 0x231F1B, dark: 0xF0E9DC)
    static let trackerHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.1) : .black.withAlphaComponent(0.08)
    })
    /// Ember, deepened on Paper so it keeps contrast against the light background.
    static let trackerAccent = Color(light: 0x89520F, dark: 0xF5921A)
    static let trackerOnAccent = Color(light: 0xFFF7EA, dark: 0x1A120A)
    static let trackerPrimaryContainer = Color(light: 0xFDEEDA, dark: 0x412C13)
    static let trackerOnPrimaryContainer = Color(light: 0x89520F, dark: 0xF5921A)
    static let trackerOK = Color(light: 0x4F7942, dark: 0x8FBF7F)
    static let trackerOKContainer = Color(light: 0xE6ECE5, dark: 0x2E3426)
    static let trackerSoon = Color(light: 0x93601B, dark: 0xE0A458)
    static let trackerSoonContainer = Color(light: 0xEEE6DB, dark: 0x3D2F1F)
    static let trackerPast = Color(light: 0xA8453A, dark: 0xD06A5C)
    static let trackerPastContainer = Color(light: 0xF3E5E3, dark: 0x3E2621)

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

    /// Serif navigation titles in the Hearth style; SwiftUI has no modifier for navigation bar fonts.
    @MainActor
    static func configureNavigationBars() {
        let text = UIColor(Color.trackerText)
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .bold), .foregroundColor: text]
        appearance.titleTextAttributes = [.font: serif(.headline, weight: .semibold), .foregroundColor: text]
    }

    @MainActor
    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 0) } ?? base
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
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
    /// The warm canvas and card surfaces shared by every list and form.
    func trackerListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.trackerBackground)
    }
}

/// A list whose rows sit on Hearth's elevated surface rather than the system's neutral grey.
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

/// Small uppercase section label, Hearth's overline.
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
