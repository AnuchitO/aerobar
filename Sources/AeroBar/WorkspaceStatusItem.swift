import AppKit

/// Retains a workspace name alongside the NSStatusItem's click target,
/// since NSStatusBarButton's action carries no context of its own. Also
/// drives a subtle hover highlight so inactive buttons still read as
/// clickable.
private final class WorkspaceButtonHandler: NSObject {
    let name: String
    private let onClick: (String) -> Void
    private weak var button: NSStatusBarButton?
    private var trackingArea: NSTrackingArea?
    fileprivate var isHovering = false

    private let onHoverChange: () -> Void

    init(name: String, button: NSStatusBarButton, onClick: @escaping (String) -> Void, onHoverChange: @escaping () -> Void) {
        self.name = name
        self.button = button
        self.onClick = onClick
        self.onHoverChange = onHoverChange
        super.init()
        installTracking(on: button)
    }

    private func installTracking(on button: NSStatusBarButton) {
        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(area)
        trackingArea = area
    }

    @objc func handleClick() {
        onClick(name)
    }

    func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChange()
    }

    func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChange()
    }
}

/// Builds and maintains one native NSStatusItem per AeroSpace workspace,
/// directly in the system menu bar -- not a dropdown, not a custom window.
/// Each item is independently clickable and switches AeroSpace to that
/// workspace. A separate, small status item provides the optional
/// Refresh / Open Configuration / Launch at Login / Quit menu.
///
/// Layout: on a notched MacBook display, only a small fixed number of
/// buttons are shown, as a contiguous window of the full workspace list
/// centered on whichever one is active (see NotchLayout).
/// Styling: the active workspace gets a solid white rounded-square badge
/// with the character sized to fill it, matching macOS's own Input
/// Source (language) menu-bar glyph; everything else is plain
/// secondary-label text.
final class WorkspaceStatusBarController {
    private var workspaceItems: [NSStatusItem] = []
    private var itemNames: [String] = []
    private var handlers: [WorkspaceButtonHandler] = []
    private var menuItem: NSStatusItem?
    private var configuration: Configuration
    private var allWorkspaces: [String] = []
    private var currentWorkspace: String?
    private var isReachable = false
    private let onSelect: (String) -> Void
    private let onRefresh: () -> Void
    private let loginItemManager: LoginItemManager

    /// Comfortable padding the active-workspace badge wants around its
    /// digit at the *auto-sized* default -- used only when
    /// `fixedItemWidth` isn't set. Once you set an explicit width, this
    /// plays no part at all.
    private static let defaultBadgePadding: CGFloat = 10

    /// Natural (auto-sized) visual size of the digit/badge: font-size
    /// plus the default padding above.
    private var naturalBadgeDiameter: CGFloat {
        CGFloat(configuration.fontSize) + Self.defaultBadgePadding
    }

    /// Total button width. If `fixedItemWidth` is set in config.toml,
    /// that's used exactly as given -- full, literal control, including
    /// the gray box macOS draws on click/hold, which always fills the
    /// whole button. Otherwise, width is computed automatically:
    /// `naturalBadgeDiameter` plus `spacing` added on each side.
    private var itemWidth: CGFloat {
        if let fixed = configuration.fixedItemWidth {
            return CGFloat(fixed)
        }
        return naturalBadgeDiameter + CGFloat(configuration.spacing) * 2
    }

    /// Size the active-workspace badge is actually drawn at: always
    /// exactly `naturalBadgeDiameter`, i.e. driven by font-size alone.
    /// `item-width`/`spacing` change ONLY the button's own footprint
    /// (`itemWidth`), never this -- so the badge (and font size) can
    /// never be shrunk by either setting. If `item-width` is set narrower
    /// than the badge needs, the badge is drawn at full size and simply
    /// clipped by the button's edges rather than scaled down (see
    /// `button.imageScaling = .scaleNone` where this is used) -- a
    /// visible consequence of that choice, not a size change.
    private var badgeDrawSize: CGFloat {
        naturalBadgeDiameter
    }

    init(configuration: Configuration, loginItemManager: LoginItemManager, onSelect: @escaping (String) -> Void, onRefresh: @escaping () -> Void) {
        self.configuration = configuration
        self.loginItemManager = loginItemManager
        self.onSelect = onSelect
        self.onRefresh = onRefresh
    }

    /// Creates the status items and the menu item. Call once at launch.
    func build() {
        buildMenuItemIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Applies a full new state: workspace list, focused workspace, and
    /// reachability. Rebuilds the button set only when the *visible*
    /// window actually needs to change, so normal focus switches just
    /// restyle existing buttons.
    func update(workspaces: [String], currentWorkspace: String?, reachable: Bool) {
        self.allWorkspaces = workspaces
        self.currentWorkspace = currentWorkspace
        self.isReachable = reachable
        rebuildIfNeeded()
        applyStyles()
    }

    /// Re-reads configuration (e.g. after "Refresh") and rebuilds.
    func applyConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
        rebuildIfNeeded(force: true)
        applyStyles()
    }

    @objc private func screenParametersChanged() {
        rebuildIfNeeded(force: true)
        applyStyles()
    }

    private var visibleNames: [String] = []

    private func rebuildIfNeeded(force: Bool = false) {
        let activeIndex = currentWorkspace.flatMap { allWorkspaces.firstIndex(of: $0) }
        let count = NotchLayout.visibleCount(
            configuredMax: configuration.maxVisibleWorkspaces,
            totalCount: allWorkspaces.count
        )
        let range = NotchLayout.window(totalCount: allWorkspaces.count, activeIndex: activeIndex, count: count)
        let newVisible = allWorkspaces.isEmpty ? [] : Array(allWorkspaces[range])

        guard force || newVisible != visibleNames else { return }
        visibleNames = newVisible

        for item in workspaceItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        workspaceItems.removeAll()
        itemNames.removeAll()
        handlers.removeAll()

        // NSStatusBar places each newly created item to the LEFT of items
        // created earlier in the same launch. Creating the visible slice
        // in reverse keeps it reading left-to-right in list order -- see
        // README "Known macOS limitations".
        for name in newVisible.reversed() {
            let item = NSStatusBar.system.statusItem(withLength: itemWidth)
            guard let button = item.button else { continue }

            button.wantsLayer = true
            let handler = WorkspaceButtonHandler(name: name, button: button, onClick: { [weak self] name in
                self?.onSelect(name)
            }, onHoverChange: { [weak self] in
                self?.applyStyles()
            })
            handlers.append(handler)

            button.target = handler
            button.action = #selector(WorkspaceButtonHandler.handleClick)
            button.setButtonType(.momentaryChange)

            workspaceItems.append(item)
            itemNames.append(name)
        }
    }

    /// Redraws each visible button's text or badge to reflect current state.
    private func applyStyles() {
        for (item, name) in zip(workspaceItems, itemNames) {
            guard let button = item.button else { continue }
            style(button: button, name: name)
        }
    }

    private func style(button: NSStatusBarButton, name: String) {
        let isActive = isReachable && name == currentWorkspace
        let handler = handlers.first { $0.name == name }
        let isHovering = handler?.isHovering ?? false

        button.toolTip = isReachable
            ? "Switch to AeroSpace workspace \(name)"
            : "AeroSpace is not reachable"

        if isActive {
            // Mimics macOS's own Input Source (language) menu-bar glyph:
            // a solid white, rounded-square badge with the character
            // drawn to fill it. Rendered as one flattened image (not a
            // text layer plus a separate background layer), so there is
            // no draw-order ambiguity that could let a background paint
            // over the text -- what you see is exactly the one bitmap.
            let side = min(button.bounds.height - 4, badgeDrawSize)
            button.image = badgeImage(for: name, side: max(12, side))
            button.imagePosition = .imageOnly
            // .scaleNone: draw the badge at its true size always, even if
            // the button (item-width) is narrower than it -- AppKit's
            // default scaling would otherwise shrink the image to fit,
            // which is exactly the unwanted coupling this avoids.
            button.imageScaling = .scaleNone
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.image = nil
            button.imagePosition = .noImage
            let font = NSFont.monospacedDigitSystemFont(ofSize: configuration.fontSize, weight: .regular)
            let textColor: NSColor = isReachable ? .secondaryLabelColor : .tertiaryLabelColor
            button.attributedTitle = NSAttributedString(
                string: name,
                attributes: [.font: font, .foregroundColor: textColor]
            )
        }

        // Hover feedback for inactive buttons only: a faint, translucent
        // wash so it's clear they're clickable, never opaque enough to
        // compete with the text.
        let hover = hoverLayer(for: button)
        hover.frame = button.bounds.insetBy(dx: 2, dy: 3)
        hover.cornerRadius = 4
        hover.backgroundColor = (!isActive && isHovering)
            ? NSColor.labelColor.withAlphaComponent(0.07).cgColor
            : NSColor.clear.cgColor
    }

    private func hoverLayer(for button: NSStatusBarButton) -> CALayer {
        let name = "aerobar.hover"
        if let existing = button.layer?.sublayers?.first(where: { $0.name == name }) {
            return existing
        }
        let layer = CALayer()
        layer.name = name
        button.layer?.addSublayer(layer)
        return layer
    }

    /// Draws a single flattened badge image: a white rounded-square with
    /// `text` centered and sized to fill it, matching the look of macOS's
    /// own Input Source glyph icons. `isTemplate` is left false so it
    /// renders in true white/black rather than being tinted/vibrancy-
    /// adjusted like a template icon.
    private func badgeImage(for text: String, side: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            NSColor.white.setFill()
            path.fill()

            let font = NSFont.monospacedDigitSystemFont(ofSize: rect.height * 0.62, weight: .bold)
            let string = NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: NSColor.black]
            )
            let stringSize = string.size()
            let origin = NSPoint(
                x: (rect.width - stringSize.width) / 2,
                y: (rect.height - stringSize.height) / 2
            )
            string.draw(at: origin)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func buildMenuItemIfNeeded() {
        guard menuItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "AeroSpace Menu Bar")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshTapped), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Configuration", action: #selector(openConfigTapped), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit AeroBar", action: #selector(quitTapped), keyEquivalent: "q").target = self

        item.menu = menu
        menuItem = item
    }

    @objc private func refreshTapped() {
        Log.ui.info("User requested manual refresh")
        onRefresh()
    }

    @objc private func openConfigTapped() {
        Configuration.ensureConfigFileExists()
        NSWorkspace.shared.open(Configuration.configFileURL)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if loginItemManager.isEnabled {
                try loginItemManager.disable()
                sender.state = .off
            } else {
                try loginItemManager.enable()
                sender.state = .on
            }
        } catch {
            Log.login.error("Failed to toggle Launch at Login: \(String(describing: error), privacy: .public)")
        }
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}
