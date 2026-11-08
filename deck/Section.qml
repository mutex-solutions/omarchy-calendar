import QtQuick
import Quickshell
import qs.Commons
import "../Model.js" as M

// Deck adapter. There is no toggle: a tap opens the page, which is what Deck
// does for a section without toggle(). The half and 1x1 tiles use Deck's own
// body, since label and detail already say what is next. The larger tiles list
// what is coming up.
Item {
  id: s

  readonly property var state: stateLoader.item

  readonly property bool active: state ? state.active : false
  readonly property string label: state ? state.label : "Calendar"
  readonly property string detail: state ? state.detail : ""
  readonly property string icon: state ? state.icon : "󰃭"
  readonly property var notice: state ? state.notice : null

  readonly property Component tileSquare: listTile
  readonly property Component tileFull: listTile

  function openPage() {
    Quickshell.execDetached(["omarchy-shell", "mutex-solutions.deck", "openSection", "calendar"])
  }

  Loader {
    id: stateLoader
    source: "../State.qml"
  }

  Component {
    id: listTile

    Item {
      id: body
      readonly property var st: s.state
      readonly property var list: st ? st.upcomingList : []
      readonly property double now: st ? st.now : Date.now()
      readonly property real rowH: Style.space(22)
      readonly property int capacity: Math.max(1, Math.floor((rows.height + Style.space(2)) / rowH))

      MouseArea {
        id: pageArea
        anchors.fill: parent
        property bool held: false
        cursorShape: Qt.PointingHandCursor
        onPressed: {
          held = false
          pageHold.restart()
        }
        onReleased: {
          pageHold.stop()
          if (!held) s.openPage()
        }
        onCanceled: pageHold.stop()

        // A custom body does not get the host's hold gesture. Match it here.
        Timer {
          id: pageHold
          interval: 450
          onTriggered: {
            pageArea.held = true
            s.openPage()
          }
        }
      }

      Text {
        id: heading
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        text: M.dayWord(body.now, body.now) + ", " + new Date(body.now).getDate() + " "
          + M.MONTHS[new Date(body.now).getMonth()].slice(0, 3)
        color: s.active ? Color.accent : Util.alpha(Color.foreground, 0.65)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
      }

      Item {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.topMargin: Style.space(4)
        anchors.bottomMargin: Style.space(6)
        clip: true

        Text {
          visible: body.list.length === 0
          anchors.left: parent.left
          anchors.right: parent.right
          text: s.detail
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Repeater {
          model: body.list.slice(0, body.capacity)

          Item {
            required property var modelData
            required property int index
            y: index * body.rowH
            width: rows.width
            height: body.rowH

            Rectangle {
              id: dot
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: (body.st ? body.st.eventColor(modelData) : modelData.color) || Color.accent
            }

            Text {
              id: time
              anchors.left: dot.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(38)
              text: M.shortColumn(modelData, body.now)
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              anchors.left: time.right
              anchors.leftMargin: Style.space(4)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
