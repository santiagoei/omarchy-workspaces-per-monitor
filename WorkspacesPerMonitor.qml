import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WorkspaceModel.js" as WorkspaceModel

// Drop-in replacement for omarchy.workspaces that filters the numbers by the
// monitor this bar instance lives on: each monitor's bar shows only its own
// workspaces. Optional `ranges` setting in the shell.json layout entry pins
// which ids a monitor displays, e.g.
//   { "id": "ei.workspaces-per-monitor",
//     "ranges": { "eDP-1": [1], "DP-1": [2, 3, 4, 5] } }
// Keys accept monitor names or Hyprland monitor ids. Workspaces that Hyprland
// reports on this monitor but that fall outside the configured range are
// still shown, and a configured id follows its workspace to another monitor:
// if workspace 4 moves onto the eDP-1 monitor, eDP-1's bar grows to show it
// and DP-1's bar drops it. An empty pinned id never leaves its monitor.
//
// Hovering a workspace number opens a popover previewing the windows it holds:
// one row per window, with the app icon and title. Clicking a row focuses that
// exact window and maximizes it while keeping the bar visible (not the Hyprland
// real-fullscreen that hides the menus). The record/hover/popover machinery is
// adapted from jacobsennando.workspace-lens (MIT, Copyright (c) 2026
// JacobsenNando). Empty workspaces stay silent.
BarWidget {
  id: root
  moduleName: "ei.workspaces-per-monitor"

  // ------------------------------------------------------- hover preview
  property int refreshSerial: 0
  // appId -> { name, iconName }. Desktop-entry lookups are the expensive part
  // of a refresh and only change with the application list. The icon *path*
  // is resolved on every refresh so the shell's icon index stays reactive.
  property var metadataCache: Object.create(null)
  property Item pendingAnchor: null
  property var pendingRecord: null
  property Item activeAnchor: null
  property var activeRecord: null
  // Last shown anchor/record, kept while the popover fades out.
  property Item fadingAnchor: null
  property var fadingRecord: null

  // The Hyprland monitor owning the screen this bar surface is mapped to.
  // Reading focusedMonitor registers the dependency the method call alone
  // would not.
  readonly property var monitor: {
    Hyprland.focusedMonitor
    var window = root.QsWindow.window
    return window && window.screen ? Hyprland.monitorFor(window.screen) : null
  }

  function configuredIds() {
    var ranges = root.setting("ranges", null)
    if (!ranges || typeof ranges !== "object") return null
    if (!root.monitor) return null

    var list = ranges[String(root.monitor.name || "")]
    if (list === undefined) list = ranges[String(root.monitor.id)]
    // Nested shell.json arrays arrive as QVariantList, not a JS Array, so
    // Array.isArray would reject them. Index access and length still work.
    if (!list || list.length === undefined) return null

    var ids = []
    for (var i = 0; i < list.length; i++) {
      var id = Math.round(Number(list[i]))
      if (Number.isFinite(id) && id > 0 && id <= 99 && ids.indexOf(id) === -1) ids.push(id)
    }

    return ids
  }

  function liveIds() {
    if (!root.monitor) return []

    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0 || ws.id > 99) continue
      if (!ws.monitor || ws.monitor.id !== root.monitor.id) continue
      if (ids.indexOf(ws.id) === -1) ids.push(ws.id)
    }

    return ids
  }

  // Ids Hyprland explicitly reports on a different monitor. A configured id
  // drops off this bar only once it actually exists elsewhere, so an empty
  // pinned workspace never vanishes from its monitor.
  function foreignIds() {
    if (!root.monitor) return []

    var foreign = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var ws = values[i]
      if (ws.id <= 0 || ws.id > 99) continue
      if (!ws.monitor || ws.monitor.id === root.monitor.id) continue
      if (foreign.indexOf(ws.id) === -1) foreign.push(ws.id)
    }

    return foreign
  }

  // Quickshell's Workspace.monitor notifications do not reliably reach the
  // bindings below, so count Hyprland IPC events that can move workspaces
  // between monitors (or change their windows) and read the counter in
  // workspaceIds() to force a recompute when one lands.
  property int refreshTick: 0

  function workspaceIds() {
    root.refreshTick

    var live = root.liveIds()
    var configured = root.configuredIds()
    if (!configured) {
      live.sort(function(left, right) { return left - right })
      return live
    }

    var foreign = root.foreignIds()
    var ids = []
    for (var i = 0; i < configured.length; i++) {
      if (foreign.indexOf(configured[i]) === -1) ids.push(configured[i])
    }
    for (var j = 0; j < live.length; j++) {
      if (ids.indexOf(live[j]) === -1) ids.push(live[j])
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Jump to one window from the popover: focus it (which follows it across
  // workspaces) and maximize it — this Hyprland build's "maximized" fills the
  // screen but keeps the bar and reserved gaps visible, unlike real fullscreen.
  // cursorPos, captured from the click event, is restored after focusing so the
  // pointer stays over the bar instead of warping onto the raised window.
  function focusWindowFullscreen(address, cursorPos) {
    var addr = String(address || "")
    if (!root.bar || !/^0x[0-9a-fA-F]+$/.test(addr)) return

    var moveCmd = ""
    if (cursorPos && typeof cursorPos.x === "number" && typeof cursorPos.y === "number") {
      var px = Math.round(Number(cursorPos.x))
      var py = Math.round(Number(cursorPos.y))
      moveCmd = " && hyprctl dispatch " + Util.shellQuote("hl.dsp.cursor.move({ x = " + px + ", y = " + py + " })")
    }

    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:" + addr + "\" })")
      + " && hyprctl dispatch " + Util.shellQuote("hl.dsp.window.fullscreen({ mode = \"maximized\", window = \"address:" + addr + "\" })")
      + moveCmd)
  }

  // ------------------------------------------------- workspace records
  function desktopEntryFor(appId) {
    var raw = String(appId || "").trim()
    if (!raw) return null
    var candidates = [raw, raw.replace(/\.desktop$/i, "")]
    for (var i = 0; i < candidates.length; i++) {
      var entry = DesktopEntries.byId(candidates[i])
      if (entry) return entry
    }

    // Some apps report a reverse-domain class (e.g. md.obsidian.Obsidian) but
    // their .desktop id is the leaf ("obsidian"). Also match StartupWMClass.
    var lower = raw.toLowerCase()
    var leaf = raw
    var dot = raw.lastIndexOf(".")
    if (dot >= 0) leaf = raw.slice(dot + 1)
    var leafLower = leaf.toLowerCase()

    var apps = DesktopEntries.applications.values
    for (var j = 0; j < apps.length; j++) {
      var e = apps[j]
      var id = String(e.id || "").toLowerCase().replace(/\.desktop$/i, "")
      if (id === lower || id === leafLower) return e
      var sc = String(e.startupClass || "").toLowerCase()
      if (sc && (sc === lower || sc === leafLower)) return e
    }

    var host = WorkspaceModel.webAppHost(raw)
    if (host) return WorkspaceModel.findWebAppEntry(host, DesktopEntries.applications.values)
    return null
  }

  function iconSource(icon, appId) {
    var library = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    var request = String(icon || appId || "application-x-executable")
    if (library) {
      var fromLib = library.iconSource(request)
      if (fromLib) return fromLib
    }
    var fromTheme = Quickshell.iconPath(request, "application-x-executable")
    if (fromTheme) return fromTheme

    // Last resort: try the leaf of a reverse-domain id (e.g. "Obsidian").
    var raw = String(appId || "")
    var dot = raw.lastIndexOf(".")
    if (dot >= 0) {
      var leaf = raw.slice(dot + 1)
      if (leaf && leaf !== request) {
        fromTheme = Quickshell.iconPath(leaf, "application-x-executable")
        if (fromTheme) return fromTheme
      }
    }
    return ""
  }

  function metadataFor(appId) {
    var key = String(appId || "")
    var cached = root.metadataCache[key]
    if (cached) return cached
    var entry = root.desktopEntryFor(key)
    var meta = {
      name: entry ? String(entry.name || "") : "",
      iconName: entry ? String(entry.icon || "") : ""
    }
    root.metadataCache[key] = meta
    return meta
  }

  function rawWindows(workspace) {
    var values = workspace && workspace.toplevels ? workspace.toplevels.values : []
    return values.map(function(toplevel) {
      var appId = WorkspaceModel.hyprlandAppId(toplevel)
      var meta = root.metadataFor(appId)
      var addr = String(toplevel.address || "")
      // Quickshell reports Hyprland addresses bare; hyprctl wants the 0x form.
      if (addr && addr.indexOf("0x") !== 0) addr = "0x" + addr
      return {
        appId: appId,
        title: String(toplevel.title || ""),
        address: addr,
        name: meta.name,
        icon: root.iconSource(meta.iconName, appId),
        focused: toplevel.activated === true || (toplevel.wayland && toplevel.wayland.activated === true)
      }
    })
  }

  function workspaceRecord(id) {
    var serial = root.refreshSerial
    var workspace = root.workspaceById(id)
    var focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    return WorkspaceModel.buildWorkspace(id, root.rawWindows(workspace), focusedId, 3)
  }

  // ---------------------------------------------------- popover plumbing
  function requestPopover(target, record) {
    closeTimer.stop()
    if (!record || !record.occupied) {
      closePopover()
      return
    }
    pendingAnchor = target
    pendingRecord = record
    openTimer.restart()
  }

  function leavePopoverTarget(target) {
    if (pendingAnchor === target) openTimer.stop()
    if ((activeAnchor === target || pendingAnchor === target) && !(popoverLoader.item && popoverLoader.item.containsMouse)) closeTimer.restart()
  }

  function closePopover() {
    openTimer.stop()
    closeTimer.stop()
    pendingAnchor = null
    pendingRecord = null
    if (activeAnchor !== null) {
      fadingAnchor = activeAnchor
      fadingRecord = activeRecord
      unloadTimer.restart()
    }
    activeAnchor = null
    activeRecord = null
  }

  function refreshPopoverRecords() {
    if (pendingRecord) {
      var pendingWorkspace = workspaceById(pendingRecord.id)
      var refreshedPending = workspaceRecord(pendingRecord.id)
      if (!pendingWorkspace || !refreshedPending.occupied) {
        openTimer.stop()
        pendingAnchor = null
        pendingRecord = null
      } else {
        pendingRecord = refreshedPending
      }
    }

    if (activeRecord) {
      var activeWorkspace = workspaceById(activeRecord.id)
      var refreshedActive = workspaceRecord(activeRecord.id)
      if (!activeWorkspace || !refreshedActive.occupied) closePopover()
      else activeRecord = refreshedActive
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var topic = String(event.name || "").toLowerCase()
      var layout = topic === "workspace" || topic === "createworkspace" || topic === "destroyworkspace" ||
        topic === "movewindow" || topic === "movewindowworkspace" || topic === "monitoradded" ||
        topic === "monitorremoved" || topic === "focusedmon" || topic === "activespecial"
      if (layout) root.refreshTick = root.refreshTick + 1
      if (layout || WorkspaceModel.isWorkspaceEvent(topic)) {
        root.refreshSerial = root.refreshSerial + 1
        root.refreshPopoverRecords()
      }
    }
  }

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() {
      // Assigning a new object re-evaluates every record binding; the popover
      // holds snapshots, so refresh those explicitly.
      root.metadataCache = Object.create(null)
      root.refreshPopoverRecords()
    }
  }

  Timer {
    id: openTimer
    interval: 180
    onTriggered: {
      if (!root.pendingAnchor || !root.pendingRecord || !root.pendingRecord.occupied) return
      unloadTimer.stop()
      root.activeAnchor = root.pendingAnchor
      root.activeRecord = root.pendingRecord
    }
  }

  Timer {
    id: closeTimer
    interval: 220
    onTriggered: root.closePopover()
  }

  // Outlives the PopupCard fade (140 ms) so the card can animate out.
  Timer {
    id: unloadTimer
    interval: 200
    onTriggered: {
      root.fadingAnchor = null
      root.fadingRecord = null
    }
  }

  Loader {
    id: popoverLoader
    readonly property Item shownAnchor: root.activeAnchor || root.fadingAnchor
    readonly property var shownRecord: root.activeRecord || root.fadingRecord
    active: shownAnchor !== null && shownRecord !== null

    sourceComponent: WorkspacePopover {
      anchorItem: popoverLoader.shownAnchor
      bar: root.bar
      record: popoverLoader.shownRecord
      open: root.activeAnchor !== null && root.activeRecord !== null && root.activeRecord.occupied
      onContainsMouseChanged: {
        if (containsMouse) closeTimer.stop()
        else if (root.activeAnchor !== null) closeTimer.restart()
      }
      onWindowPicked: function(address, cursorPos) {
        root.closePopover()
        root.focusWindowFullscreen(address, cursorPos)
      }
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: wsButton
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property var record: root.workspaceRecord(modelData)

        bar: root.bar
        text: modelData === 10 ? "0" : String(modelData)
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
        onTooltipHoveredChanged: {
          if (wsButton.tooltipHovered) root.requestPopover(wsButton, wsButton.record)
          else root.leavePopoverTarget(wsButton)
        }

        Rectangle {
          id: focusMark
          readonly property real thickness: Style.spaceReal(2)
          readonly property real inset: Style.spaceReal(2)
          readonly property bool barTop: !root.bar || root.bar.position !== "bottom"

          visible: parent.focused && parent.labelWidth > 0
          z: 1
          color: Color.accent
          radius: thickness / 2
          height: root.vertical ? Math.max(Style.spaceReal(10), parent.labelWidth) : thickness
          width: root.vertical ? thickness : Math.max(Style.spaceReal(10), parent.labelWidth)
          // Vertical bars mark the edge facing the desktop; horizontal ones
          // underline below the number (overline when the bar sits at the
          // bottom of the screen).
          x: root.vertical
            ? (root.bar && root.bar.position === "left"
                ? parent.width - width - inset
                : inset)
            : (parent.width - width) / 2
          y: root.vertical
            ? (parent.height - height) / 2
            : (barTop
                ? parent.height - height - inset
                : inset)

          Behavior on x { enabled: visible; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          Behavior on y { enabled: visible; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
