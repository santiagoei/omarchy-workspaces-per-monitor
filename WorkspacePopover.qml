// Vendored from jacobsennando.workspace-lens WorkspacePopover.qml (MIT, Copyright
// (c) 2026 JacobsenNando), adapted here: groups show the app icon + name +
// count, and each window gets its own clickable row below with its title and
// a marker when it is the focused window. Clicking a row emits windowPicked so
// the host can focus + maximize that exact window while keeping the cursor in
// place.
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

PopupCard {
  id: root

  property var record: null

  // Emitted when a window row is clicked, with the Hyprland window address and
  // the global cursor position where the click happened.
  signal windowPicked(string address, var cursorPos)

  // While fading out the window is still mapped; an empty mask makes it
  // click-through so a fast click below the bar reaches the app underneath.
  readonly property var emptyMask: Region { }
  mask: open ? null : emptyMask
  readonly property bool scrollable: contentHeight < groupsColumn.implicitHeight + header.height + verticalContentInset + Style.space(5)

  triggerMode: "hover"
  contentWidth: fittedContentWidth(Style.space(340), Style.space(420))
  contentHeight: fittedContentHeight(groupsColumn.implicitHeight + header.height + Style.space(5), Style.space(520))

  component WindowRow: Item {
    id: row

    required property var modelData
    required property QtObject barHost

    signal picked(string address, var cursorPos)

    function tooltipText(value) {
      return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
    }

    readonly property color foreground: barHost ? barHost.foreground : Color.foreground
    readonly property real rowHeight: Style.spaceReal(15)
    readonly property bool clickable: String(modelData.address || "").length > 0

    width: parent ? parent.width : 0
    height: rowHeight
    implicitHeight: rowHeight

    Accessible.role: clickable ? Accessible.Button : Accessible.StaticText
    Accessible.name: modelData.title
    Accessible.onPressAction: if (clickable) row.picked(String(modelData.address), { x: 0, y: 0 })

    BorderSurface {
      anchors.fill: parent
      anchors.leftMargin: -Style.spaceReal(2)
      anchors.rightMargin: -Style.spaceReal(2)
      radius: Style.cornerRadius
      color: hoverArea.containsMouse && row.clickable
        ? Util.alpha(row.foreground, 0.08) : "transparent"
      Accessible.ignored: true
    }

    Text {
      id: titleLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(13) + Style.space(3)
      anchors.right: focusDot.visible ? focusDot.left : parent.right
      anchors.rightMargin: focusDot.visible ? Style.space(2) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: row.modelData.title
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: row.foreground
      opacity: row.modelData.focused ? 1 : 0.75
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      Accessible.ignored: true
    }

    Rectangle {
      id: focusDot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: row.modelData.focused
      width: Style.space(5)
      height: width
      radius: width / 2
      color: Color.accent
      Accessible.ignored: true
    }

    MouseArea {
      id: hoverArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.clickable
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: if (titleLabel.truncated && row.barHost)
        row.barHost.showTooltip(hoverArea, row.tooltipText(titleLabel.text))
      onExited: if (row.barHost)
        row.barHost.hideTooltip(hoverArea)
      onClicked: function(mouse) {
        row.picked(String(row.modelData.address), hoverArea.mapToGlobal(mouse.x, mouse.y))
      }
    }
  }

  component GroupDetails: BorderSurface {
    id: groupDetails

    required property var modelData
    required property QtObject barHost

    readonly property color foreground: barHost ? barHost.foreground : Color.foreground
    readonly property int inset: Style.space(4)

    width: ListView.view ? ListView.view.width : parent.width
    height: groupColumn.implicitHeight + inset * 2
    radius: Style.cornerRadius
    color: Util.alpha(foreground, 0.06)

    Column {
      id: groupColumn
      x: groupDetails.inset
      y: groupDetails.inset
      width: parent.width - groupDetails.inset * 2
      spacing: Style.space(1)

      Row {
        id: groupRow
        width: parent.width
        spacing: Style.space(3)

        AppIcon {
          id: appIcon
          source: groupDetails.modelData.icon
          label: groupDetails.modelData.name
          foreground: groupDetails.foreground
          size: Style.space(13)
        }

        Text {
          id: groupName
          width: parent.width - appIcon.width - groupCount.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: groupDetails.modelData.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: groupDetails.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          Accessible.ignored: true
        }

        Text {
          id: groupCount
          anchors.verticalCenter: parent.verticalCenter
          text: groupDetails.modelData.count + (groupDetails.modelData.count === 1 ? " window" : " windows")
          color: groupDetails.foreground
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          Accessible.ignored: true
        }
      }

      Repeater {
        model: groupDetails.modelData.windows

        WindowRow {
          barHost: groupDetails.barHost
          onPicked: function(address, cursorPos) { root.windowPicked(address, cursorPos) }
        }
      }
    }
  }

  Column {
    id: contentColumn
    anchors.fill: parent
    spacing: Style.space(5)

    Item {
      id: header
      width: parent.width
      height: headerTitle.implicitHeight

      Text {
        id: headerTitle
        anchors.left: parent.left
        text: root.record ? "Workspace " + root.record.id : ""
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        anchors.baseline: headerTitle.baseline
        text: root.record ? root.record.appCount + (root.record.appCount === 1 ? " app" : " apps") + " · " + root.record.windowCount + (root.record.windowCount === 1 ? " window" : " windows") : ""
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        Accessible.ignored: true
      }
    }

    Item {
      id: groupsViewport
      width: parent.width
      height: root.scrollable ? Math.max(0, parent.height - header.height - contentColumn.spacing) : groupsColumn.implicitHeight
      clip: root.scrollable

      Column {
        id: groupsColumn
        visible: !root.scrollable
        width: parent.width
        spacing: Style.space(3)

        Repeater {
          model: root.record ? root.record.groups : []

          GroupDetails {
            barHost: root.bar
          }
        }
      }

      ListView {
        visible: root.scrollable
        anchors.fill: parent
        clip: true
        spacing: Style.space(3)
        model: root.record ? root.record.groups : []

        delegate: GroupDetails {
          barHost: root.bar
        }
      }
    }
  }
}
