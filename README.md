# Workspaces Per Monitor

An [Omarchy](https://omarchy.org/) bar widget: each monitor's bar shows
only that monitor's workspaces, and hovering a number previews the windows
inside it.

`omarchy.workspaces` paints the full workspace list on every bar, so with
two monitors each bar fills up with numbers you will never click from that
screen. This widget shows only the monitor's own workspaces, numbered the
way Omarchy numbers them, and keeps the useful part: click to switch, hover
to see what lives there.

## Features

- **Per-monitor blocks.** Each monitor shows its own block of workspaces,
  labelled 1–10 as Omarchy labels them (the block comes from Omarchy's
  `monitor-workspaces` state file). The first five always show, dimmed when
  empty; workspaces of an unplugged monitor show after them, set apart by a gap.
- **Hover preview.** A popover lists one row per window — app icon and
  title. Clicking a row focuses that exact window and maximizes it while
  keeping the bar visible (not Hyprland's `realfullscreen`, which hides
  the menus).
- **Quiet by default.** Empty workspaces stay dimmed. The number is always
  visible; its mark shows the workspace's layout: tiling underlines the
  focused workspace, scrolling gets a dot, floating gets a box. Clicking the
  active number cycles the layout. Workspace 10 shows as `0`.

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

The widget has no settings: which workspaces a monitor shows comes from
Omarchy's per-monitor blocks.

## Interactions

| Input                     | Action                                    |
| ------------------------- | ----------------------------------------- |
| Click a number            | Switch to that workspace                  |
| Click the active number   | Cycle the workspace's layout              |
| Hover a number            | Preview its windows                       |
| Click a row               | Focus that window and maximize it         |

## Dependencies

Omarchy with the Quickshell bar (`omarchy-shell`) running Hyprland. No
extra packages: window and monitor data come from Quickshell's own
`Quickshell.Hyprland` API, icons from the installed desktop entries.

## How it works

`WorkspacesPerMonitor.qml` is the widget: it resolves the Hyprland monitor
owning its bar surface, reads its workspace block from Omarchy's state file,
and drives the hover popover. `WorkspaceModel.js` builds the
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
