import AppKit

@MainActor
public enum DockBadge {
    public static func set(_ label: String?) {
        guard let app = NSApp else { return }
        app.dockTile.badgeLabel = label
    }

    public static func clear() {
        set(nil)
    }

    public static func setCount(_ count: Int) {
        set(count > 0 ? String(count) : nil)
    }
}
