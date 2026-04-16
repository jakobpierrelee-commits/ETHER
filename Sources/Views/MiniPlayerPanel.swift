import AppKit
import SwiftUI

final class MiniPlayerPanel {
    static let shared = MiniPlayerPanel()
    private var panel: NSPanel?

    func show(controller: EQController, profileStore: ProfileStore, engine: EngineManager) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = MiniPlayerView(controller: controller, profileStore: profileStore)
            .environmentObject(engine)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 275)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 275),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 160, height: 200)
        panel.maxSize = NSSize(width: 320, height: 400)
        panel.aspectRatio = NSSize(width: 4, height: 5)

        // Center on screen initially
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 240
            let y = screenFrame.maxY - 300
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
