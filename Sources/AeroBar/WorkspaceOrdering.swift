import Foundation

/// Default ordering applied to the dynamically-discovered workspace list
/// (i.e. when config.toml does not set an explicit `workspaces` override).
///
/// Single-digit workspaces named "1".."9" sort first, in that numeric
/// order, followed by "0" -- matching a physical keyboard's number row --
/// and any other (non-numeric) workspace names are appended afterwards in
/// plain alphabetical order. This reproduces "1 2 3 4 5 6 7 8 9 0" for the
/// common case with zero configuration, while staying entirely driven by
/// whatever AeroSpace reports, so adding/removing/renaming workspaces in
/// ~/.aerospace.toml is reflected automatically.
enum WorkspaceOrdering {
    static func sorted(_ names: [String]) -> [String] {
        names.sorted { lhs, rhs in
            switch (keypadRank(lhs), keypadRank(rhs)) {
            case let (l?, r?):
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        }
    }

    /// Rank used for the keyboard-row ordering: "1"->1, ..., "9"->9, "0"->10.
    /// Returns nil for anything that isn't a single decimal digit.
    private static func keypadRank(_ name: String) -> Int? {
        guard name.count == 1, let digit = name.first, digit.isASCII, digit.isNumber else { return nil }
        let value = digit.wholeNumberValue ?? 0
        return value == 0 ? 10 : value
    }
}
