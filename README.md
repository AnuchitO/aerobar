# AeroBar

A tiny, native macOS menu-bar utility that replaces SketchyBar's workspace
indicator with real `NSStatusItem`s in the actual system menu bar. Buttons
for your AeroSpace workspaces, always clickable, in keyboard-row order
(`1 2 3 4 5 6 7 8 9 0`), capped to a small fixed count next to a MacBook's
camera notch.

```
 Finder  File  Edit  View  ...     7  8  [9]  0     Wi-Fi  Battery  Clock
```
(the active workspace is a small white rounded-square badge with the
digit inside, like macOS's own Input Source/language menu-bar glyph)

Built with Swift + AppKit only: no Electron, no WebKit, no SketchyBar,
no custom drawn menu bar, no Accessibility permission, **no polling
timers of any kind** -- see section 3.

## 1. What it does

- Draws one native `NSStatusItem` per workspace, directly in the system
  menu bar.
- Clicking a workspace button runs the equivalent of `aerospace workspace
  <name>`.
- Highlights the currently focused workspace with a small white
  rounded-square badge (matching macOS's own Input Source/language
  menu-bar glyph) -- kept in sync the instant it changes, whether you
  switch by clicking a button, an AeroSpace keyboard shortcut, `aerospace
  workspace ...` in a terminal, or by moving a window to another
  workspace.
- Discovers the workspace list from AeroSpace itself (no hard-coded
  list) -- add or remove a workspace in `~/.aerospace.toml` and the menu
  bar picks it up (checked at launch and on "Refresh").
- On a notched display, shows a small fixed number of buttons, centered
  on the active workspace, instead of overflowing.
- Leaves your `~/.aerospace.toml` untouched otherwise: no
  `persistent-workspaces`, no config-version changes, no rewriting of
  `[workspace-to-monitor-force-assignment]`. AeroSpace keeps handling
  monitor assignment exactly as it does today.
- Runs as a menu-bar-only app (no Dock icon, no app menu, no window).

## 2. Requirements

- macOS 13 (Ventura) or later.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) installed and
  running, with your existing configuration (workspace-to-monitor
  assignments etc.) left as-is.
- Swift toolchain (Xcode 15+, or Xcode Command Line Tools) to build.

## 3. How AeroSpace integration works (event-driven, no polling)

This app only uses AeroSpace's documented, public CLI -- see the
[AeroSpace commands reference](https://nikitabobko.github.io/AeroSpace/commands)
and [guide](https://nikitabobko.github.io/AeroSpace/guide). No private or
undocumented API is used, and there is **no timer that repeatedly runs
`aerospace` commands in the background**. Instead:

| Need                      | Mechanism used |
|----------------------------|----------------|
| Switch workspace            | `aerospace workspace <name>` (run once, on click) |
| Read the focused workspace  | `aerospace list-workspaces --focused` (run once at launch, and once per real change) |
| Discover the workspace list | `aerospace list-workspaces --all` (run once at launch, and on "Refresh") |
| Detect workspace changes    | `exec-on-workspace-change` writing to a file this app watches via a kernel file-system event |
| Detect AeroSpace start/quit | `NSWorkspace` launch/terminate notifications |

All commands are run with Foundation's `Process`, invoked directly against
a resolved absolute path to the `aerospace` binary -- never through `/bin/sh`
or the user's shell `$PATH`.

### Replacing your SketchyBar trigger (required for updates to work)

AeroSpace's only change hook is the `exec-on-workspace-change` config key,
which runs one external command on every workspace change. Since this app
does not poll, **this one-line edit to `~/.aerospace.toml` is what makes
workspace-change detection work at all** (the app never edits that file
automatically -- you make this one edit yourself). Replace your current:

```toml
exec-on-workspace-change = [
    '/bin/bash',
    '-c',
    'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE',
]
```

with:

```toml
exec-on-workspace-change = [
    '/bin/sh',
    '-c',
    'printf "%s" "$AEROSPACE_FOCUSED_WORKSPACE" > "$HOME/.config/aerospace-menubar/current-workspace"',
]
```

Then `aerospace reload-config` (or quit/relaunch AeroSpace). This writes
the focused workspace name to a small file every time it changes;
AeroBar watches that file with a kqueue file-system event (via
`DispatchSource.makeFileSystemObjectSource`) -- a passive kernel
subscription, not a loop that checks anything on a timer -- and updates
the instant it's written.

AeroSpace launching or quitting is detected the same way: via
`NSWorkspace`'s own launch/terminate notifications, not by periodically
checking whether the process is still there. On launch, the workspace
list and current workspace are read once, immediately; on quit, the menu
bar is marked unreachable immediately.

If you skip the config edit above, the app still shows an initial state
at launch (one-time read), but won't learn about later workspace changes
until you pick **Refresh** -- so it's worth doing.

## 4. How to build

```bash
git clone https://github.com/AnuchitO/aerobar.git
cd aerobar
make build
```

`make build` is a thin wrapper around `swift build -c release`, producing
a bare executable at `.build/release/AeroBar` -- useful for development
(`make dev`, i.e. `swift run`), but **not** enough on its own for Launch
at Login or a Dock-free launch from Finder -- for that you need a real
`.app` bundle:

```bash
make app
```

which runs `Scripts/build-app.sh` and produces `.build/AeroBar.app`
(ad-hoc code signed, which is required for `SMAppService`/Launch at Login
to work).

## 5. How to install

```bash
make install
```

Runs `Scripts/install.sh`, which builds the release `.app` and copies it
to `/Applications/AeroBar.app`. Run this again any time you pull changes
or rebuild. `make run` does the same and then opens the app in one step.

## 6. How to launch

```bash
make run
```

or `open /Applications/AeroBar.app`, or double-click it in Finder. It
will not appear in the Dock or the Cmd+Tab switcher (menu-bar-only app,
`LSUIElement = true`); look for the workspace numbers and a small grid
icon in the menu bar.

## 7. How to enable Launch at Login

Click the small grid icon (to the right of the workspace numbers) →
**Launch at Login**. This uses `SMAppService.mainApp` (the current,
non-deprecated API), so it requires the app to be running from
`/Applications/AeroBar.app` (or another `.app` bundle location)
rather than the bare `.build/release/AeroBar` binary.

## 8. How workspace detection works

See section 3: an instant, event-driven file watch fed by
`exec-on-workspace-change`, plus `NSWorkspace` notifications for AeroSpace
itself starting or quitting. No polling loop exists anywhere in the app.

## 9. How active-workspace detection works

Every update compares the freshly-read focused workspace against the
app's cached value. The active button is drawn as a single flattened
badge image -- a solid white, rounded-square background with the digit
sized to fill it -- deliberately mimicking macOS's own Input Source
(language) menu-bar glyph, a familiar, unmistakable "this one is
selected" look. Being one bitmap (not a text layer plus a separate
background layer) means there's no draw-order ambiguity that could let a
background paint over the digit. Every other button is plain,
regular-weight text in `NSColor.secondaryLabelColor`, with a faint hover
wash when the pointer is over it.

## 10. How to configure button size and spacing

By default, each button auto-sizes to `font-size + 10` wide, plus
`spacing` (points) added on each side -- `spacing = 0` (the default)
means no extra gap beyond that.

For full, literal control over the button's total width instead
(including the gray highlight box macOS draws on click/hold), set:

```toml
item-width = 20
```

in `~/.config/aerospace-menubar/config.toml`. This changes ONLY the
button's own footprint -- `spacing` is then ignored, and the
digit/active-workspace badge is always drawn at its normal,
font-size-driven size regardless of `item-width`, never scaled up or
down. Set it narrower than the badge needs and the badge is simply
clipped by the button's edges rather than shrunk -- a visible consequence
of that width, not a size change. Pick **Refresh** from the grid icon's
menu after changing either setting.

## 11. How to configure workspace order

By default, nothing needs configuring: the workspace list comes straight
from `aerospace list-workspaces --all` and is sorted `1..9` then `0`
(matching your keyboard row), with any non-numeric workspace names
appended alphabetically after. Add or remove a workspace in
`~/.aerospace.toml` and it shows up here (checked at launch, and
immediately via "Refresh").

If you want a fixed, manual order instead, set it explicitly in
`~/.config/aerospace-menubar/config.toml`:

```toml
workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
```

which is then used exactly as written (never re-sorted) and stops
auto-discovery.

`~/.config/aerospace-menubar/config.toml` is created automatically, with
these defaults filled in, the first time the app runs (and on every
subsequent launch, if it's ever missing) -- there's nothing to set up
before editing it. Use the grid icon's **Open Configuration** menu item
to open it in your default editor, then **Refresh** to apply changes.

## 12. How to configure the AeroSpace executable path

The app searches, in order:

1. `aerospace-path` in `~/.config/aerospace-menubar/config.toml`, if set.
2. `/opt/homebrew/bin/aerospace` (Homebrew, Apple Silicon)
3. `/usr/local/bin/aerospace` (Homebrew, Intel)
4. `/opt/local/bin/aerospace` (MacPorts)
5. `/Applications/AeroSpace.app/Contents/MacOS/AeroSpace`
6. `~/.local/bin/aerospace`

If none of these match your install, set it explicitly:

```toml
aerospace-path = "/custom/path/to/aerospace"
```

then pick **Refresh** from the grid icon's menu.

## 13. Notch-aware layout

macOS does not expose a reliable way to measure exactly how much menu-bar
space is actually free next to a notch (the closest API,
`NSScreen.auxiliaryTopRightArea`, is meant for window content layout and
doesn't account for other apps' menu-bar icons at all). Rather than guess
at pixel widths, this app uses a simple, predictable rule instead:

- **No notch** (external display, older MacBook): every workspace is
  shown.
- **Notch present** (`NSScreen.safeAreaInsets.top > 0` on the built-in
  display -- the standard, reliable way to detect one): a small fixed
  number of buttons are shown (4 by default), as a sliding window of the
  full list centered on the active workspace. For example, with
  workspaces `1..9,0`:
  - active = `9` → shows `7 8 9 0` (window clamped to the end of the list)
  - active = `5` → shows `3 4 5 6` (centered)

The window recomputes whenever the active workspace or the workspace list
changes, and whenever screen configuration changes (external display
connected/disconnected, resolution change).

To override the default count (e.g. if 4 is too many or too few for your
setup), set it explicitly in `~/.config/aerospace-menubar/config.toml`:

```toml
max-visible-workspaces = 4
```

Setting this also applies on non-notched displays, if you'd rather always
cap the count.

## 14. Troubleshooting

- **All workspace numbers are dim / nothing highlights.** AeroSpace isn't
  reachable -- either it isn't running, or the executable couldn't be
  found. Check Console.app (see below) for `AeroSpace executable not
  found` or `AeroSpace command failed` messages, and set `aerospace-path`
  if needed. The app retries automatically; it will never crash or hang
  the UI while AeroSpace is unavailable.
- **Buttons appear in the wrong left-to-right order.** See "Known macOS
  limitations" below.
- **Workspace switches from a terminal/keybinding aren't reflected.**
  Double-check the `exec-on-workspace-change` line in section 3 is in
  place and `aerospace reload-config` was run afterwards -- without it,
  the app only refreshes at launch and on manual "Refresh".
- **Too many or too few buttons on a notched display.** Set
  `max-visible-workspaces` in config.toml to the count you want.
- **Launch at Login doesn't stick.** Make sure you're running the app
  from `/Applications/AeroBar.app` (built via `Scripts/install.sh`),
  not the bare `.build` binary -- `SMAppService` requires a real,
  code-signed `.app` bundle.
- **Viewing logs:**

  ```bash
  log stream --predicate 'subsystem == "com.anuchito.AeroBar"' --level info
  ```

  Logging only happens on real state changes (a workspace switch,
  AeroSpace starting/quitting), never on a timer, so a healthy, idle run
  produces no log output at all.

## 15. Known macOS limitations

- **Status item ordering.** AppKit does not let an app pin an
  `NSStatusItem` to an exact x-position. New items are placed to the left
  of items the same process already created, which is why this app
  creates its visible buttons in reverse order to end up reading
  left-to-right correctly. Other menu-bar apps launching/quitting around
  the same time, or the user dragging items (with Cmd) in System
  Settings, can still shift the whole group left or right -- there is no
  documented, supported way around this; it's a property of
  `NSStatusBar` itself.
- **No API for "space actually free" next to the notch.** See section 13
  -- the fixed-count default is a deliberate, predictable choice instead
  of an unreliable pixel-width guess.
- **A residual gap between buttons at the automatic size.** By default
  (no `item-width` set), each button's own width is `font-size + 10`, plus
  `spacing` added on each side; on top of that, macOS itself still
  inserts a small, fixed margin between adjacent `NSStatusItem`s that no
  app can remove. Set `item-width` explicitly (section 10) for full,
  literal control instead.
- **The gray box you see on click-and-hold.** That's macOS's own
  highlight for the button being pressed, and it always fills the whole
  button -- so its size is exactly the button's width: `item-width` if
  you've set one, otherwise the automatic `font-size + 10 + spacing * 2`.
- **Multiple monitors.** `NSStatusItem`s only ever live in the menu bar of
  the *primary* display, regardless of how many monitors are connected --
  this is a hard macOS limitation, not something this app can work
  around. Actual workspace-to-monitor placement is entirely AeroSpace's
  job, driven by your existing `[workspace-to-monitor-force-assignment]`
  in `~/.aerospace.toml`; this app never touches that, and never opens
  per-display windows to compensate.

## 16. Project structure

```
AeroBar/
├── README.md
├── Makefile                  # make build / app / install / run / dev / clean
├── Package.swift
├── Resources/
│   ├── Info.plist            # LSUIElement, bundle id, etc. for the .app
│   └── config.example.toml
├── Scripts/
│   ├── build-app.sh          # swift build + assemble + codesign .app
│   └── install.sh            # build-app.sh + copy to /Applications
└── Sources/AeroBar/
    ├── main.swift                    # NSApplication bootstrap
    ├── AppDelegate.swift             # wires everything together, accessory policy
    ├── AeroSpaceClient.swift         # Process-based CLI wrapper (no shell, no PATH dependency)
    ├── WorkspaceManager.swift        # discovery, event-driven state, switch requests
    ├── WorkspaceOrdering.swift       # keyboard-row sort for auto-discovered workspaces
    ├── WorkspaceChangeFileWatcher.swift # instant updates via exec-on-workspace-change
    ├── NotchLayout.swift             # notch detection + which slice of workspaces to show
    ├── WorkspaceStatusItem.swift     # NSStatusItem creation/styling + menu
    ├── LoginItemManager.swift        # SMAppService wrapper
    ├── Configuration.swift           # config.toml loading + tiny TOML subset parser
    └── Logging.swift                 # os.Logger definitions
```

## 17. Uninstall / go back to SketchyBar

```bash
make uninstall   # or: rm -rf /Applications/AeroBar.app
rm -rf ~/.config/aerospace-menubar
```

and change `exec-on-workspace-change` back in `~/.aerospace.toml`.
Nothing else there was ever modified.
