import SwiftUI
import AppKit

/// Invisible NSView that forwards mouseDown events to the window so the user
/// can drag the borderless window by clicking this region.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}
