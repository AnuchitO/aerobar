import AppKit

/// Decides how many workspace buttons to show and which contiguous slice
/// of the full workspace list to display, centered on the active one.
///
/// macOS gives no reliable, public way to measure exactly how many points
/// of menu-bar space are free next to a notch -- `NSScreen.auxiliaryTop*
/// Area` is intended for window content layout, not for sizing status
/// items, and doesn't account for other apps' menu-bar icons at all. So
/// rather than compute an unreliable pixel budget, this uses a simple,
/// predictable rule: on a notched display, cap the count at a sensible
/// fixed number (tunable); on a display without a notch, show everything.
enum NotchLayout {
    /// A MacBook with a camera notch reports a non-zero top safe-area
    /// inset on its built-in display. This is the standard, documented
    /// way to detect a notch and is reliable across macOS versions.
    static func hasNotch(screen: NSScreen? = NSScreen.main) -> Bool {
        (screen?.safeAreaInsets.top ?? 0) > 0
    }

    /// Default cap used on a notched display when the user hasn't set
    /// `max-visible-workspaces` explicitly. Comfortably fits next to every
    /// current MacBook Pro/Air notch alongside Wi-Fi/Battery/Clock.
    static let defaultNotchVisibleCount = 4

    static func visibleCount(configuredMax: Int?, totalCount: Int, screen: NSScreen? = NSScreen.main) -> Int {
        if let configuredMax {
            return max(1, min(configuredMax, totalCount))
        }
        guard hasNotch(screen: screen) else {
            return totalCount
        }
        return min(defaultNotchVisibleCount, totalCount)
    }

    /// The contiguous range of indices (into the full, ordered workspace
    /// list) to display, `count` wide, centered on `activeIndex` and
    /// clamped to the list's bounds. E.g. for 10 workspaces indexed 0..9
    /// with "9" active (index 8) and count 4, returns 6..<10 ("7 8 9 0").
    static func window(totalCount: Int, activeIndex: Int?, count: Int) -> Range<Int> {
        guard count < totalCount else { return 0..<totalCount }
        let anchor = activeIndex ?? 0
        let half = count / 2
        let start = max(0, min(anchor - half, totalCount - count))
        return start..<(start + count)
    }
}
