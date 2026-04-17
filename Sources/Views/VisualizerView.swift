import SwiftUI
import AppKit

struct VisualizerView: View {
    @EnvironmentObject var engine: EngineManager
    @StateObject private var nowPlaying = NowPlayingManager()

    private var tint: Color {
        Color(nsColor: nowPlaying.dominantColor.blended(withFraction: 0.3, of: .white) ?? .white)
    }
    private var tint2: Color {
        guard let rgb = nowPlaying.dominantColor.usingColorSpace(.deviceRGB) else { return tint }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.22 && b > 0.15 else { return tint }
        let h2 = (h + 0.42).truncatingRemainder(dividingBy: 1.0)
        let c2 = NSColor(hue: h2, saturation: min(1, s * 1.4), brightness: min(1, b * 1.1), alpha: 1.0)
        return Color(nsColor: c2.blended(withFraction: 0.25, of: .white) ?? .white)
    }

    var body: some View {
        MiniVisualizerView(analyzer: engine.postSpectrum, tint: tint, tint2: tint2, isFullScreen: true)
            .ignoresSafeArea()
            .onAppear { engine.postSpectrum.isActive = true }
    }
}
