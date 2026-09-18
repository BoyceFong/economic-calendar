import AppKit
import SwiftUI

/// Window drag region (title bar only, parity with the Qt drag area).
/// Left-click starts a system move; right-click passes through so the
/// SwiftUI context menu still opens.
final class DragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

struct DragRegionView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}
}

/// Ctrl+click → copy, parity with the Qt eventFilter behavior. The view only
/// participates in hit-testing while ⌃ is held; otherwise events flow to
/// SwiftUI untouched (double-click, hover, context menu).
final class ControlClickNSView: NSView {
    var onControlClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        NSEvent.modifierFlags.contains(.control) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onControlClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

struct ControlClickCatcher: NSViewRepresentable {
    let onControlClick: () -> Void

    func makeNSView(context: Context) -> ControlClickNSView {
        let view = ControlClickNSView()
        view.onControlClick = onControlClick
        return view
    }

    func updateNSView(_ nsView: ControlClickNSView, context: Context) {
        nsView.onControlClick = onControlClick
    }
}
