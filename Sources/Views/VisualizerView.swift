import SwiftUI
import AppKit

struct VisualizerView: View {
    @EnvironmentObject var engine: EngineManager
    @StateObject private var nowPlaying = NowPlayingManager()

    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.05, of: .white) ?? .white)
    }
    private var tint2: Color {
        guard let rgb = nowPlaying.dominantColor.usingColorSpace(.deviceRGB) else { return tint }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.15 && b > 0.12 else { return tint }
        // Adjacent hue (~36°) — same palette neighborhood, not complementary
        let h2 = (h + 0.10).truncatingRemainder(dividingBy: 1.0)
        let c2 = NSColor(hue: h2, saturation: min(1, s * 1.05), brightness: min(1, b), alpha: 1.0)
        return Color(nsColor: c2.blended(withFraction: 0.03, of: .white) ?? .white)
    }

    var body: some View {
        MiniVisualizerView(analyzer: engine.postSpectrum, tint: tint, tint2: tint2, isFullScreen: true)
            .ignoresSafeArea()
            .onAppear { engine.postSpectrum.isActive = true }
    }
}
