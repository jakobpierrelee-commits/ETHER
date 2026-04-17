import AppKit
import SwiftUI

final class WideMiniPlayerPanel {
    static let shared = WideMiniPlayerPanel()
    private var panel: NSPanel?

    func show(controller: EQController, engine: EngineManager) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = WideMiniPlayerView(controller: controller)
            .environmentObject(engine)

        let hostingView = NSHostingView(rootView: view)
        let initialRect = NSRect(x: 0, y: 0, width: 440, height: 72)
        hostingView.frame = initialRect

        let panel = NSPanel(
            contentRect: initialRect,
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
        panel.minSize = NSSize(width: 320, height: 62)
        panel.maxSize = NSSize(width: 640, height: 88)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 220
            let y = screenFrame.maxY - 90
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
