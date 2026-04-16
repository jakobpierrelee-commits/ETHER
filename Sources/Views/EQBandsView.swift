import SwiftUI
import AppKit

// MARK: - EQ Curve + Handles (Unified Pro Layout)

struct EQBandsView: View {
    @EnvironmentObject var engine: EngineManager
    @ObservedObject var controller: EQController
    @ObservedObject private var theme = ThemeManager.shared

    private let minGain: Float = -24
    private let maxGain: Float = +24
    private let minFreq: Float = 20
    private let maxFreq: Float = 20_000

    @State private var hoveredBandID: UUID?
    @State private var dragAnchor: DragAnchor?
    @State private var dragAxisLock: DragAxis = .free
    @State private var scrollMonitor: Any?
    @State private var showSuggestions = false

    var body: some View {
        VStack(spacing: 8) {
            // Minimal header — no visualizer selector, no loud FLAT button
            HStack {
                EtherSectionHeader(text: "Equalizer")
                Spacer()

                if controller.bypassed {
                    Text("BYPASSED")
                        .font(.etherMono(8, weight: .semibold))
                        .tracking(1.0)
                        .foregroundColor(.etherWarning)
                }

                // Reference match
                Button {
                    loadReferenceFile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 9))
                        Text("Match")
                            .font(.etherMono(10))
                    }
                    .foregroundColor(engine.autoEQ.hasEnoughData ? .etherAccent : .etherTextTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!engine.autoEQ.hasEnoughData)
                .help("Load a reference track — Ether sets the EQ to match its tonal balance")

                // AI Suggest button
                Button {
                    engine.autoEQ.analyze()
                    showSuggestions = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("AI Suggest")
                            .font(.etherMono(10))
                    }
                    .foregroundColor(engine.autoEQ.hasEnoughData ? .etherAccent : .etherTextTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!engine.autoEQ.hasEnoughData)
                .help(engine.autoEQ.hasEnoughData
                    ? "Analyze recent audio and suggest tonal corrections"
                    : "Start the engine and let audio play for a few seconds")

                Button("Reset") { controller.reset() }
                    .font(.etherMono(10))
                    .buttonStyle(.plain)
                    .foregroundColor(.etherTextTertiary)
            }

            // One integrated canvas — no visible sub-regions
            GeometryReader { geo in
                ZStack {
                    // Ghost spectrum — post-EQ only (what you're actually hearing)
                    GhostSpectrum(analyzer: engine.postSpectrum)
                        .opacity(0.65)

                    // Dot-grid backdrop
                    dotGrid(size: geo.size)

                    // Per-band filled contribution areas (colored)
                    bandContributions(size: geo.size)

                    // Combined curve — thin white line on top
                    combinedCurve(size: geo.size)

                    // Q envelope for selected/hovered band
                    if let bandID = controller.selectedBandID ?? hoveredBandID,
                       let band = controller.bands.first(where: { $0.id == bandID }),
                       let index = controller.bands.firstIndex(where: { $0.id == bandID }) {
                        qEnvelope(band: band, color: EQController.color(for: index), size: geo.size)
                    }

                    // Handles
                    ForEach(Array(controller.bands.enumerated()), id: \.element.id) { i, band in
                        handleView(band: band, index: i, size: geo.size)
                    }

                    // Floating band info card (Ozone-style)
                    if let hoveredID = hoveredBandID,
                       let band = controller.bands.first(where: { $0.id == hoveredID }),
                       let index = controller.bands.firstIndex(where: { $0.id == hoveredID }) {
                        bandInfoCard(band: band, index: index, size: geo.size)
                    }

                    // Axis labels (dB on left, freq on bottom)
                    axisLabels(size: geo.size)

                    // Ghost preview curve if suggestions are active
                    if showSuggestions && !engine.autoEQ.suggestions.isEmpty {
                        suggestionGhostCurve(size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(
                    ZStack {
                        Color(white: 0.015)
                        NoiseTexture(opacity: 0.015)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        hoveredBandID = nearestHandle(to: location, size: geo.size)
                        if let hid = hoveredBandID,
                           let idx = controller.bands.firstIndex(where: { $0.id == hid }) {
                            controller.highlightedKnobID = MacroKnob.all.first(where: { $0.bandIndices.contains(idx) })?.id
                        } else {
                            controller.highlightedKnobID = nil
                        }
                    case .ended:
                        hoveredBandID = nil
                        controller.highlightedKnobID = nil
                    }
                }
                .onTapGesture {
                    controller.selectedBandID = nil
                }
                .overlay(alignment: .topTrailing) {
                    if showSuggestions {
                        SuggestionPanel(
                            analyzer: engine.autoEQ,
                            controller: controller,
                            isPresented: $showSuggestions
                        )
                        .padding(12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showSuggestions)
            }
            .frame(height: 280)
        }
    }

    // MARK: - Suggestion ghost curve

    /// Dashed preview of the combined curve with suggested changes applied.
    private func suggestionGhostCurve(size: CGSize) -> some View {
        // Build a map of proposed deltas per band index
        var deltas = [Int: Float]()
        for s in engine.autoEQ.suggestions {
            deltas[s.bandIndex, default: 0] += s.gainDelta
        }

        return Canvas { ctx, _ in
            let w = size.width, h = size.height
            let steps = 160

            var path = Path()
            for s in 0...steps {
                let x = CGFloat(s) / CGFloat(steps) * w
                let freq = freqForX(x, width: w)
                let gain = previewGain(at: freq, deltas: deltas)
                let y = yForGain(gain, height: h)
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            ctx.stroke(
                path,
                with: .color(.etherAccent.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
            )
        }
    }

    /// Gain at a given frequency if the proposed deltas were applied.
    private func previewGain(at freq: Float, deltas: [Int: Float]) -> Float {
        if controller.bypassed { return 0 }
        var total: Float = 0
        for (index, band) in controller.bands.enumerated() where !band.bypassed && band.type.usesGain {
            let proposedGain = band.gain + (deltas[index] ?? 0)
            let adjusted = EQBand(
                id: band.id,
                frequency: band.frequency,
                gain: proposedGain,
                q: band.q,
                type: band.type,
                bypassed: band.bypassed
            )
            total += bandContribution(band: adjusted, freq: freq)
        }
        return max(minGain, min(maxGain, total + controller.masterGain))
    }

    // MARK: - Dot Grid

    private func dotGrid(size: CGSize) -> some View {
        Canvas { ctx, _ in
            let h = size.height, w = size.width
            let dbStops: [Float] = [-24, -18, -12, -6, 0, 6, 12, 18, 24]
            let freqStops: [Float] = [20, 30, 50, 80, 100, 200, 300, 500, 800, 1000, 2000, 3000, 5000, 8000, 10_000, 16_000]

            // Horizontal dB grid lines — thin scanlines
            for db in dbStops {
                let y = yForGain(db, height: h)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y))
                let alpha = (db == 0) ? 0.10 : (db.truncatingRemainder(dividingBy: 12) == 0 ? 0.06 : 0.03)
                ctx.stroke(line, with: .color(.white.opacity(alpha)), lineWidth: 0.5)
            }

            // Vertical freq grid lines
            for fq in freqStops {
                let x = xForFreq(fq, width: w)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: h))
                let major = [100, 1000, 10000].contains(Int(fq))
                ctx.stroke(line, with: .color(.white.opacity(major ? 0.06 : 0.025)), lineWidth: 0.5)
            }

            // Plus markers at major intersections only
            let majorDB: [Float] = [-24, -12, 0, 12, 24]
            let majorFreq: [Float] = [100, 500, 1000, 5000, 10_000]
            let arm: CGFloat = 2.5
            for db in majorDB {
                let y = yForGain(db, height: h)
                for fq in majorFreq {
                    let x = xForFreq(fq, width: w)
                    var plus = Path()
                    plus.move(to: CGPoint(x: x - arm, y: y))
                    plus.addLine(to: CGPoint(x: x + arm, y: y))
                    plus.move(to: CGPoint(x: x, y: y - arm))
                    plus.addLine(to: CGPoint(x: x, y: y + arm))
                    ctx.stroke(plus, with: .color(.white.opacity(db == 0 ? 0.18 : 0.08)), lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: - Per-band Contributions (filled colored areas, soft feathered edges)

    private func bandContributions(size: CGSize) -> some View {
        Canvas { ctx, _ in
            guard !controller.bypassed else { return }
            let w = size.width, h = size.height
            let steps = 140

            for (i, band) in controller.bands.enumerated() {
                guard !band.bypassed, band.type.usesGain, abs(band.gain) > 0.01 else { continue }

                let color = EQController.color(for: i)
                let midY = h / 2

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                for s in 0...steps {
                    let x = CGFloat(s) / CGFloat(steps) * w
                    let freq = freqForX(x, width: w)
                    let contrib = bandContribution(band: band, freq: freq)
                    let y = yForGain(contrib, height: h)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: midY))
                path.closeSubpath()

                // Wide bloom halo
                var bloom = ctx
                bloom.addFilter(.blur(radius: 14))
                bloom.fill(path, with: .color(color.opacity(0.22)))

                // Soft outer halo
                var halo = ctx
                halo.addFilter(.blur(radius: 6))
                halo.fill(path, with: .color(color.opacity(0.25)))

                // Main fill with vertical gradient fade toward 0 dB line
                ctx.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.52), color.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: band.gain > 0 ? 0 : h),
                        endPoint:   CGPoint(x: 0, y: band.gain > 0 ? h : 0)
                    )
                )
            }
        }
        .blendMode(.screen)
        // Slight overall blur softens the outlines further
        .blur(radius: 0.6)
    }

    // MARK: - Combined Curve (thin white line)

    private func combinedCurve(size: CGSize) -> some View {
        let rainbow = ThemeManager.shared.curveGradient
        return Canvas { ctx, _ in
            let w = size.width, h = size.height
            let steps = 200

            var path = Path()
            for s in 0...steps {
                let x = CGFloat(s) / CGFloat(steps) * w
                let freq = freqForX(x, width: w)
                let gain = totalGain(at: freq)
                let y = yForGain(gain, height: h)
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            let grad = Gradient(colors: rainbow)
            let start = CGPoint(x: 0, y: h / 2)
            let end = CGPoint(x: w, y: h / 2)

            // Colored stroke — no glow
            ctx.stroke(path, with: .linearGradient(grad, startPoint: start, endPoint: end), lineWidth: 1.5)

            // Crisp white edge on top
            ctx.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 0.5)
        }
    }

    // MARK: - Axis Labels

    private func axisLabels(size: CGSize) -> some View {
        ZStack {
            // dB labels, vertical
            VStack(alignment: .leading) {
                ForEach([24, 12, 0, -12, -24], id: \.self) { db in
                    HStack {
                        Text(db == 0 ? "0" : "\(db > 0 ? "+" : "")\(db)")
                            .font(.etherMono(EtherType.micro))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 20, alignment: .leading)
                            .padding(.leading, 6)
                        Spacer()
                    }
                    if db != -24 { Spacer() }
                }
            }

            // Freq labels, horizontal, bottom — tinted by position in the rainbow
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    let freqs: [Int] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
                    ForEach(freqs, id: \.self) { fq in
                        let x = xForFreq(Float(fq), width: size.width)
                        Text(fq < 1000 ? "\(fq)" : "\(fq / 1000)k")
                            .font(.etherMono(EtherType.micro))
                            .foregroundColor(.white.opacity(0.3))
                            .position(x: x, y: size.height - 8)
                    }
                }
                .frame(height: 0)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Handles

    @ViewBuilder
    private func handleView(band: EQBand, index: Int, size: CGSize) -> some View {
        let color = EQController.color(for: index)
        let x = xForFreq(band.frequency, width: size.width)
        let y = band.type.usesGain ? yForGain(band.gain, height: size.height) : size.height / 2
        let isSelected = controller.selectedBandID == band.id
        let isHovered = hoveredBandID == band.id
        let isBypassed = band.bypassed
        let isKnobLinked = controller.highlightedBandIndices.contains(index)

        ZStack {
            // Soft glow behind the handle — intensified when knob-linked
            Circle()
                .fill(color.opacity(isKnobLinked ? 0.7 : (isHovered ? 0.5 : 0.25)))
                .frame(width: isKnobLinked ? 28 : 22, height: isKnobLinked ? 28 : 22)
                .blur(radius: isKnobLinked ? 10 : 6)
            if isSelected || isKnobLinked {
                Circle()
                    .strokeBorder(color.opacity(isKnobLinked ? 0.8 : 0.5), lineWidth: isKnobLinked ? 2 : 1.5)
                    .frame(width: 22, height: 22)
            }
            Circle()
                .fill(isBypassed ? Color.white.opacity(0.15) : color)
                .frame(width: 9, height: 9)
            Circle()
                .strokeBorder(Color.white.opacity(isHovered || isKnobLinked ? 0.9 : 0.6), lineWidth: 1)
                .frame(width: 9, height: 9)
        }
        .scaleEffect(isKnobLinked ? 1.35 : (isHovered ? 1.25 : 1.0))
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isKnobLinked)
        .position(x: x, y: y)
        .gesture(handleDragGesture(bandID: band.id, size: size))
        .onTapGesture(count: 2) { controller.resetBand(bandID: band.id) }
        .contextMenu { bandContextMenu(band: band) }
        .onAppear { installScrollMonitorIfNeeded() }
    }

    // MARK: - Reference Match

    private func loadReferenceFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a reference track. Ether will set the EQ to match its tonal balance."
        panel.prompt = "Match"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Offload decoding + FFT to a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let current = engine.autoEQ.currentAverageBins
            let bandFreqs = EQController.defaultFrequencies
            do {
                let suggestions = try engine.referenceMatcher.analyze(
                    referenceURL: url,
                    currentAverageBins: current,
                    bandFrequencies: bandFreqs
                )
                DispatchQueue.main.async {
                    engine.autoEQ.setSuggestions(suggestions)
                    showSuggestions = true
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Reference match failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    /// Returns the band whose handle is closest to `location`, or nil if no
    /// handle is within the hover threshold.
    private func nearestHandle(to location: CGPoint, size: CGSize) -> UUID? {
        let threshold: CGFloat = 24
        var best: (id: UUID, distance: CGFloat)?
        for band in controller.bands {
            let hx = xForFreq(band.frequency, width: size.width)
            let hy = band.type.usesGain ? yForGain(band.gain, height: size.height) : size.height / 2
            let dx = location.x - hx
            let dy = location.y - hy
            let d = sqrt(dx * dx + dy * dy)
            if best == nil || d < best!.distance {
                best = (band.id, d)
            }
        }
        if let best = best, best.distance < threshold { return best.id }
        return nil
    }

    private func handleDragGesture(bandID: UUID, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let band = controller.bands.first(where: { $0.id == bandID }) else { return }
                let shift = NSEvent.modifierFlags.contains(.shift)
                let cmdOrOpt = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.option)

                if dragAnchor == nil {
                    dragAnchor = DragAnchor(
                        startFreq: band.frequency,
                        startGain: band.gain,
                        startLocation: value.startLocation
                    )
                    controller.selectedBandID = bandID
                }
                guard let anchor = dragAnchor else { return }

                if shift && dragAxisLock == .free {
                    let adx = abs(value.translation.width)
                    let ady = abs(value.translation.height)
                    if max(adx, ady) > 4 {
                        dragAxisLock = adx > ady ? .horizontal : .vertical
                    }
                }

                let fine: CGFloat = cmdOrOpt ? 0.2 : 1.0
                let dx = value.translation.width * fine
                let dy = value.translation.height * fine

                if dragAxisLock != .vertical {
                    let startX = xForFreq(anchor.startFreq, width: size.width)
                    let newX = max(0, min(size.width, startX + dx))
                    var newFreq = freqForX(newX, width: size.width)
                    if shift { newFreq = snapToISO(newFreq) }
                    controller.setFrequency(bandID: bandID, frequency: newFreq)
                }

                if dragAxisLock != .horizontal && band.type.usesGain {
                    let startY = yForGain(anchor.startGain, height: size.height)
                    let newY = max(0, min(size.height, startY + dy))
                    let newGain = gainForY(newY, height: size.height)
                    controller.setGain(bandID: bandID, gain: newGain)
                }
            }
            .onEnded { _ in
                dragAnchor = nil
                dragAxisLock = .free
            }
    }

    @ViewBuilder
    private func bandContextMenu(band: EQBand) -> some View {
        Menu("Filter Type") {
            ForEach(EQFilterType.allCases) { type in
                Button {
                    controller.setType(bandID: band.id, type: type)
                } label: {
                    HStack {
                        if type == band.type { Image(systemName: "checkmark") }
                        Text(type.displayName)
                    }
                }
            }
        }
        Divider()
        Button(band.bypassed ? "Enable Band" : "Bypass Band") {
            controller.toggleBypass(bandID: band.id)
        }
        Button("Reset Band") {
            controller.resetBand(bandID: band.id)
        }
    }

    // MARK: - Floating band info card (Ozone style)

    private func bandInfoCard(band: EQBand, index: Int, size: CGSize) -> some View {
        let color = EQController.color(for: index)
        let x = xForFreq(band.frequency, width: size.width)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(band.type.displayName)
                    .font(.etherMono(EtherType.small, weight: .medium))
                    .foregroundColor(.white)
            }
            HStack(spacing: 8) {
                infoRow(label: "Freq", value: EtherFormat.frequency(band.frequency))
                if band.type.usesGain {
                    infoRow(label: "Gain", value: EtherFormat.gain(band.gain))
                }
                infoRow(label: "Q", value: EtherFormat.q(band.q))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .fixedSize()
        .position(x: min(size.width - 90, max(90, x)), y: 32)
        .allowsHitTesting(false)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.etherMono(EtherType.micro))
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.etherMono(EtherType.tiny, weight: .medium))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    // MARK: - Q envelope

    private func qEnvelope(band: EQBand, color: Color, size: CGSize) -> some View {
        guard band.type.usesGain else { return AnyView(EmptyView()) }
        let centerX = xForFreq(band.frequency, width: size.width)
        let bandwidth = 1.0 / band.q
        let loFreq = band.frequency * pow(2, -bandwidth)
        let hiFreq = band.frequency * pow(2, +bandwidth)
        let loX = xForFreq(loFreq, width: size.width)
        let hiX = xForFreq(hiFreq, width: size.width)

        return AnyView(
            ZStack {
                ForEach([loX, hiX], id: \.self) { x in
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                Path { p in
                    p.move(to: CGPoint(x: centerX, y: 0))
                    p.addLine(to: CGPoint(x: centerX, y: size.height))
                }
                .stroke(color.opacity(0.5), lineWidth: 0.5)
                    .opacity(0.8)
            }
            .allowsHitTesting(false)
        )
    }

    // MARK: - Curve math

    private func totalGain(at freq: Float) -> Float {
        if controller.bypassed { return 0 }
        var total: Float = 0
        for band in controller.bands where !band.bypassed && band.type.usesGain {
            total += bandContribution(band: band, freq: freq)
        }
        return max(minGain, min(maxGain, total + controller.masterGain))
    }

    private func bandContribution(band: EQBand, freq: Float) -> Float {
        let octaves = log2(freq / band.frequency)
        let bandwidth = 1.0 / band.q
        switch band.type {
        case .bell:
            let x = octaves / bandwidth
            return band.gain * exp(-x * x)
        case .lowShelf:
            let x = -octaves / bandwidth
            return band.gain * (1.0 / (1.0 + exp(-x * 2)))
        case .highShelf:
            let x = octaves / bandwidth
            return band.gain * (1.0 / (1.0 + exp(-x * 2)))
        default:
            return 0
        }
    }

    // MARK: - Scroll-to-Q

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            Task { @MainActor in
                if let hoveredID = hoveredBandID,
                   let band = controller.bands.first(where: { $0.id == hoveredID }) {
                    let fine = event.modifierFlags.contains(.shift)
                    let delta = Float(event.deltaY) * (fine ? 0.02 : 0.1)
                    let newQ = max(0.1, min(20, band.q + delta))
                    controller.setQ(bandID: hoveredID, q: newQ)
                }
            }
            return event
        }
    }

    // MARK: - Coordinate conversion

    private func xForFreq(_ freq: Float, width: CGFloat) -> CGFloat {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logF = log10(max(minFreq, min(maxFreq, freq)))
        return CGFloat((logF - logMin) / (logMax - logMin)) * width
    }

    private func freqForX(_ x: CGFloat, width: CGFloat) -> Float {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let t = Float(max(0, min(1, x / width)))
        return pow(10, logMin + (logMax - logMin) * t)
    }

    private func yForGain(_ gain: Float, height: CGFloat) -> CGFloat {
        let t = (gain - minGain) / (maxGain - minGain)
        return height * (1 - CGFloat(t))
    }

    private func gainForY(_ y: CGFloat, height: CGFloat) -> Float {
        let t = 1 - Float(y / height)
        return max(minGain, min(maxGain, minGain + t * (maxGain - minGain)))
    }

    private func snapToISO(_ freq: Float) -> Float {
        let iso: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
            630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
            10000, 12500, 16000, 20000
        ]
        return iso.min(by: { abs($0 - freq) < abs($1 - freq) }) ?? freq
    }
}

// MARK: - Ghost Spectrum (desaturated, subtle, sits behind)

private struct GhostSpectrum: View {
    @ObservedObject var analyzer: SpectrumAnalyzer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !analyzer.isActive)) { _ in
            Canvas { ctx, size in
                let bins = analyzer.magnitudes
                guard bins.count > 1 else { return }
                let w = size.width, h = size.height

                var points: [CGPoint] = []
                points.reserveCapacity(bins.count)
                for i in 0..<bins.count {
                    let x = CGFloat(i) / CGFloat(bins.count - 1) * w
                    let normalized = max(0, min(1, (bins[i] + 80) / 80))
                    let y = h * (1 - CGFloat(normalized))
                    points.append(CGPoint(x: x, y: y))
                }

                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                if let first = points.first { path.addLine(to: first) }
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]
                    let midX = (prev.x + curr.x) / 2
                    let c1 = CGPoint(x: midX, y: prev.y)
                    let c2 = CGPoint(x: midX, y: curr.y)
                    path.addCurve(to: curr, control1: c1, control2: c2)
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()

                // Stroke: rainbow trace along the top edge
                let rainbow = EQController.rainbowGradient
                ctx.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: rainbow.map { $0.opacity(0.45) }),
                        startPoint: CGPoint(x: 0, y: h / 2),
                        endPoint: CGPoint(x: w, y: h / 2)
                    ),
                    lineWidth: 1.5
                )

                // Glow behind the stroke
                var glow = ctx
                glow.addFilter(.blur(radius: 4))
                glow.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: rainbow.map { $0.opacity(0.2) }),
                        startPoint: CGPoint(x: 0, y: h / 2),
                        endPoint: CGPoint(x: w, y: h / 2)
                    ),
                    lineWidth: 4
                )

                // Fill: rainbow horizontal gradient fading down
                ctx.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: rainbow.map { $0.opacity(0.12) }),
                        startPoint: CGPoint(x: 0, y: h / 2),
                        endPoint: CGPoint(x: w, y: h / 2)
                    )
                )
            }
        }
    }
}

// MARK: - Drag Anchor

private struct DragAnchor {
    let startFreq: Float
    let startGain: Float
    let startLocation: CGPoint
}

private enum DragAxis {
    case free, horizontal, vertical
}
