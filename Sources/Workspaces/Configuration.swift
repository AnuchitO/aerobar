import Foundation

/// App configuration, loaded from ~/.config/aerospace-menubar/config.toml.
///
/// The parser below only understands the small subset of TOML this app
/// needs (top-level `key = value` pairs, where value is a string, a bool,
/// a number, or an array of strings). This avoids pulling in a third-party
/// TOML dependency for a handful of settings, which keeps the app tiny and
/// dependency-free. If the file is missing or a key is absent, sensible
/// defaults are used and nothing is written back to disk.
struct Configuration {
    /// Explicit workspace order override. When nil (the default), the
    /// workspace list is discovered dynamically from `aerospace
    /// list-workspaces --all` and sorted with `WorkspaceOrdering`, so it
    /// automatically follows whatever workspaces exist in
    /// ~/.aerospace.toml -- nothing is hard-coded. Set this only if you
    /// want a fixed, manual order instead.
    var workspaces: [String]?

    /// Explicit path to the `aerospace` CLI executable. When nil, the app
    /// searches common install locations (see AeroSpaceClient).
    var aerospacePath: String?

    /// Font size (points) used for each workspace status item's title.
    var fontSize: Double = 13

    /// Extra horizontal padding (points) added on each side of every
    /// workspace button, widening the button itself -- NSStatusItem has
    /// no separate "gap" API, so this is how visual spacing between
    /// adjacent buttons is controlled. Only applies when `fixedItemWidth` is
    /// nil (auto-sized buttons); ignored once you set an explicit width.
    /// Default 0 makes each button fit its content only, matching how a
    /// native menu-bar item (e.g. the Input Source/language indicator)
    /// has no extra padding around it.
    var spacing: Double = 0

    /// Explicit total width (points) for every workspace button --
    /// including the gray box macOS draws on click/hold, which always
    /// fills the whole button. When nil (the default), width is computed
    /// automatically from font-size (see WorkspaceStatusBarController).
    /// Changes ONLY the button's own footprint -- the digit/badge itself
    /// is always drawn at its font-size-driven natural size regardless of
    /// this value, never scaled up or down. Set it narrower than that
    /// natural size and the badge is simply clipped by the button's
    /// edges rather than shrunk.
    var fixedItemWidth: Double?

    /// Fixed number of workspace buttons to show. When nil (the default),
    /// the app shows every workspace on a display without a notch, or a
    /// small fixed count (NotchLayout.defaultNotchVisibleCount) on a
    /// notched MacBook display. Set this to override either default.
    var maxVisibleWorkspaces: Int?

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("aerospace-menubar", isDirectory: true)
    }

    static var configFileURL: URL {
        configDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    /// File that `exec-on-workspace-change` (optionally) writes the
    /// currently-focused workspace name into, for instant updates. See
    /// README section 3.
    static var currentWorkspaceFileURL: URL {
        configDirectory.appendingPathComponent("current-workspace", isDirectory: false)
    }

    /// Contents written out for a fresh config.toml -- both when the app
    /// notices none exists (see `load()`) and when the user picks "Open
    /// Configuration". Kept in one place so both paths always agree.
    static let defaultTemplateContents = """
        # Workspaces configuration.
        # Leave `workspaces` unset to auto-discover from AeroSpace itself.
        # workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        font-size = 13
        spacing = 0
        # item-width = 22
        # max-visible-workspaces = 4
        # aerospace-path = "/opt/homebrew/bin/aerospace"
        """

    /// Creates config.toml with the default template if it doesn't exist
    /// yet. Safe to call every launch -- a no-op once the file is there,
    /// and best-effort (never throws) so a permissions problem can't
    /// prevent the app from starting.
    @discardableResult
    static func ensureConfigFileExists() -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configFileURL.path) else { return false }
        do {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            try defaultTemplateContents.write(to: configFileURL, atomically: true, encoding: .utf8)
            Log.config.info("Created default config at \(configFileURL.path, privacy: .public)")
            return true
        } catch {
            Log.config.error("Could not create default config: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Loads configuration from disk, falling back to defaults for any
    /// missing or malformed values. Never throws: a bad config file should
    /// never prevent the menu bar from working.
    static func load() -> Configuration {
        var config = Configuration()
        ensureConfigFileExists()
        let url = configFileURL

        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            Log.config.info("No config file found at \(url.path, privacy: .public); using defaults")
            return config
        }

        let values = MiniTOML.parse(data)

        if let ws = values.stringArray("workspaces"), !ws.isEmpty {
            config.workspaces = ws
        }
        if let path = values.string("aerospace-path"), !path.isEmpty {
            config.aerospacePath = path
        }
        if let size = values.double("font-size") {
            config.fontSize = size
        }
        if let spacing = values.double("spacing") {
            config.spacing = spacing
        }
        if let width = values.double("item-width") {
            config.fixedItemWidth = max(1, width)
        }
        if let maxVisible = values.double("max-visible-workspaces") {
            config.maxVisibleWorkspaces = max(1, Int(maxVisible))
        }

        Log.config.info("Loaded config from \(url.path, privacy: .public)")
        return config
    }
}

/// A tiny, dependency-free parser for the subset of TOML this app uses:
/// top-level `key = "string"`, `key = 123`, `key = true`, and
/// `key = ["a", "b", "c"]`. Comments start with `#`. Nested tables and
/// multi-line arrays are intentionally not supported to keep this small.
enum MiniTOML {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let eqRange = line.range(of: "=") else { continue }
            let key = line[line.startIndex..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    private static func stripComment(_ line: String) -> String {
        var insideQuotes = false
        for (index, char) in line.enumerated() {
            if char == "\"" { insideQuotes.toggle() }
            if char == "#" && !insideQuotes {
                return String(line.prefix(index))
            }
        }
        return line
    }
}

private extension Dictionary where Key == String, Value == String {
    func string(_ key: String) -> String? {
        guard var raw = self[key] else { return nil }
        raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    func double(_ key: String) -> Double? {
        guard let raw = self[key] else { return nil }
        return Double(raw.trimmingCharacters(in: .whitespaces))
    }

    func stringArray(_ key: String) -> [String]? {
        guard var raw = self[key] else { return nil }
        raw = raw.trimmingCharacters(in: .whitespaces)
        guard raw.hasPrefix("[") && raw.hasSuffix("]") else { return nil }
        let inner = raw.dropFirst().dropLast()
        guard !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return inner.split(separator: ",").map { item in
            var trimmed = item.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
            return trimmed
        }
    }
}
