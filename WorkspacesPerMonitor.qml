import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WorkspaceModel.js" as WorkspaceModel

// Drop-in replacement for omarchy.workspaces that shows each monitor's own
// block of workspaces, labelled 1-10 the way Omarchy labels them (see
// default/hypr/monitor-workspaces.lua in Omarchy). Clicking the active
// workspace cycles its layout, as in omarchy.workspaces.
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

  // Quickshell's Workspace.monitor notifications do not reliably reach the
  // bindings below, so count Hyprland IPC events that can move workspaces
  // between monitors (or change their windows) and read the counter in
  // workspaceIds() to force a recompute when one lands.
  property int refreshTick: 0

  // Connector -> workspace block, from the file Omarchy keeps them in.
  property var blocks: ({})
  readonly property int slots: 10

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  readonly property string monitorName: root.monitor ? String(root.monitor.name || "") : ""

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  // Until Omarchy has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
    return active > 0 ? root.blockOf(active) : 0
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    root.refreshTick

    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  // Each workspace's layout, read with Omarchy's own command since Hyprland
  // only reports tiled layouts and floating is kept by Omarchy.
  property var modes: ({})
  property bool modesStale: false

  function refreshModes() {
    if (modeProc.running) {
      root.modesStale = true
      return
    }
    var ids = root.workspaceIds().map(String)
    modeProc.command = ["bash", "-c", "for id in \"$@\"; do printf '%s %s\\n' \"$id\" \"$(omarchy-hyprland-workspace-layout-current \"$id\")\"; done", "bash"].concat(ids)
    modeProc.running = true
  }

  Component.onCompleted: refreshModes()
  onRefreshTickChanged: refreshModes()

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/workspace-layout-notification"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshModes()
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var next = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var fields = lines[i].trim().split(" ")
          if (fields.length === 2 && fields[1] !== "") next[fields[0]] = fields[1]
        }
        root.modes = next
      }
    }
    onExited: {
      if (!root.modesStale) return
      root.modesStale = false
      Qt.callLater(root.refreshModes)
    }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
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
      var layout = topic === "workspace" || topic === "workspacev2" || topic === "createworkspace" ||
        topic === "destroyworkspace" || topic === "movewindow" || topic === "movewindowworkspace" ||
        topic === "moveworkspace" || topic === "moveworkspacev2" || topic === "changeworkspaceid" ||
        topic === "monitoradded" || topic === "monitorremoved" || topic === "focusedmon" ||
        topic === "activespecial" || topic === "configreloaded"
      // Quickshell misses the workspace a monitor falls back to and the
      // workspaces that change number, so ask Hyprland for the truth.
      var switched = topic === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || topic === "moveworkspacev2" || topic === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
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
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property string mode: root.modes[modelData] || "dwindle"
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        required property int index

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        bar: root.bar
        text: slot === root.slots ? "0" : String(slot)
        opacity: occupied || focused || shown ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function(button) {
          if (shown && button === Qt.RightButton) root.cycleLayout()
          else root.focusWorkspace(modelData)
        }
        onTooltipHoveredChanged: {
          if (wsButton.tooltipHovered) root.requestPopover(wsButton, wsButton.record)
          else root.leavePopoverTarget(wsButton)
        }

        Rectangle {
          id: focusMark
          readonly property real thickness: Style.spaceReal(2)
          readonly property real inset: Style.spaceReal(2)
          readonly property bool barTop: !root.bar || root.bar.position !== "bottom"

          visible: parent.focused && parent.mode === "dwindle" && parent.labelWidth > 0
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

        // Same metrics the button uses to center its number, so a box drawn
        // around it lands on the figures rather than the line box.
        FontMetrics {
          id: figureMetrics
          font.family: wsButton.fontFamily
          font.pixelSize: wsButton.fontSize
        }
        readonly property real figureHeight: figureMetrics.tightBoundingRect("0").height
        readonly property real figureOffset: root.vertical ? 0
          : (figureMetrics.descent - figureMetrics.ascent + figureHeight) / 2

        // Scrolling: a dot where the tiling underline would sit.
        Rectangle {
          id: scrollingDot
          readonly property real size: Style.spaceReal(3)
          readonly property real inset: Style.spaceReal(2)
          readonly property bool barTop: !root.bar || root.bar.position !== "bottom"

          visible: parent.focused && parent.mode === "scrolling" && parent.labelWidth > 0
          z: 1
          color: Color.accent
          radius: size / 2
          width: size
          height: size
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
        }

        // Floating: a box around the number.
        Rectangle {
          visible: parent.focused && parent.mode === "floating" && parent.labelWidth > 0
          z: 1
          anchors.centerIn: parent
          anchors.verticalCenterOffset: parent.figureOffset
          width: parent.labelWidth + Style.spaceReal(9)
          height: parent.figureHeight + Style.spaceReal(8)
          color: "transparent"
          border.color: Color.accent
          border.width: Style.spaceReal(2)
          radius: Style.spaceReal(2)
        }
      }
    }
  }
}
