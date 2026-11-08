import QtQuick
import Quickshell
import qs.Commons
import "../Model.js" as M

// The full calendar: a month on the left, the chosen day and what is coming up
// on the right, and a form for adding an event. On a narrow card the two stack.
// Calendar data lives in State; the host draws the back button and the title.
Item {
  id: page

  property var state: null
  property var host: null

  // Deck widens its card for a page that asks. Only the month needs the room.
  readonly property real preferredWidth: view === "month" && !(state && state.compact) ? Style.space(860) : 0

  // Compact is the narrow layout by choice; a narrow screen gets it either way.
  readonly property bool wide: !(state && state.compact) && width >= Style.space(620)
  readonly property real gap: Style.space(12)
  readonly property real agendaWidth: wide ? Style.space(270) : width
  readonly property real barH: Style.space(30)
  readonly property real labelsH: Style.space(20)
  readonly property real cellH: wide ? Style.space(84) : Style.space(40)
  // With more than one account, a row of account chips sits under the month bar.
  readonly property bool multi: !!state && state.multiAccount
  readonly property real accountsH: multi ? accountFlow.implicitHeight + Style.space(6) : 0
  readonly property real monthH: barH + accountsH + labelsH + 6 * cellH
  readonly property double now: state ? state.now : Date.now()
  readonly property var dayEvents: state && state.viewIndex[state.selectedDay] ? state.viewIndex[state.selectedDay] : []
  readonly property var soon: state ? state.upcomingList.slice(0, 6) : []
  readonly property string selectedTitle: {
    if (!state) return ""
    var p = state.selectedDay.split("-")
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    return M.DAYS[d.getDay()] + " " + d.getDate() + " " + M.MONTHS[d.getMonth()]
  }

  implicitHeight: view === "account" ? accountView.implicitHeight
    : adding ? addForm.implicitHeight
    : (wide ? monthH : monthH + gap + agendaColumn.implicitHeight)

  // The form and the settings are views of their own; the host draws their
  // crumb and back arrow.
  property string view: "month"
  readonly property bool adding: view === "add"
  readonly property var trail: adding ? [editId !== "" ? "Edit event" : "New event"]
    : (view === "account" ? ["Settings"] : [])
  readonly property bool canGoBack: view !== "month"
  function goBack() { view = "month" }
  function goTo(i) { if (i < 0) view = "month" }

  function openAdd() {
    if (!state) return
    editId = ""
    titleField.text = ""
    dateField.text = state.selectedDay
    startField.text = "09:00"
    endField.text = ""
    locationField.text = ""
    allDay = false
    formError = ""
    state.createError = ""
    calendarId = state.writableCalendars.length > 0 ? state.writableCalendars[0].id : ""
    calendarAccount = state.writableCalendars.length > 0 ? String(state.writableCalendars[0].account || "") : ""
    view = "add"
    titleField.takeFocus()
  }

  function openEdit(event) {
    if (!state) return
    editId = event.id
    titleField.text = event.title
    dateField.text = M.dayKey(new Date(event.start))
    allDay = event.allDay === true
    startField.text = allDay ? "09:00" : M.clock(event.start)
    endField.text = allDay ? "" : M.clock(event.end)
    locationField.text = event.location || ""
    formError = ""
    state.createError = ""
    view = "add"
    titleField.takeFocus()
  }

  function saveNew() {
    if (!state || state.creating) return
    var request = M.newEventRequest(titleField.text, dateField.text.trim(), allDay,
      startField.text.trim(), endField.text.trim(), locationField.text, editId !== "" ? "" : calendarId)
    formError = request.error || ""
    if (request.error) return
    if (editId !== "") {
      request.id = editId
      state.updateEvent(request)
    } else {
      if (calendarAccount !== "") request.account = calendarAccount
      state.createEvent(request)
    }
  }

  property bool allDay: false
  property string formError: ""
  property string calendarId: ""
  property string calendarAccount: ""
  // The local event being edited, or empty for a new one.
  property string editId: ""

  Connections {
    target: page.state
    function onCreated(day) { page.view = "month" }
  }

  // Bind to the page being on screen, not to its existence: Deck keeps a loaded
  // page while the panel opens and closes.
  readonly property bool shown: host ? host.open === true : true
  onShownChanged: if (shown && state) state.fetchMonth()
  onStateChanged: if (shown && state) state.fetchMonth()

  component Caps: Text {
    color: Util.alpha(Color.foreground, 0.45)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  component Field: Item {
    id: field
    property alias text: input.text
    property string placeholder: ""
    function takeFocus() { input.forceActiveFocus() }
    signal accepted()

    height: Style.space(28)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.05)
      border.width: 1
      border.color: input.activeFocus ? Util.alpha(Color.accent, 0.7) : Util.alpha(Color.foreground, 0.22)
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: Text.AlignVCenter
      visible: input.text === ""
      text: field.placeholder
      color: Util.alpha(Color.foreground, 0.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      clip: true
      selectByMouse: true
      onAccepted: field.accepted()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string text: ""
    property bool strong: false
    signal clicked()
    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.cornerRadius
    color: chipMouse.containsMouse
      ? Util.alpha(Color.foreground, 0.14)
      : (strong ? Util.alpha(Color.accent, 0.22) : Util.alpha(Color.foreground, 0.06))
    border.width: 1
    border.color: strong ? Util.alpha(Color.accent, 0.5) : Util.alpha(Color.foreground, 0.1)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.text
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // An account in the filter row: its colour, its address, chosen or not.
  component AccountChip: Rectangle {
    id: ac
    property string key: ""
    property string text: ""
    property color dot: Color.accent
    property bool chosen: false
    property bool broken: false
    signal clicked()
    width: acRow.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.cornerRadius
    color: acMouse.containsMouse ? Util.alpha(Color.foreground, 0.14)
      : (chosen ? Util.alpha(dot, 0.22) : Util.alpha(Color.foreground, 0.06))
    border.width: 1
    border.color: chosen ? Util.alpha(dot, 0.8) : Util.alpha(Color.foreground, 0.1)

    // Row places only; the row itself is centred, its children are not anchored.
    Row {
      id: acRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Rectangle {
        y: (acText.height - height) / 2
        width: Style.space(8)
        height: width
        radius: width / 2
        color: ac.dot
        opacity: ac.broken ? 0.35 : 1
      }

      Text {
        id: acText
        text: ac.text
        color: ac.broken ? Color.urgent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: acMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ac.clicked()
    }
  }

  // One event in a list. Pressing it opens its details in place.
  component EventRow: Item {
    id: row
    property var event: null
    property bool showDay: false
    readonly property bool open: !!event && !!page.state && page.state.openEventId === rowKey
    readonly property string rowKey: event ? (showDay ? "soon:" : "day:") + event.id : ""
    readonly property real detailH: open ? details.implicitHeight + Style.space(6) : 0
    property bool deleteArmed: false
    onOpenChanged: deleteArmed = false

    width: parent ? parent.width : 0
    height: Style.space(28) + detailH

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.open ? Util.alpha(Color.foreground, 0.06)
        : (rowMouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent")
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (page.state) page.state.openEventId = row.open ? "" : row.rowKey
    }

    Item {
      id: head
      width: parent.width
      height: Style.space(28)

      Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(3)
        height: Style.space(16)
        radius: width
        color: (row.event && page.state ? page.state.eventColor(row.event) : "") || Color.accent
        opacity: row.event && row.event.declined ? 0.35 : 1
      }

      Text {
        id: when
        anchors.left: bar.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(row.showDay ? 66 : 48)
        text: !row.event ? ""
          : row.showDay ? M.timeColumn(row.event, page.now)
          : (row.event.allDay ? "All day" : M.clock(row.event.start))
        color: Util.alpha(Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        anchors.left: when.right
        anchors.leftMargin: Style.space(4)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.event ? row.event.title : ""
        color: row.event && row.event.declined ? Util.alpha(Color.foreground, 0.45) : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.strikeout: !!row.event && row.event.declined
        elide: Text.ElideRight
      }
    }

    Column {
      id: details
      visible: row.open
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(17)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      Text {
        width: parent.width
        visible: text !== ""
        text: row.event && !row.event.allDay ? M.clock(row.event.start) + " to " + M.clock(row.event.end) : ""
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: row.event ? row.event.location : ""
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: !row.event ? ""
          : row.event.calendar + (page.multi ? " · " + page.state.accountLabel(row.event.account) : "")
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Item {
        width: parent.width
        height: Style.space(24)

        Chip {
          id: joinChip
          visible: !!row.event && row.event.joinUrl !== ""
          strong: true
          text: "Join"
          onClicked: page.state.openLink(row.event.joinUrl)
        }

        Chip {
          anchors.left: joinChip.visible ? joinChip.right : parent.left
          anchors.leftMargin: joinChip.visible ? Style.space(6) : 0
          visible: !!row.event && row.event.url !== ""
          text: "Open in Google"
          onClicked: page.state.openLink(row.event.url)
        }

        // Local events have no Google to go and change them in.
        Chip {
          id: editChip
          visible: !!row.event && row.event.local === true
          text: "Edit"
          onClicked: page.openEdit(row.event)
        }

        Chip {
          anchors.left: editChip.right
          anchors.leftMargin: Style.space(6)
          visible: editChip.visible
          text: row.deleteArmed ? "Really delete" : "Delete"
          strong: row.deleteArmed
          onClicked: {
            if (row.deleteArmed) page.state.deleteEvent(row.event.id)
            else row.deleteArmed = true
          }
        }
      }
    }
  }

  // ---- settings: the Google account ---------------------------------------

  Column {
    id: accountView
    visible: page.view === "account"
    width: parent.width
    spacing: Style.space(10)

    readonly property string status: page.state ? page.state.status : "loading"
    readonly property bool connected: !!page.state && page.state.hasData && status === "ok"

    Text {
      width: parent.width
      text: accountView.connected ? "Google connected" : "Connect Google"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      wrapMode: Text.Wrap
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: accountView.connected ? (page.state.account || "")
        : (page.state && accountView.status !== "missing" ? page.state.message : "")
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    // Every Google account, each with its colour and whether it answered.
    Repeater {
      // Only once something answered: before that, the steps below say more.
      model: accountView.connected ? page.state.accounts : []

      Item {
        required property var modelData
        width: accountView.width
        height: Style.space(24)

        Rectangle {
          id: accountDot
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(8)
          height: width
          radius: width / 2
          color: page.state.accountColor(modelData.key) || Color.accent
          opacity: modelData.ok ? 1 : 0.35
        }

        Text {
          anchors.left: accountDot.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (modelData.email || modelData.key) + (modelData.ok ? ""
            : modelData.code === "signin" ? " · sign in again" : " · unavailable")
          color: modelData.ok ? Color.foreground : Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    Caps {
      visible: accountView.connected
      text: "CALENDARS"
    }

    Repeater {
      model: accountView.connected && page.state ? page.state.calendars.filter(function(c) { return c.id !== "local" }) : []

      Item {
        required property var modelData
        width: accountView.width
        height: Style.space(24)

        Rectangle {
          id: calendarDot
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(8)
          height: width
          radius: width / 2
          color: modelData.color || Color.accent
        }

        Text {
          anchors.left: calendarDot.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name + (page.multi ? " · " + page.state.accountLabel(modelData.account) : "")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }

    Caps {
      visible: accountView.connected
      text: "ADD AN ACCOUNT"
    }

    Text {
      width: parent.width
      visible: !accountView.connected
      text: "gws needs your OAuth client at ~/.config/gws/client_secret.json"
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    Repeater {
      model: accountView.connected
        ? ["GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/work gws auth login -s calendar"]
        : accountView.status === "missing"
          ? ["sudo pacman -S googleworkspace-cli", "gws auth login -s calendar"]
          : ["gws auth login -s calendar"]

      Item {
        required property string modelData
        width: accountView.width
        height: Style.space(30)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Util.alpha(Color.foreground, 0.05)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: copyChip.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Chip {
          id: copyChip
          anchors.right: parent.right
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          text: "Copy"
          onClicked: Quickshell.execDetached(["wl-copy", modelData])
        }
      }
    }

    Chip {
      text: accountView.connected ? "Refresh" : "Check again"
      strong: !accountView.connected
      onClicked: page.state.refresh()
    }
  }

  // ---- a new event --------------------------------------------------------

  Column {
    id: addForm
    visible: page.adding
    x: Math.max(0, (page.width - width) / 2)
    width: Math.min(page.width, Style.space(420))
    spacing: Style.space(8)

    Field {
      id: titleField
      width: parent.width
      placeholder: "Title"
      onAccepted: page.saveNew()
    }

    Item {
      width: parent.width
      height: Style.space(28)

      Field {
        id: dateField
        width: Style.space(120)
        anchors.left: parent.left
        placeholder: "YYYY-MM-DD"
        onAccepted: page.saveNew()
      }

      Field {
        id: startField
        visible: !page.allDay
        width: Style.space(70)
        anchors.left: dateField.right
        anchors.leftMargin: Style.space(6)
        placeholder: "Start"
        onAccepted: page.saveNew()
      }

      Field {
        id: endField
        visible: !page.allDay
        width: Style.space(70)
        anchors.left: startField.right
        anchors.leftMargin: Style.space(6)
        placeholder: "End"
        onAccepted: page.saveNew()
      }

      Chip {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "All day"
        strong: page.allDay
        onClicked: page.allDay = !page.allDay
      }
    }

    Field {
      id: locationField
      width: parent.width
      placeholder: "Location"
      onAccepted: page.saveNew()
    }

    Flow {
      width: parent.width
      spacing: Style.space(4)
      visible: page.editId === "" && !!page.state && page.state.writableCalendars.length > 1

      Repeater {
        model: page.state ? page.state.writableCalendars : []

        Chip {
          required property var modelData
          text: modelData.name + (page.multi && page.state.shownAccount === ""
            ? " · " + page.state.accountLabel(modelData.account) : "")
          strong: page.calendarId === modelData.id
          onClicked: {
            page.calendarId = modelData.id
            page.calendarAccount = String(modelData.account || "")
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: page.formError !== "" ? page.formError : (page.state ? page.state.createError : "")
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    Chip {
      text: page.state && page.state.creating ? "Saving" : (page.editId !== "" ? "Save" : "Add event")
      strong: true
      onClicked: page.saveNew()
    }
  }

  // ---- the month ---------------------------------------------------------

  Item {
    id: monthBox
    visible: page.view === "month"
    width: page.width - (page.wide ? page.agendaWidth + page.gap : 0)
    height: page.monthH

    Item {
      id: monthBar
      width: parent.width
      height: page.barH

      Chip {
        id: prevChip
        anchors.verticalCenter: parent.verticalCenter
        text: "‹"
        onClicked: page.state.shiftMonth(-1)
      }

      Chip {
        id: nextChip
        anchors.left: prevChip.right
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        onClicked: page.state.shiftMonth(1)
      }

      Text {
        anchors.left: nextChip.right
        anchors.leftMargin: Style.space(10)
        anchors.right: statusText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: !page.state ? ""
          : page.wide ? M.monthTitle(page.state.viewYear, page.state.viewMonth)
          : M.MONTHS[page.state.viewMonth].slice(0, 3) + " " + page.state.viewYear
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: statusText
        anchors.right: newChip.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        // Says so when what is on screen is not current. Quiet when it is.
        text: !page.state || page.state.status === "loading" ? ""
          : page.state.status === "ok" ? page.state.accountTrouble
          : page.state.needsSignIn ? "Not connected"
          : (page.state.status === "offline" ? "Offline" : page.state.message)
            + (page.state.hasData ? ", from " + M.clock(page.state.lastSync) : "")
        color: page.state && page.state.needsSignIn ? Util.alpha(Color.foreground, 0.5) : Color.urgent
        width: page.wide ? Math.min(implicitWidth, Style.space(200)) : 0
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Chip {
        id: newChip
        anchors.right: todayChip.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: page.wide ? "New" : "+"
        strong: true
        onClicked: page.openAdd()
      }

      Chip {
        id: todayChip
        anchors.right: refreshChip.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: "Today"
        onClicked: page.state.goToday()
      }

      Chip {
        id: refreshChip
        anchors.right: settingsChip.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: page.wide ? "Refresh" : "↻"
        onClicked: page.state.refresh()
      }

      Chip {
        id: settingsChip
        anchors.right: sizeChip.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: page.wide ? "Settings" : "󰒓"
        onClicked: page.view = "account"
      }

      // Full month and agenda side by side, or the compact one above the other.
      Chip {
        id: sizeChip
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: page.state && page.state.compact ? "󰊓" : "Compact"
        onClicked: page.state.setCompact(!page.state.compact)
      }
    }

    Flow {
      id: accountFlow
      visible: page.multi
      y: page.barH + Style.space(2)
      width: parent.width
      spacing: Style.space(4)

      AccountChip {
        text: "All"
        // Neutral: the first account's colour is close to most accents.
        dot: Util.alpha(Color.foreground, 0.6)
        chosen: !!page.state && page.state.shownAccount === ""
        onClicked: page.state.chooseAccount("")
      }

      Repeater {
        model: page.state ? page.state.accounts : []

        AccountChip {
          required property var modelData
          key: modelData.key
          // Only a sign-in problem asks to sign in again; Google's own hiccups
          // (5xx, offline) say "unavailable" and clear at the next refresh.
          text: (modelData.email || modelData.key) + (modelData.ok ? ""
            : modelData.code === "signin" ? " · sign in again" : " · unavailable")
          dot: page.state.accountColor(modelData.key) || Color.accent
          broken: !modelData.ok
          chosen: page.state.shownAccount === modelData.key
          onClicked: page.state.chooseAccount(modelData.key)
        }
      }
    }

    Item {
      id: labels
      y: page.barH + page.accountsH
      width: parent.width
      height: page.labelsH

      Repeater {
        model: page.state ? M.weekdayLabels(page.state.firstDayOfWeek) : []

        Text {
          required property string modelData
          required property int index
          x: index * labels.width / 7
          width: labels.width / 7
          height: labels.height
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }

    Item {
      id: cells
      y: page.barH + page.accountsH + page.labelsH
      width: parent.width
      height: 6 * page.cellH
      readonly property real cellW: width / 7

      Repeater {
        model: page.state ? page.state.grid : []

        Rectangle {
          id: cell
          required property var modelData
          required property int index
          readonly property bool isToday: !!page.state && modelData.key === page.state.todayKey
          readonly property bool isSelected: !!page.state && modelData.key === page.state.selectedDay
          readonly property var dayList: page.state && page.state.viewIndex[modelData.key] ? page.state.viewIndex[modelData.key] : []
          // Three rows of events fit a wide cell; the last gives way to "+N".
          readonly property int shownCount: !page.wide ? 0 : (dayList.length > 3 ? 2 : dayList.length)

          x: (index % 7) * cells.cellW
          y: Math.floor(index / 7) * page.cellH
          width: cells.cellW
          height: page.cellH
          radius: Style.cornerRadius
          color: isSelected ? Util.alpha(Color.accent, 0.14)
            : (cellMouse.containsMouse ? Util.alpha(Color.foreground, 0.05) : "transparent")
          border.width: 1
          border.color: isSelected ? Util.alpha(Color.accent, 0.6) : Util.alpha(Color.foreground, 0.06)

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.state.selectDay(cell.modelData.key)
          }

          Rectangle {
            id: dayDisc
            x: page.wide ? Style.space(4) : (parent.width - width) / 2
            y: Style.space(3)
            width: Style.space(20)
            height: width
            radius: width / 2
            color: cell.isToday ? Color.accent : "transparent"

            Text {
              anchors.centerIn: parent
              text: cell.modelData.day
              color: cell.isToday ? Color.background
                : Util.alpha(Color.foreground, cell.modelData.inMonth ? 0.9 : 0.3)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: cell.isToday
            }
          }

          // A wide cell names its events.
          Repeater {
            model: cell.dayList.slice(0, cell.shownCount)

            Rectangle {
              required property var modelData
              required property int index
              x: Style.space(3)
              y: Style.space(25) + index * Style.space(18)
              width: cell.width - Style.space(6)
              height: Style.space(16)
              radius: Style.space(3)
              color: Util.alpha(page.state.eventColor(modelData) || Color.accent, modelData.declined ? 0.12 : 0.32)
              opacity: cell.modelData.inMonth ? 1 : 0.5

              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(4)
                anchors.rightMargin: Style.space(2)
                verticalAlignment: Text.AlignVCenter
                text: modelData.title
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.strikeout: modelData.declined === true
                elide: Text.ElideRight
              }
            }
          }

          Text {
            visible: page.wide && cell.dayList.length > 3
            x: Style.space(7)
            y: Style.space(25) + 2 * Style.space(18)
            height: Style.space(16)
            verticalAlignment: Text.AlignVCenter
            text: "+" + (cell.dayList.length - 2) + " more"
            color: Util.alpha(Color.foreground, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // A narrow cell has room only to say there is something.
          Rectangle {
            visible: !page.wide && cell.dayList.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(27)
            width: Style.space(5)
            height: width
            radius: width / 2
            color: (cell.dayList.length > 0 ? page.state.eventColor(cell.dayList[0]) : "") || Color.accent
          }
        }
      }
    }
  }

  // ---- the day and what is next ------------------------------------------

  Flickable {
    id: agenda
    visible: page.view === "month"
    x: page.wide ? monthBox.width + page.gap : 0
    y: page.wide ? 0 : page.monthH + page.gap
    width: page.agendaWidth
    height: page.wide ? page.monthH : agendaColumn.implicitHeight
    contentHeight: agendaColumn.implicitHeight
    interactive: page.wide && contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: agendaColumn
      width: agenda.width
      spacing: Style.space(2)

      Item {
        width: parent.width
        height: page.barH

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: page.selectedTitle
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
      }

      Repeater {
        model: page.dayEvents

        EventRow {
          required property var modelData
          event: modelData
        }
      }

      Text {
        visible: page.dayEvents.length === 0
        leftPadding: Style.space(6)
        height: Style.space(28)
        verticalAlignment: Text.AlignVCenter
        text: "No events"
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: parent.width
        height: Style.space(30)

        Caps {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          text: "UPCOMING"
        }
      }

      Repeater {
        model: page.soon

        EventRow {
          required property var modelData
          event: modelData
          showDay: true
        }
      }

      Text {
        visible: page.soon.length === 0
        leftPadding: Style.space(6)
        height: Style.space(28)
        verticalAlignment: Text.AlignVCenter
        text: "Nothing coming up"
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
