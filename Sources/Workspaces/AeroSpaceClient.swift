import Foundation

/// Everything related to talking to the `aerospace` CLI.
///
/// Design notes (see README "How AeroSpace integration works" for the
/// research this is based on):
///   - AeroSpace does not currently expose a socket/IPC event stream that a
///     third-party process can subscribe to. The only event hook is the
///     `exec-on-workspace-change` config key, which runs an external
///     command on every workspace change -- but wiring that up requires
///     editing the user's ~/.aerospace.toml, which this app must never do
///     automatically. So workspace-change *detection* here uses a light
///     poll of `aerospace list-workspaces --focused` (see WorkspaceManager).
///   - Workspace *switching* and *current-workspace* queries both go
///     through the documented CLI (`aerospace workspace <name>` and
///     `aerospace list-workspaces --focused`), invoked via `Process`
///     directly against the resolved executable path -- no shell, no
///     dependency on the user's PATH.
final class AeroSpaceClient {
    enum ClientError: Error, CustomStringConvertible {
        case executableNotFound
        case processFailed(command: String, status: Int32, stderr: String)
        case launchFailed(underlying: Error)

        var description: String {
            switch self {
            case .executableNotFound:
                return "Could not locate the aerospace executable"
            case .processFailed(let command, let status, let stderr):
                return "`\(command)` exited with status \(status): \(stderr)"
            case .launchFailed(let underlying):
                return "Failed to launch aerospace process: \(underlying)"
            }
        }
    }

    /// Common install locations, checked in order, before falling back to
    /// a configured override. Homebrew on Apple Silicon and Intel are
    /// listed first since they're by far the most common installs.
    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
        "/opt/local/bin/aerospace",
        "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace",
        "/Applications/AeroSpace.app/Contents/MacOS/aerospace",
    ]

    /// Resolved path to the aerospace executable, or nil if none could be
    /// found. Re-resolved each time `resolveExecutable()` is called so a
    /// fresh install (or a config change) is picked up without a restart.
    private(set) var executablePath: String?

    private let configuredPathProvider: () -> String?

    init(configuredPathProvider: @escaping () -> String? = { Configuration.load().aerospacePath }) {
        self.configuredPathProvider = configuredPathProvider
        self.executablePath = resolveExecutable()
    }

    /// Searches for the aerospace executable: an explicit config override
    /// first, then well-known install locations, then `$HOME/.local/bin`.
    @discardableResult
    func resolveExecutable() -> String? {
        let fm = FileManager.default

        if let configured = configuredPathProvider(), fm.isExecutableFile(atPath: configured) {
            Log.client.info("Using configured aerospace path: \(configured, privacy: .public)")
            executablePath = configured
            return configured
        }

        for path in Self.candidatePaths where fm.isExecutableFile(atPath: path) {
            Log.client.info("AeroSpace executable found at \(path, privacy: .public)")
            executablePath = path
            return path
        }

        let homeLocal = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/aerospace").path
        if fm.isExecutableFile(atPath: homeLocal) {
            Log.client.info("AeroSpace executable found at \(homeLocal, privacy: .public)")
            executablePath = homeLocal
            return homeLocal
        }

        Log.client.error("AeroSpace executable not found in any known location")
        executablePath = nil
        return nil
    }

    /// Runs `aerospace <args>` directly (no shell) and returns trimmed
    /// stdout. Throws `ClientError` on a missing executable, launch
    /// failure, or non-zero exit status.
    @discardableResult
    private func run(_ args: [String]) throws -> String {
        guard let path = executablePath ?? resolveExecutable() else {
            throw ClientError.executableNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed(underlying: error)
        }
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ClientError.processFailed(
                command: "aerospace \(args.joined(separator: " "))",
                status: process.terminationStatus,
                stderr: stderr
            )
        }

        return stdout
    }

    /// Returns the name of the currently focused workspace, e.g. "1" or "0".
    func currentWorkspace() throws -> String {
        try run(["list-workspaces", "--focused"])
    }

    /// Switches AeroSpace to the given workspace. This is exactly
    /// equivalent to running `aerospace workspace <name>` in a terminal;
    /// AeroSpace itself decides which monitor the workspace appears on,
    /// per the user's existing `workspace-to-monitor-force-assignment`.
    func switchTo(workspace name: String) throws {
        try run(["workspace", name])
        Log.client.info("Switched to workspace \(name, privacy: .public)")
    }

    /// Diagnostic helper: lists all workspaces AeroSpace currently knows
    /// about (used only for a one-time startup log, not for the UI's
    /// workspace list, which comes from Configuration so empty/unassigned
    /// workspaces are never hidden).
    func listAllWorkspaces() throws -> [String] {
        let output = try run(["list-workspaces", "--all"])
        return output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// True if the aerospace process itself appears to be reachable, i.e.
    /// a basic command succeeds. Used to distinguish "not installed / not
    /// running" from a transient error.
    func isReachable() -> Bool {
        (try? currentWorkspace()) != nil
    }
}
