import SwiftUI

enum ColorThemeID: String, CaseIterable, Identifiable {
    case clinical  = "Clinical"
    case neon      = "Neon"
    case thermal   = "Thermal"
    case monochrome = "Mono"
    case ember     = "Ember"
    case arctic    = "Arctic"

    var id: String { rawValue }
}

struct ColorTheme {
    let accent: Color
    let bandColors: [Color]

    static func theme(for id: ColorThemeID) -> ColorTheme {
        switch id {
        case .clinical:
            return ColorTheme(
                accent: Color.p3(0.95, 0.08, 0.08),
                bandColors: [
                    Color.p3(0.20, 0.30, 0.95),
                    Color.p3(0.25, 0.50, 0.95),
                    Color.p3(0.30, 0.65, 0.90),
                    Color.p3(0.45, 0.78, 0.85),
                    Color.p3(0.70, 0.82, 0.82),
                    Color.p3(0.85, 0.80, 0.72),
                    Color.p3(0.90, 0.65, 0.50),
                    Color.p3(0.92, 0.45, 0.35),
                    Color.p3(0.95, 0.22, 0.18),
                    Color.p3(0.90, 0.10, 0.25),
                ]
            )
        case .neon:
            return ColorTheme(
                accent: Color.p3(0.00, 0.92, 1.00),
                bandColors: [
                    Color.p3(0.30, 0.20, 1.00),
                    Color.p3(0.10, 0.45, 1.00),
                    Color.p3(0.00, 0.80, 0.95),
                    Color.p3(0.00, 0.95, 0.65),
                    Color.p3(0.35, 1.00, 0.20),
                    Color.p3(0.80, 1.00, 0.00),
                    Color.p3(1.00, 0.80, 0.00),
                    Color.p3(1.00, 0.50, 0.00),
                    Color.p3(1.00, 0.18, 0.10),
                    Color.p3(1.00, 0.10, 0.60),
                ]
            )
        case .thermal:
            return ColorTheme(
                accent: Color.p3(1.00, 0.55, 0.00),
                bandColors: [
                    Color.p3(0.05, 0.10, 0.50),
                    Color.p3(0.10, 0.15, 0.75),
                    Color.p3(0.15, 0.35, 0.90),
                    Color.p3(0.10, 0.70, 0.60),
                    Color.p3(0.20, 0.90, 0.30),
                    Color.p3(0.65, 0.95, 0.10),
                    Color.p3(1.00, 0.90, 0.00),
                    Color.p3(1.00, 0.60, 0.00),
                    Color.p3(1.00, 0.25, 0.00),
                    Color.p3(0.90, 0.05, 0.05),
                ]
            )
        case .monochrome:
            return ColorTheme(
                accent: Color.white,
                bandColors: [
                    Color(white: 0.35),
                    Color(white: 0.42),
                    Color(white: 0.50),
                    Color(white: 0.58),
                    Color(white: 0.65),
                    Color(white: 0.72),
                    Color(white: 0.78),
                    Color(white: 0.85),
                    Color(white: 0.90),
                    Color(white: 0.95),
                ]
            )
        case .ember:
            return ColorTheme(
                accent: Color.p3(1.00, 0.35, 0.10),
                bandColors: [
                    Color.p3(0.30, 0.05, 0.10),
                    Color.p3(0.50, 0.08, 0.12),
                    Color.p3(0.70, 0.12, 0.10),
                    Color.p3(0.85, 0.20, 0.08),
                    Color.p3(0.95, 0.35, 0.08),
                    Color.p3(1.00, 0.50, 0.10),
                    Color.p3(1.00, 0.65, 0.15),
                    Color.p3(1.00, 0.78, 0.25),
                    Color.p3(0.95, 0.40, 0.55),
                    Color.p3(0.85, 0.20, 0.60),
                ]
            )
        case .arctic:
            return ColorTheme(
                accent: Color.p3(0.30, 0.70, 1.00),
                bandColors: [
                    Color.p3(0.10, 0.20, 0.55),
                    Color.p3(0.12, 0.35, 0.75),
                    Color.p3(0.15, 0.50, 0.90),
                    Color.p3(0.20, 0.65, 0.95),
                    Color.p3(0.30, 0.80, 1.00),
                    Color.p3(0.50, 0.88, 1.00),
                    Color.p3(0.70, 0.92, 1.00),
                    Color.p3(0.85, 0.95, 1.00),
                    Color.p3(0.92, 0.97, 1.00),
                    Color.p3(0.98, 0.99, 1.00),
                ]
            )
        }
    }
}

enum CurveColorMode: String, CaseIterable, Identifiable {
    case matchTheme = "Match Theme"
    case white      = "White"
    case neon       = "Neon Rainbow"
    case thermal    = "Thermal"

    var id: String { rawValue }

    var colors: [Color]? {
        switch self {
        case .matchTheme: return nil
        case .white:      return (0..<10).map { _ in Color.white }
        case .neon:
            return [
                Color.p3(0.30, 0.20, 1.00), Color.p3(0.10, 0.45, 1.00),
                Color.p3(0.00, 0.80, 0.95), Color.p3(0.00, 0.95, 0.65),
                Color.p3(0.35, 1.00, 0.20), Color.p3(0.80, 1.00, 0.00),
                Color.p3(1.00, 0.80, 0.00), Color.p3(1.00, 0.50, 0.00),
                Color.p3(1.00, 0.18, 0.10), Color.p3(1.00, 0.10, 0.60),
            ]
        case .thermal:
            return [
                Color.p3(0.05, 0.10, 0.50), Color.p3(0.10, 0.15, 0.75),
                Color.p3(0.15, 0.35, 0.90), Color.p3(0.10, 0.70, 0.60),
                Color.p3(0.20, 0.90, 0.30), Color.p3(0.65, 0.95, 0.10),
                Color.p3(1.00, 0.90, 0.00), Color.p3(1.00, 0.60, 0.00),
                Color.p3(1.00, 0.25, 0.00), Color.p3(0.90, 0.05, 0.05),
            ]
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentID: ColorThemeID {
        didSet {
            UserDefaults.standard.set(currentID.rawValue, forKey: "audio.ether.colorTheme")
            current = ColorTheme.theme(for: currentID)
        }
    }
    @Published private(set) var current: ColorTheme

    @Published var curveColorMode: CurveColorMode {
        didSet {
            UserDefaults.standard.set(curveColorMode.rawValue, forKey: "audio.ether.curveColorMode")
        }
    }

    var curveGradient: [Color] {
        curveColorMode.colors ?? current.bandColors
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "audio.ether.colorTheme") ?? "Clinical"
        let id = ColorThemeID(rawValue: saved) ?? .clinical
        self.currentID = id
        self.current = ColorTheme.theme(for: id)

        let savedCurve = UserDefaults.standard.string(forKey: "audio.ether.curveColorMode") ?? "Match Theme"
        self.curveColorMode = CurveColorMode(rawValue: savedCurve) ?? .matchTheme
    }
}
