# Workspaces Per Monitor

An [Omarchy](https://omarchy.org/) bar widget: each monitor's bar shows
only that monitor's workspaces, and hovering a number previews the windows
inside it.

`omarchy.workspaces` paints the full workspace list on every bar, so with
two monitors each bar fills up with numbers you will never click from that
screen. This widget filters the list by the monitor the bar surface is
mapped to, and keeps the useful part: click to switch, hover to see what
lives there.

## Features

- **Per-monitor filtering.** Workspaces follow their monitor: if workspace
  4 moves onto the eDP-1 screen, eDP-1's bar grows to show it and DP-1's
  bar drops it. An id *pinned* to a monitor (see `ranges`) never leaves it.
- **Hover preview.** A popover lists one row per window — app icon and
  title. Clicking a row focuses that exact window and maximizes it while
  keeping the bar visible (not Hyprland's `realfullscreen`, which hides
  the menus).
- **Quiet by default.** Empty workspaces stay dimmed; the focused one gets
  an accent mark that adapts to the bar's edge. Workspace 10 shows as `0`.
- **Per-monitor pinning (optional).** Lock specific workspace ids to
  specific monitors with the `ranges` setting.

## Install

```bash
omarchy plugin add https://github.com/santiagoei/omarchy-workspaces-per-monitor.git --enable
```

The widget joins the bar's center section. If `omarchy.workspaces` is
still on your bar, turn it off — the two replace each other:

```bash
omarchy plugin disable omarchy.workspaces
```

Or, if you keep it in your dotfiles, symlink the checkout into the plugins
directory and rescan:

```bash
ln -sfn ~/Projects/omarchy/omarchy-workspaces-per-monitor \
  ~/.config/omarchy/plugins/ei.workspaces-per-monitor
omarchy-shell shell rescanPlugins
omarchy plugin enable ei.workspaces-per-monitor center
```

## Configuration

All settings live in the widget's entry in `~/.config/omarchy/shell.json`
and are editable from the bar's widget settings UI:

| Key     | Default | What it does                                              |
| ------- | ------- | --------------------------------------------------------- |
| `ranges`| —       | Object mapping a monitor (name or Hyprland id) to the workspace ids it should always display. |

```json
{ "id": "ei.workspaces-per-monitor",
  "ranges": { "eDP-1": [1], "DP-1": [2, 3, 4, 5] } }
```

Keys accept monitor names (`eDP-1`) or Hyprland monitor ids. Workspaces
that Hyprland reports on a monitor but that fall outside its configured
range are still shown; a configured id follows its workspace to another
monitor, except that a pinned id never *leaves* its monitor.

## Interactions

| Input            | Action                                    |
| ---------------- | ----------------------------------------- |
| Click a number   | Switch to that workspace                  |
| Hover a number   | Preview its windows                       |
| Click a row      | Focus that window and maximize it         |

## Dependencies

Omarchy with the Quickshell bar (`omarchy-shell`) running Hyprland. No
extra packages: window and monitor data come from Quickshell's own
`Quickshell.Hyprland` API, icons from the installed desktop entries.

## How it works

`WorkspacesPerMonitor.qml` is the widget: it resolves the Hyprland monitor
owning its bar surface, derives the visible id set (live workspaces plus
pinned ones), and drives the hover popover. `WorkspaceModel.js` builds the
per-workspace window records, `WorkspacePopover.qml` and `AppIcon.qml`
render the preview.

## Credits

- The window-record and hover/popover machinery — and the vendored
  `WorkspaceModel.js`, `AppIcon.qml` and `WorkspacePopover.qml` — are
  adapted from [JacobsenNando/workspace-lens](https://github.com/JacobsenNando/workspace-lens)
  (MIT, Copyright (c) 2026 JacobsenNando).
- It replaces the first-party `omarchy.workspaces` widget of
  [Omarchy](https://github.com/basecamp/omarchy) (MIT); the per-monitor
  filtering, pinning and window-focus behavior are this plugin's own.

## License

[MIT](./LICENSE).
