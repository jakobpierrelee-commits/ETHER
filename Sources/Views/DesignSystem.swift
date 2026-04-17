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
// Dual font scheme: SF Pro (proportional) for labels/UI, SF Mono for numeric readouts.
// SF Pro = Apple's system font, ships on every Mac. Clean, engineered for UI.
// SF Mono = system monospace. Used only where digits need to align (dB, Hz, %).

enum EtherType {
    static let monoFamily         = "SF Mono"

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
    /// Primary UI font — proportional SF Pro for all labels, headers, buttons.
    /// This is the default used throughout the app. Replaces the old Space Mono everywhere.
    static func etherMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Variant font — for display/headers. SF Pro Rounded for softer branding feel.
    static func etherVariant(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Numeric readout font — SF Mono for values that need to align (dB, Hz, Q, %).
    static func etherValue(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(EtherType.monoFamily, size: size)
            .weight(weight)
    }

    /// UI labels, section headers — proportional SF Pro.
    static func etherLabel(_ size: CGFloat = EtherType.body, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Small uppercase section header. Paired with tracking and tertiary color.
    static let etherSectionHeader = Font.system(size: EtherType.tiny, weight: .semibold, design: .default)
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
    var cornerRadius: CGFloat = 8
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(elevated ? Color.etherSurfaceHigh : Color.etherSurface)
                    .shadow(color: .black.opacity(elevated ? 0.35 : 0.2), radius: elevated ? 6 : 3, y: elevated ? 3 : 1)
            )
    }
}

extension View {
    func etherPanel(padding: CGFloat = 12, cornerRadius: CGFloat = 8, elevated: Bool = false) -> some View {
        modifier(EtherPanel(padding: padding, cornerRadius: cornerRadius, elevated: elevated))
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(filled ? 0.2 : 0.08))
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

// MARK: - Glass Dropdown

struct EtherDropdown<Label: View>: View {
    let options: [String]
    let selection: String?
    let onSelect: (String) -> Void
    let label: Label

    @State private var isOpen = false
    @State private var mouseLocation: CGPoint = .zero

    init(options: [String], selection: String?, onSelect: @escaping (String) -> Void, @ViewBuilder label: () -> Label) {
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
        self.label = label()
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                label
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.etherTextTertiary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(.easeOut(duration: 0.15), value: isOpen)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            GlassDropdownMenu(
                options: options,
                selection: selection,
                onSelect: { option in
                    onSelect(option)
                    isOpen = false
                }
            )
        }
    }
}

private struct GlassDropdownMenu: View {
    let options: [String]
    let selection: String?
    let onSelect: (String) -> Void
    @State private var hoveredOption: String?
    @State private var mousePos: CGPoint = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isHovered = hoveredOption == option
                let isSelected = selection == option

                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 8) {
                        if isSelected {
                            Circle()
                                .fill(Color.etherAccent)
                                .frame(width: 4, height: 4)
                        } else {
                            Spacer().frame(width: 4)
                        }
                        Text(option)
                            .font(.etherMono(EtherType.small))
                            .foregroundColor(isSelected ? .etherAccent : (isHovered ? .white : .etherTextPrimary))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isHovered ? Color.etherAccent.opacity(0.12) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredOption = $0 ? option : (hoveredOption == option ? nil : hoveredOption) }
            }
        }
        .padding(6)
        .frame(minWidth: 200)
        .background(Color.etherBackground.opacity(0.85))
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
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
