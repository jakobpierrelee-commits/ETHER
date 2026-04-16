import SwiftUI
import AppKit

// MARK: - Color Palette

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Display P3 color with sRGB hex fallback values.
    /// On P3-capable displays (2016+ MacBook Pros, modern iMacs, Studio Display, XDR)
    /// these render in wide gamut. On sRGB displays they clamp gracefully.
    static func p3(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.displayP3, red: r, green: g, blue: b)
    }

    // Neutrals stay in sRGB — P3 doesn't expand what greys look like
    static let etherBackground    = Color(hex: 0x080808)
    static let etherSurface       = Color(hex: 0x141414)
    static let etherSurfaceHigh   = Color(hex: 0x1C1C1C)

    // Accent: driven by selected color theme
    static var etherAccent: Color { ThemeManager.shared.current.accent }
    static let etherPositive      = Color.p3(0.22, 1.00, 0.08)   // neon green (status only)
    static let etherNegative      = Color.p3(1.00, 0.42, 0.20)   // saturated orange (status only)
    static let etherWarning       = Color.p3(1.00, 0.84, 0.00)   // amber (status only)
    static let etherClip          = Color.p3(1.00, 0.08, 0.08)   // matches accent

    static let etherTextPrimary   = Color(hex: 0xE0E0E0)
    static let etherTextSecondary = Color(hex: 0x808080)
    static let etherTextTertiary  = Color(hex: 0x484848)

    /// Gain readout tint: white at neutral, red at extremes
    static func gainTint(for gain: Float) -> Color {
        if abs(gain) < 0.5 { return .etherTextPrimary }
        let t = min(1, abs(gain) / 12)
        return Color.white.mix(with: .etherAccent, amount: Double(t))
    }

    /// Linear interpolation between two colors in Display P3 space.
    /// Falls back to sRGB if P3 conversion isn't available.
    func mix(with other: Color, amount: Double) -> Color {
        let cs: NSColorSpace = .displayP3
        let a = NSColor(self).usingColorSpace(cs) ?? NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let b = NSColor(other).usingColorSpace(cs) ?? NSColor(other).usingColorSpace(.sRGB) ?? NSColor.black
        let t = max(0, min(1, amount))
        return Color(
            .displayP3,
            red:   a.redComponent   * (1 - t) + b.redComponent   * t,
            green: a.greenComponent * (1 - t) + b.greenComponent * t,
            blue:  a.blueComponent  * (1 - t) + b.blueComponent  * t
        )
    }
}

// MARK: - Typography Tokens
//
// Single source of truth for all fonts. Change `fontFamily` to swap the
// entire UI typeface (e.g. "JetBrains Mono", "OCR-A", "SF Mono").
// The variant family is used for display/header text when you want contrast.

enum EtherType {
    static let fontFamily         = "Space Mono"
    static let variantFamily      = "Space Mono"

    // Size scale
    static let micro:  CGFloat    = 8
    static let tiny:   CGFloat    = 9
    static let small:  CGFloat    = 10
    static let body:   CGFloat    = 11
    static let medium: CGFloat    = 12
    static let title:  CGFloat    = 13
    static let large:  CGFloat    = 14
    static let xl:     CGFloat    = 18
    static let xxl:    CGFloat    = 22
}

extension Font {
    /// Primary font — defaults to Space Mono, falls back to system mono.
    static func etherMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(EtherType.fontFamily, size: size)
            .weight(weight)
    }

    /// Variant font — for display/headers when you want typographic contrast.
    static func etherVariant(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(EtherType.variantFamily, size: size)
            .weight(weight)
    }

    /// UI labels, section headers.
    static func etherLabel(_ size: CGFloat = EtherType.body, weight: Font.Weight = .regular) -> Font {
        .custom(EtherType.fontFamily, size: size)
            .weight(weight)
    }

    /// Small uppercase section header. Paired with tracking and tertiary color.
    static let etherSectionHeader = Font.custom(EtherType.fontFamily, size: EtherType.tiny)
        .weight(.semibold)
}

// MARK: - Formatters

enum EtherFormat {
    /// 63 Hz, 250 Hz, 1.00 kHz, 3.20 kHz, 16.0 kHz — always 3 significant figures
    static func frequency(_ hz: Float) -> String {
        if hz < 1000 {
            return "\(Int(hz.rounded())) Hz"
        }
        let k = hz / 1000
        if k < 10 { return String(format: "%.2f kHz", k) }
        if k < 100 { return String(format: "%.1f kHz", k) }
        return String(format: "%.0f kHz", k)
    }

    /// +4.5 dB, -12.0 dB, 0.0 dB — always signed, always one decimal
    static func gain(_ db: Float) -> String {
        String(format: "%+.1f dB", db)
    }

    /// 1.00, 0.71, 10.0 — three sig figs
    static func q(_ q: Float) -> String {
        if q < 1 { return String(format: "%.2f", q) }
        if q < 10 { return String(format: "%.2f", q) }
        return String(format: "%.1f", q)
    }
}

// MARK: - Noise Texture

struct NoiseTexture: View {
    var opacity: Double = 0.03
    var body: some View {
        Canvas { ctx, size in
            let w = Int(size.width)
            let h = Int(size.height)
            for x in stride(from: 0, to: w, by: 1) {
                for y in stride(from: 0, to: h, by: 1) {
                    let hash = ((x &* 374761393) ^ (y &* 668265263) &+ 1274126177)
                    let v = Double(abs(hash) % 256) / 255.0
                    if v > 0.45 {
                        let rect = CGRect(x: x, y: y, width: 1, height: 1)
                        ctx.fill(Path(rect), with: .color(.white.opacity((v - 0.45) * opacity * 3)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .drawingGroup()
    }
}

// MARK: - Panel Style

struct EtherPanel: ViewModifier {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.etherSurface)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.clear)
                        .overlay(NoiseTexture(opacity: 0.025))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
            )
    }
}

extension View {
    func etherPanel(padding: CGFloat = 12, cornerRadius: CGFloat = 4) -> some View {
        modifier(EtherPanel(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Custom Slider

struct EtherSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var disabled: Bool = false

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 4
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = normalized * w

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: h)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(disabled ? 0.1 : 0.3))
                    .frame(width: max(0, thumbX), height: h)

                Circle()
                    .fill(disabled ? Color.etherTextTertiary : Color.etherTextPrimary)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .offset(x: thumbX - 5)
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard !disabled else { return }
                        isDragging = true
                        let t = Float(max(0, min(1, g.location.x / w)))
                        value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.1), value: isDragging)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Custom Gain Slider

struct EtherGainSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -12...12

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 6
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = normalized * w
            let tint = Color.gainTint(for: value)

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: h)

                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: max(0, thumbX), height: h)

                // Thumb
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .offset(x: thumbX - 7)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        let t = Float(max(0, min(1, g.location.x / w)))
                        value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - Ether Button Style

struct EtherButtonStyle: ButtonStyle {
    var color: Color = .etherAccent
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.etherMono(EtherType.small, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(filled ? 0.2 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == EtherButtonStyle {
    static var ether: EtherButtonStyle { EtherButtonStyle() }
    static func ether(color: Color, filled: Bool = false) -> EtherButtonStyle {
        EtherButtonStyle(color: color, filled: filled)
    }
}

// MARK: - Section Header

struct EtherSectionHeader: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            // Left tick
            Rectangle()
                .fill(Color.etherAccent.opacity(0.5))
                .frame(width: 2, height: 8)
            Text(text.uppercased())
                .font(.etherSectionHeader)
                .tracking(2.0)
                .foregroundColor(.etherTextTertiary)
        }
    }
}

// MARK: - Section Divider (technical tick-mark rule)

struct EtherDivider: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let mid = h / 2

            // Center line
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: w, y: mid))
            ctx.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 0.5)

            // Tick marks
            let ticks = 12
            for i in 0...ticks {
                let x = CGFloat(i) / CGFloat(ticks) * w
                let tickH: CGFloat = (i == 0 || i == ticks || i == ticks / 2) ? 4 : 2
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: mid - tickH / 2))
                tick.addLine(to: CGPoint(x: x, y: mid + tickH / 2))
                ctx.stroke(tick, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
            }
        }
        .frame(height: 6)
    }
}
