import AppKit

/// Frameless, non-activating panel — the native equivalent of the Qt window
/// flags (FramelessWindowHint + optional WindowStaysOnTopHint) plus the
/// user-chosen "don't steal keyboard focus" behavior. Clicking the calendar
/// never takes focus away from the app you're typing in.
final class AppPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static func makeAlwaysOnTop(_ on: Bool) -> NSWindow.Level {
        on ? .floating : .normal
    }

    /// Runtime toggle; unlike Qt there's no need to rebuild flags/re-show.
    func toggleAlwaysOnTop() -> Bool {
        let on = !AppSettings.alwaysOnTop
        level = Self.makeAlwaysOnTop(on)
        return on
    }

    /// Restore geometry from persisted macOS top-left coordinates; falls back
    /// to a centered 578×705 card (the legacy default size).
    func restoreFrame() {
        let geometry = AppSettings.geometry
        let size = NSSize(width: geometry.width, height: geometry.height)
        setContentSize(size)
        if geometry.origin != .zero {
            setFrameTopLeftPoint(NSPoint(x: geometry.origin.x, y: geometry.origin.y))
        } else {
            center()
        }
    }

    func persistFrame() {
        let frame = self.frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        AppSettings.geometry = CGRect(origin: topLeft, size: frame.size)
    }

    /// Borderless-window shadows go stale after moves; nudge AppKit to re-read
    /// the opaque pixels.
    func invalidateCardShadow() {
        invalidateShadow()
    }
}
