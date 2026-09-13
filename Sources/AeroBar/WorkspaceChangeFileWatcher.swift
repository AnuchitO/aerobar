import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Fast path for workspace-change detection, driven by AeroSpace's own
/// `exec-on-workspace-change` hook writing the focused workspace name into
/// a small file. This is what replaces the app's previous
/// SketchyBar-triggering line -- see README section 3 for the exact
/// ~/.aerospace.toml snippet.
///
/// The recommended config line is:
///
///   exec-on-workspace-change = ['/bin/sh', '-c',
///     'printf "%s" "$AEROSPACE_FOCUSED_WORKSPACE" > "$HOME/.config/aerospace-menubar/current-workspace"'
///   ]
///
/// Polling (WorkspaceManager's timer) keeps running underneath as a
/// fallback, so the app works correctly even before this line is added,
/// or if the watch below can't be established for any reason.
final class WorkspaceChangeFileWatcher {
    private let queue = DispatchQueue(label: "com.anuchito.AeroBar.file-watch")
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileFD: Int32 = -1
    private var directoryFD: Int32 = -1
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            self?.setUp()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.tearDown()
        }
    }

    /// Reads whatever is currently in the notification file, if present.
    /// Safe to call from any queue.
    func readCurrentValue() -> String? {
        guard let data = try? Data(contentsOf: Configuration.currentWorkspaceFileURL) else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    private func setUp() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Configuration.configDirectory, withIntermediateDirectories: true)

        watchDirectory()
        tryWatchFile()
    }

    private func tearDown() {
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    /// Watches the config directory itself so we notice when the
    /// notification file is created for the first time (e.g. the first
    /// workspace change after the app launches, or after the user adds
    /// the exec-on-workspace-change line).
    private func watchDirectory() {
        let path = Configuration.configDirectory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Log.workspace.info("Could not watch config directory for instant updates; relying on polling only")
            return
        }
        directoryFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: queue)
        source.setEventHandler { [weak self] in
            self?.onChange()
            // The notification file may have just been created -- attach
            // a direct watch on it if we don't have one yet.
            if self?.fileSource == nil {
                self?.tryWatchFile()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryFD, fd >= 0 { close(fd) }
        }
        source.resume()
        directorySource = source
    }

    /// Watches the notification file directly, for instant updates on
    /// every write once it exists.
    private func tryWatchFile() {
        let path = Configuration.currentWorkspaceFileURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return } // file doesn't exist yet; directory watch will retry us

        fileFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.onChange()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileFD, fd >= 0 { close(fd) }
        }
        source.resume()
        fileSource = source
        Log.workspace.info("Watching \(path, privacy: .public) for instant workspace-change updates")
    }
}
