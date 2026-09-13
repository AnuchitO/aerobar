import Foundation
import ServiceManagement

/// Wraps SMAppService (macOS 13+) for "Launch at Login" support. This is
/// the modern, non-deprecated API for registering an app as a login item;
/// it requires the app to be running from a proper .app bundle (see
/// Scripts/build-app.sh), which is why this project's build/install
/// process always produces Workspaces.app rather than a bare binary.
final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() throws {
        guard SMAppService.mainApp.status != .enabled else { return }
        try SMAppService.mainApp.register()
        Log.login.info("Launch at Login enabled")
    }

    func disable() throws {
        guard SMAppService.mainApp.status == .enabled else { return }
        try SMAppService.mainApp.unregister()
        Log.login.info("Launch at Login disabled")
    }
}
