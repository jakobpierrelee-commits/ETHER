import AppKit
import Combine

final class NowPlayingManager: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var albumArt: NSImage?
    @Published var isPlaying: Bool = false
    @Published var dominantColor: NSColor = .black

    private var timer: Timer?
    private var handle: UnsafeMutableRawPointer?

    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private var sendCommandFn: SendCommandFn?

    private let kMRTogglePlayPause: UInt32 = 2
    private let kMRNextTrack: UInt32 = 4
    private let kMRPreviousTrack: UInt32 = 5

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        if let h = handle, let ptr = dlsym(h, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(ptr, to: SendCommandFn.self)
        }
        fetchNowPlaying()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.fetchNowPlaying()
        }
    }

    func fetchNowPlaying() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Try Spotify first, then Music
            let spotify = self?.querySpotify()
            let music = spotify == nil ? self?.queryMusic() : nil
            let info = spotify ?? music

            DispatchQueue.main.async {
                if let info {
                    self?.title = info.title
                    self?.artist = info.artist
                    self?.isPlaying = info.isPlaying
                    if let art = info.art {
                        self?.albumArt = art
                        self?.dominantColor = Self.extractDominantColor(from: art)
                    }
                } else {
                    self?.title = ""
                    self?.artist = ""
                    self?.isPlaying = false
                }
            }
        }
    }

    private struct TrackInfo {
        let title: String
        let artist: String
        let isPlaying: Bool
        let art: NSImage?
    }

    private func querySpotify() -> TrackInfo? {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return "NOT_RUNNING"
        end tell
        tell application "Spotify"
            if player state is stopped then return "STOPPED"
            set t to name of current track
            set a to artist of current track
            set s to player state as string
            return t & "|||" & a & "|||" & s
        end tell
        """
        guard let result = runAppleScript(script), result != "NOT_RUNNING", result != "STOPPED" else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }

        let art = getSpotifyArt()
        return TrackInfo(title: parts[0], artist: parts[1], isPlaying: parts[2] == "playing", art: art)
    }

    private func getSpotifyArt() -> NSImage? {
        let script = """
        tell application "Spotify"
            return artwork url of current track
        end tell
        """
        guard let urlString = runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return nil }

        // Synchronous fetch (we're already on background queue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    private func queryMusic() -> TrackInfo? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return "NOT_RUNNING"
        end tell
        tell application "Music"
            if player state is stopped then return "STOPPED"
            set t to name of current track
            set a to artist of current track
            set s to player state as string
            return t & "|||" & a & "|||" & s
        end tell
        """
        guard let result = runAppleScript(script), result != "NOT_RUNNING", result != "STOPPED" else { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }

        let art = getMusicArt()
        return TrackInfo(title: parts[0], artist: parts[1], isPlaying: parts[2] == "playing", art: art)
    }

    private func getMusicArt() -> NSImage? {
        let script = """
        tell application "Music"
            try
                set artData to raw data of artwork 1 of current track
                return artData
            end try
        end tell
        """
        // For Music.app, artwork comes as raw data through NSAppleScript
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        if let data = result?.data {
            return NSImage(data: data)
        }
        return nil
    }

    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return result?.stringValue
    }

    // MARK: - Commands (osascript shell for hardened runtime compatibility)

    func togglePlayPause() {
        sendCommand("playpause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.fetchNowPlaying() }
    }

    func nextTrack() {
        sendCommand("next track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.fetchNowPlaying() }
    }

    func previousTrack() {
        sendCommand("previous track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.fetchNowPlaying() }
    }

    private func sendCommand(_ command: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            // Detect which player is running, send via osascript
            let players = ["Spotify", "Music"]
            for player in players {
                let check = Process()
                check.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                check.arguments = ["-e", "tell application \"System Events\" to return exists process \"\(player)\""]
                let pipe = Pipe()
                check.standardOutput = pipe
                check.standardError = FileHandle.nullDevice
                try? check.run()
                check.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if output == "true" {
                    let cmd = Process()
                    cmd.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    cmd.arguments = ["-e", "tell application \"\(player)\" to \(command)"]
                    cmd.standardOutput = FileHandle.nullDevice
                    cmd.standardError = FileHandle.nullDevice
                    try? cmd.run()
                    cmd.waitUntilExit()
                    return
                }
            }
        }
    }

    static func extractDominantColor(from image: NSImage) -> NSColor {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return .black }

        // Sample a grid of pixels, find the most saturated common color
        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        let step = max(1, min(w, h) / 12)
        var bestColor: NSColor = .black
        var bestSat: CGFloat = 0

        for x in stride(from: w / 4, to: w * 3 / 4, by: step) {
            for y in stride(from: h / 4, to: h * 3 / 4, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.sRGB) else { continue }

                var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)

                // Prefer saturated, reasonably bright colors
                let score = sat * (0.3 + bri * 0.7)
                if score > bestSat {
                    bestSat = score
                    bestColor = color
                }
            }
        }

        return bestColor
    }

    deinit {
        timer?.invalidate()
        if let h = handle { dlclose(h) }
    }
}
