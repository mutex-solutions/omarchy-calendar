import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Standalone bar widget. Click opens the panel; the same page Deck renders is
// shown inside it. Run this or the Deck section, not both: each would send its
// own reminders.
Panel {
  id: root

  moduleName: "mutex-solutions.calendar"
  ipcTarget: "mutex-solutions.calendar"

  readonly property var state: stateLoader.item

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: stateLoader
    source: "State.qml"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.state ? root.state.icon : ""
    active: root.state ? root.state.active : false
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(pageLoader.item ? pageLoader.item.preferredWidth : Style.space(860))
    contentHeight: panel.fittedContentHeight(pageLoader.item ? pageLoader.item.implicitHeight : Style.space(360), Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.close()
    }

    ScrollView {
      id: scroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

      Loader {
        id: pageLoader
        width: scroll.availableWidth
        active: root.opened
        source: "deck/Page.qml"
        onLoaded: if (item) item.state = root.state
      }
    }
  }

  onStateChanged: if (pageLoader.item) pageLoader.item.state = root.state
}
