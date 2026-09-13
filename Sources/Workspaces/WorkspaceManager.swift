import AppKit

/// Owns the app's view of AeroSpace state: the (dynamically discovered)
/// workspace list, which one is currently focused, and whether AeroSpace
/// itself is reachable.
///
/// Deliberately has no timer-based polling of any kind. State changes are
/// driven entirely by real events:
///   - WorkspaceChangeFileWatcher, fed by the user's own
///     exec-on-workspace-change hook, for instant focus updates.
///   - NSWorkspace launch/terminate notifications for AeroSpace itself, so
///     "AeroSpace isn't running" / "AeroSpace just started" is detected
///     the moment it happens, not on the next tick of a timer.
///   - One explicit read at startup (so the UI isn't blank on launch) and
///     whenever the user picks "Refresh".
final class WorkspaceManager {
    /// Ordered list of workspaces to display. When Configuration.workspaces
    /// is set, this is exactly that list, unchanged. Otherwise it is
    /// discovered from `aerospace list-workspaces --all` and sorted by
    /// WorkspaceOrdering, so adding/removing workspaces in
    /// ~/.aerospace.toml is picked up automatically -- nothing is
    /// hard-coded.
    private(set) var workspaces: [String] = []

    /// Name of the currently focused workspace, or nil if unknown (e.g.
    /// AeroSpace isn't running yet).
    private(set) var currentWorkspace: String?

    /// Whether the last attempt to talk to AeroSpace succeeded.
    private(set) var isAeroSpaceReachable: Bool = false

    /// Called on the main thread whenever workspaces, currentWorkspace, or
    /// isAeroSpaceReachable changes.
    var onStateChange: (() -> Void)?

    private let client: AeroSpaceClient
    private var configuration: Configuration
    private var fileWatcher: WorkspaceChangeFileWatcher?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private let workQueue = DispatchQueue(label: "com.anuchito.Workspaces.workspace-events")

    init(configuration: Configuration, client: AeroSpaceClient = AeroSpaceClient()) {
        self.configuration = configuration
        self.client = client
    }

    func start() {
        Log.workspace.info("Starting workspace manager (event-driven; no polling)")

        // One explicit read so the UI isn't blank on launch. Off the main
        // thread, so a slow/hung aerospace process can never block launch.
        workQueue.async { [weak self] in
            self?.refreshList()
            self?.refreshFocus()
        }

        let watcher = WorkspaceChangeFileWatcher { [weak self] in
            self?.workQueue.async { self?.refreshFocus() }
        }
        watcher.start()
        self.fileWatcher = watcher

        observeAeroSpaceLifecycle()
    }

    func stop() {
        fileWatcher?.stop(); fileWatcher = nil
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        if let terminateObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver) }
        launchObserver = nil
        terminateObserver = nil
    }

    /// Reloads static configuration (e.g. after the user edits
    /// config.toml and chooses "Refresh"), then re-derives the workspace
    /// list and current state immediately.
    func reloadConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
        client.resolveExecutable()
        refreshNow()
    }

    /// Re-reads both the workspace list and the focused workspace right
    /// now. Used by the "Refresh" menu item -- an explicit, user-initiated
    /// action, not a recurring timer.
    func refreshNow() {
        workQueue.async { [weak self] in
            self?.refreshList()
            self?.refreshFocus()
        }
    }

    /// Switches to the given workspace. Updates local state optimistically
    /// for a snappy UI, then confirms with AeroSpace shortly after.
    func select(workspace name: String) {
        Log.workspace.info("Switching to workspace \(name, privacy: .public)")
        currentWorkspace = name
        publishStateChange()

        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.client.switchTo(workspace: name)
            } catch {
                Log.workspace.error("AeroSpace command failed: \(String(describing: error), privacy: .public)")
            }
            self.refreshFocus()
        }
    }

    /// Watches for AeroSpace launching or quitting via NSWorkspace's
    /// notifications -- an event-driven substitute for polling "is
    /// AeroSpace still there?". On launch, re-reads everything right away;
    /// on termination, immediately marks the app unreachable.
    private func observeAeroSpaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard self?.isAeroSpace(notification) == true else { return }
            Log.workspace.info("AeroSpace launched")
            self?.refreshNow()
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard self?.isAeroSpace(notification) == true else { return }
            Log.workspace.info("AeroSpace quit")
            self?.workQueue.async {
                guard let self else { return }
                let wasReachable = self.isAeroSpaceReachable
                self.isAeroSpaceReachable = false
                if wasReachable { self.publishStateChange() }
            }
        }
    }

    private func isAeroSpace(_ notification: Notification) -> Bool {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        if let bundleID = app.bundleIdentifier, bundleID.localizedCaseInsensitiveContains("aerospace") {
            return true
        }
        return app.localizedName?.localizedCaseInsensitiveContains("aerospace") ?? false
    }

    /// Queries AeroSpace for the full workspace list and, unless the user
    /// pinned an explicit order in config.toml, re-derives display order
    /// from it. Runs on workQueue.
    private func refreshList() {
        if let fixed = configuration.workspaces {
            if fixed != workspaces {
                workspaces = fixed
                publishStateChange()
            }
            return
        }

        do {
            let discovered = try client.listAllWorkspaces()
            let ordered = WorkspaceOrdering.sorted(discovered)
            if ordered != workspaces {
                let list = ordered.joined(separator: ", ")
                Log.workspace.info("Detected workspaces: \(list, privacy: .public)")
                workspaces = ordered
                publishStateChange()
            }
        } catch {
            // Don't clear the existing list on a transient failure --
            // keep showing the last known-good set of buttons.
            Log.workspace.error("Could not list workspaces: \(String(describing: error), privacy: .public)")
        }
    }

    /// Queries AeroSpace for the focused workspace and updates state if it
    /// changed. This is the handler for the instant file-watch path, so it
    /// always re-reads from AeroSpace itself rather than trusting the
    /// notification file's content blindly.
    private func refreshFocus() {
        do {
            let focused = try client.currentWorkspace()
            let wasReachable = isAeroSpaceReachable
            let changed = focused != currentWorkspace
            currentWorkspace = focused
            isAeroSpaceReachable = true

            if changed {
                Log.workspace.info("Workspace update received: now on \(focused, privacy: .public)")
            }
            if !wasReachable {
                Log.workspace.info("AeroSpace is reachable")
            }
            if changed || !wasReachable {
                publishStateChange()
            }
        } catch {
            let wasReachable = isAeroSpaceReachable
            isAeroSpaceReachable = false
            if wasReachable {
                Log.workspace.error("Lost connection to AeroSpace: \(String(describing: error), privacy: .public)")
                publishStateChange()
            }
        }
    }

    private func publishStateChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?()
        }
    }
}
