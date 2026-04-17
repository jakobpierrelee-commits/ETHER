import SwiftUI

enum ColorThemeID: String, CaseIterable, Identifiable {
    case clinical   = "Clinical"
    case violet     = "Violet"
    case thermal    = "Thermal"
    case mono       = "Mono"
    case ember      = "Ember"
    case tidal      = "Tidal"

    var id: String { rawValue }
}

struct ColorTheme {
    let accent: Color
    let bandColors: [Color]

    static func theme(for id: ColorThemeID) -> ColorTheme {
        switch id {
        case .clinical:
            // Refined instrument look — deep blue through neutral to warm red
            return ColorTheme(
                accent: Color.p3(0.92, 0.12, 0.12),
                bandColors: [
                    Color.p3(0.15, 0.25, 0.90),
                    Color.p3(0.18, 0.45, 0.92),
                    Color.p3(0.22, 0.62, 0.88),
                    Color.p3(0.35, 0.75, 0.78),
                    Color.p3(0.55, 0.78, 0.68),
                    Color.p3(0.75, 0.72, 0.52),
                    Color.p3(0.88, 0.58, 0.35),
                    Color.p3(0.92, 0.40, 0.22),
                    Color.p3(0.92, 0.20, 0.15),
                    Color.p3(0.85, 0.10, 0.18),
                ]
            )
        case .violet:
            // Stage lights — deep indigo through electric purple to hot magenta
            return ColorTheme(
                accent: Color.p3(0.40, 0.42, 1.00),
                bandColors: [
                    Color.p3(0.18, 0.08, 0.55),
                    Color.p3(0.30, 0.10, 0.75),
                    Color.p3(0.45, 0.15, 0.90),
                    Color.p3(0.60, 0.20, 0.95),
                    Color.p3(0.75, 0.28, 0.92),
                    Color.p3(0.88, 0.22, 0.78),
                    Color.p3(0.95, 0.18, 0.58),
                    Color.p3(1.00, 0.25, 0.42),
                    Color.p3(1.00, 0.35, 0.50),
                    Color.p3(0.95, 0.45, 0.65),
                ]
            )
        case .thermal:
            // True FLIR — dark indigo to white-hot, no green gap
            return ColorTheme(
                accent: Color.p3(1.00, 0.55, 0.00),
                bandColors: [
                    Color.p3(0.04, 0.02, 0.22),
                    Color.p3(0.12, 0.05, 0.50),
                    Color.p3(0.30, 0.05, 0.65),
                    Color.p3(0.55, 0.05, 0.60),
                    Color.p3(0.80, 0.10, 0.35),
                    Color.p3(0.95, 0.25, 0.10),
                    Color.p3(1.00, 0.50, 0.00),
                    Color.p3(1.00, 0.72, 0.00),
                    Color.p3(1.00, 0.88, 0.40),
                    Color.p3(1.00, 0.97, 0.80),
                ]
            )
        case .mono:
            // Warm filament — off-white with subtle warmth, not dead gray
            return ColorTheme(
                accent: Color.p3(0.95, 0.90, 0.82),
                bandColors: [
                    Color.p3(0.32, 0.30, 0.28),
                    Color.p3(0.40, 0.38, 0.35),
                    Color.p3(0.50, 0.48, 0.44),
                    Color.p3(0.58, 0.56, 0.52),
                    Color.p3(0.66, 0.64, 0.60),
                    Color.p3(0.74, 0.72, 0.68),
                    Color.p3(0.82, 0.80, 0.76),
                    Color.p3(0.88, 0.86, 0.82),
                    Color.p3(0.93, 0.91, 0.86),
                    Color.p3(0.97, 0.95, 0.90),
                ]
            )
        case .ember:
            // True fire — deep burgundy through crimson, orange, to molten gold
            return ColorTheme(
                accent: Color.p3(1.00, 0.42, 0.08),
                bandColors: [
                    Color.p3(0.25, 0.02, 0.05),
                    Color.p3(0.42, 0.04, 0.06),
                    Color.p3(0.62, 0.08, 0.05),
                    Color.p3(0.80, 0.15, 0.04),
                    Color.p3(0.92, 0.28, 0.04),
                    Color.p3(1.00, 0.42, 0.06),
                    Color.p3(1.00, 0.58, 0.08),
                    Color.p3(1.00, 0.72, 0.12),
                    Color.p3(1.00, 0.82, 0.25),
                    Color.p3(1.00, 0.90, 0.45),
                ]
            )
        case .tidal:
            // Ocean depth — dark navy through steel blue to pale gold
            return ColorTheme(
                accent: Color.p3(0.30, 0.62, 0.92),
                bandColors: [
                    Color.p3(0.04, 0.08, 0.28),
                    Color.p3(0.06, 0.15, 0.45),
                    Color.p3(0.08, 0.28, 0.62),
                    Color.p3(0.12, 0.42, 0.78),
                    Color.p3(0.20, 0.55, 0.88),
                    Color.p3(0.35, 0.68, 0.90),
                    Color.p3(0.52, 0.75, 0.88),
                    Color.p3(0.70, 0.78, 0.80),
                    Color.p3(0.85, 0.80, 0.68),
                    Color.p3(0.92, 0.82, 0.58),
                ]
            )
        }
    }
}

enum CurveColorMode: String, CaseIterable, Identifiable {
    case matchTheme = "Match Theme"
    case white      = "White"
    case violet     = "Violet"
    case thermal    = "Thermal"

    var id: String { rawValue }

    var colors: [Color]? {
        switch self {
        case .matchTheme: return nil
        case .white:      return (0..<10).map { _ in Color.white }
        case .violet:     return ColorTheme.theme(for: .violet).bandColors
        case .thermal:    return ColorTheme.theme(for: .thermal).bandColors
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
