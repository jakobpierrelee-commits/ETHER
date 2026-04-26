import SwiftUI
import AppKit
import Sparkle

struct VisualizerCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Visualizer") {
            Button("Ring Visualizer") { openWindow(id: "visualizer") }
                .keyboardShortcut("v", modifiers: .command)
            Button("Sphere Visualizer") { openWindow(id: "sphere") }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}

struct SkinCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("Skins") {
            Button("Ethereal (preview)") { openWindow(id: "ethereal") }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}

@main
struct EtherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engineManager = EngineManager()
    @StateObject private var eqController = EQController()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var launchAtLogin = LaunchAtLogin()
    @StateObject private var globalHotkeys = GlobalHotkeys()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // ── Main window ────────────────────────────────────────────────
        Window("Ether", id: "main") {
            ContentView(eqController: eqController, profileStore: profileStore)
                .environmentObject(engineManager)
                .environmentObject(launchAtLogin)
                .environmentObject(globalHotkeys)
                .onAppear {
                    appDelegate.engineManager = engineManager
                    eqController.engine = engineManager
                    engineManager.controller = eqController
                    engineManager.restoreOutputIfStuckOnVirtual()
                    if let id = profileStore.currentProfileID,
                       let profile = profileStore.profiles.first(where: { $0.id == id }) {
                        eqController.load(bands: profile.eqBands, masterGain: profile.masterGain, knobValues: profile.knobValues ?? [:])
                    }
                    // Wire global hotkeys to controller actions
                    globalHotkeys.onBypassToggle = { eqController.toggleGlobalBypass() }
                    globalHotkeys.onABToggle = {
                        NotificationCenter.default.post(name: .toggleABSlots, object: nil)
                    }
                    globalHotkeys.install()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    engineManager.spectrum.isActive = (newPhase == .active)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ether") {
                    let alert = NSAlert()
                    alert.messageText = "Ether"
                    alert.informativeText = "System Audio Equalizer\n\nv\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")\n\nBuilt on Core Audio HAL\nhttps://github.com/jakobpierrelee-commits/ETHER"
                    alert.runModal()
                }
                Divider()
                Button("Check for Updates…") {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { eqController.undoManager.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!eqController.undoManager.canUndo)
                Button("Redo") { eqController.undoManager.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!eqController.undoManager.canRedo)
            }
            CommandMenu("EQ") {
                Button(eqController.bypassed ? "Un-bypass All" : "Bypass All") {
                    eqController.toggleGlobalBypass()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Reset to Flat") { eqController.reset() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            VisualizerCommands()
            SkinCommands()
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showShortcuts, object: nil)
                }
                .keyboardShortcut("?", modifiers: [.shift])
            }
        }

        // ── Advanced window (opened from gear icon in main header) ─────
        Window("Ether — Advanced", id: "advanced") {
            AdvancedView(
                spatial: engineManager.spatial,
                loudness: engineManager.loudness,
                hotkeys: globalHotkeys,
                denoise: engineManager.denoise
            )
            .environmentObject(engineManager)
        }
        .defaultSize(width: 620, height: 720)
        .windowResizability(.contentSize)

        // ── Experimental tuning (spike) ────────────────────────────────
        Window("Ether — Experimental", id: "experimental") {
            ExperimentalTuningView()
                .environmentObject(engineManager)
        }
        .defaultSize(width: 720, height: 720)
        .windowResizability(.contentSize)

        // ── Visualizer (fullscreen-capable) ───────────────────────────────
        Window("Ether — Visualizer", id: "visualizer") {
            VisualizerView()
                .environmentObject(engineManager)
        }
        .defaultSize(width: 900, height: 600)
        .windowStyle(.hiddenTitleBar)

        // ── Sphere visualizer ──────────────────────────────────────────────
        Window("Ether — Sphere", id: "sphere") {
            SphereVisualizerWindowView()
                .environmentObject(engineManager)
        }
        .defaultSize(width: 800, height: 800)
        .windowStyle(.hiddenTitleBar)

        // ── Ethereal skin (dev spike) ──────────────────────────────────────
        Window("Ether — Ethereal", id: "ethereal") {
            EtherealSkinView(controller: eqController)
                .environmentObject(engineManager)
        }
        .defaultSize(width: 960, height: 680)
        .windowStyle(.hiddenTitleBar)

        // ── Menu bar popover ────────────────────────────────────────────
        MenuBarExtra("Ether", systemImage: "waveform") {
            MenuBarContent(controller: eqController, profileStore: profileStore)
                .environmentObject(engineManager)
        }
        .menuBarExtraStyle(.window)

        // ── Settings ────────────────────────────────────────────────────
        Settings {
            PreferencesView(launchAtLogin: launchAtLogin, hotkeys: globalHotkeys)
                .environmentObject(engineManager)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var engineManager: EngineManager?
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        if let existing = others.first {
            existing.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engineManager?.emergencyRestore()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

extension Notification.Name {
    static let showShortcuts = Notification.Name("audio.ether.showShortcuts")
    static let toggleABSlots = Notification.Name("audio.ether.toggleAB")
}
