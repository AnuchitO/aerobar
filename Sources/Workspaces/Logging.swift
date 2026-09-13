import os

/// Centralized loggers for the app, grouped by subsystem area.
/// Uses Apple's unified logging system (os.Logger) so output is visible in
/// Console.app and via `log stream --predicate 'subsystem == "..."'`.
enum Log {
    private static let subsystem = "com.anuchito.Workspaces"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let client = Logger(subsystem: subsystem, category: "aerospace-client")
    static let workspace = Logger(subsystem: subsystem, category: "workspace-manager")
    static let ui = Logger(subsystem: subsystem, category: "status-item")
    static let config = Logger(subsystem: subsystem, category: "configuration")
    static let login = Logger(subsystem: subsystem, category: "login-item")
}
