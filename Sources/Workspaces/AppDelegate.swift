import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: WorkspaceStatusBarController!
    private var workspaceManager: WorkspaceManager!
    private let loginItemManager = LoginItemManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no app menu, no main window.
        // This is the runtime equivalent of LSUIElement = true; it is set
        // here (rather than relying solely on Info.plist) so the behavior
        // is correct even if the app is ever run outside its .app bundle
        // (e.g. `swift run` during development).
        NSApp.setActivationPolicy(.accessory)

        let configuration = Configuration.load()
        Log.app.info("Workspaces launching")

        let manager = WorkspaceManager(configuration: configuration)
        self.workspaceManager = manager

        let controller = WorkspaceStatusBarController(
            configuration: configuration,
            loginItemManager: loginItemManager,
            onSelect: { [weak manager] name in
                manager?.select(workspace: name)
            },
            onRefresh: { [weak self] in
                self?.reload()
            }
        )
        controller.build()
        self.statusBarController = controller

        manager.onStateChange = { [weak self] in
            guard let self else { return }
            self.statusBarController.update(
                workspaces: self.workspaceManager.workspaces,
                currentWorkspace: self.workspaceManager.currentWorkspace,
                reachable: self.workspaceManager.isAeroSpaceReachable
            )
        }
        manager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceManager?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Re-reads config.toml, applies any layout-affecting changes (font
    /// size, max visible count, etc.), and re-derives the workspace list
    /// and current state. Triggered by the "Refresh" menu item.
    private func reload() {
        let configuration = Configuration.load()
        statusBarController.applyConfiguration(configuration)
        workspaceManager.reloadConfiguration(configuration)
    }
}
