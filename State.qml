import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as M

// Calendar state. One instance, shared by the tile and the page.
//
// Events come from scripts/calendar: local ones always, Google's when it is
// connected. Two windows are kept:
// `events`, yesterday to six weeks ahead, which feeds the tile, the notice and
// the reminders; and one month at a time for the page. Sections stay loaded
// with the panel closed, which is what lets reminders fire from here.
Item {
  id: s

  readonly property string helper: String(Qt.resolvedUrl("scripts/calendar")).replace("file://", "")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/deck"
  readonly property int refreshMs: 300000

  // Google's state: loading, ok, missing (no gws), signin, offline, error
  property string status: "loading"
  property string message: ""
  property string account: ""
  // [{ key, email, ok, code, error }], one per signed-in gws directory.
  property var accounts: []
  property var calendars: []
  property var events: []
  // When Google last answered. Zero until then; local events do not need it.
  property double lastSync: 0
  property bool loaded: false
  property double now: Date.now()
  readonly property bool hasData: lastSync > 0
  readonly property bool needsSignIn: !hasData && (status === "missing" || status === "signin")

  // ---- accounts --------------------------------------------------------
  // The filter is a view: it narrows the tile, the month and the form, never
  // the reminders or Deck's notice, which keep watching every account.

  property string accountFilter: ""
  readonly property string shownAccount: M.effectiveAccount(accounts, accountFilter)
  readonly property bool multiAccount: accounts.length > 1
  readonly property string accountTrouble: M.accountTrouble(accounts)
  readonly property var shownEvents: M.forAccount(events, shownAccount)

  function accountColor(key) { return M.accountColor(accounts, key) }
  function accountLabel(key) { return M.accountLabel(accounts, key) }

  // Coloured by account when every account is on screen, so they can be told
  // apart; by Google's own calendar colour when one account is chosen.
  function eventColor(e) {
    if (!e) return ""
    if (multiAccount && shownAccount === "") return accountColor(e.account) || e.color || ""
    return e.color || ""
  }

  // Compact: a small month with the day's events under it, at Deck's usual width.
  property bool compact: false

  function chooseAccount(key) {
    accountFilter = key || ""
    saveView()
  }

  function setCompact(on) {
    compact = on === true
    saveView()
  }

  function saveView() {
    viewFile.setText(JSON.stringify({ account: accountFilter, compact: compact }))
  }

  FileView {
    id: viewFile
    path: s.stateDir + "/calendar-view.json"
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text()) || {}
        s.accountFilter = String(saved.account || "")
        s.compact = saved.compact === true
      } catch (e) {
      }
    }
  }

  readonly property var upcomingList: M.upcoming(shownEvents, now)
  readonly property var next: {
    for (var i = 0; i < upcomingList.length; i++)
      if (!upcomingList[i].allDay) return upcomingList[i]
    return upcomingList.length > 0 ? upcomingList[0] : null
  }

  readonly property var notice: M.noticeFor(events, now)
  readonly property bool active: notice !== null
  readonly property string icon: "󰃭"
  readonly property string label: next ? next.title : "Calendar"
  readonly property string detail: {
    if (next) return M.whenWords(next, now)
    // No account is not a fault: it is still a calendar, so say what day it is.
    if (needsSignIn) return M.dayLine(now)
    if (status === "loading") return "Loading"
    if (!loaded) return status === "offline" ? "Offline" : "Could not load"
    return "Nothing coming up"
  }

  // ---- the page's view ---------------------------------------------------
  // Kept here so it survives the page being closed and reopened.

  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()
  property string selectedDay: M.dayKey(new Date())
  property string openEventId: ""
  readonly property string todayKey: M.dayKey(new Date(now))
  readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek % 7
  readonly property var grid: M.monthGrid(viewYear, viewMonth, firstDayOfWeek)

  // month key -> { events, at }
  property var months: ({})
  readonly property string viewKey: viewYear + "-" + viewMonth
  readonly property var viewEvents: M.forAccount(months[viewKey] ? months[viewKey].events : events, shownAccount)
  readonly property var viewIndex: M.indexByDay(viewEvents)

  function shiftMonth(by) {
    var d = new Date(viewYear, viewMonth + by, 1)
    viewYear = d.getFullYear()
    viewMonth = d.getMonth()
    fetchMonth()
  }

  function goToday() {
    var d = new Date()
    viewYear = d.getFullYear()
    viewMonth = d.getMonth()
    selectedDay = M.dayKey(d)
    fetchMonth()
  }

  function selectDay(key) {
    selectedDay = key
    openEventId = ""
  }

  function jumpTo(key) {
    var p = String(key).split("-")
    viewYear = Number(p[0])
    viewMonth = Number(p[1]) - 1
    selectedDay = key
    openEventId = ""
  }

  function openLink(url) {
    url = String(url || "")
    if (url.indexOf("https://") === 0) Qt.openUrlExternally(url)
  }

  // ---- reading Google ----------------------------------------------------

  function refresh() {
    sync()
    fetchMonth(true)
  }

  function sync() {
    if (syncProc.running) return
    var day = new Date(now)
    var from = new Date(day.getFullYear(), day.getMonth(), day.getDate() - 1)
    var to = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 43)
    syncProc.command = [helper, "range", M.dayKey(from), M.dayKey(to)]
    syncProc.running = true
  }

  // The page calls this when it shows. A month read in the last refresh period
  // is good enough, and the one on screen is re-read with every refresh.
  function fetchMonth(force) {
    var cached = months[viewKey]
    if (!force && cached && now - cached.at < refreshMs) return
    if (monthProc.running) {
      monthPending = true
      return
    }
    monthPending = false
    var cells = M.monthGrid(viewYear, viewMonth, firstDayOfWeek)
    var last = cells[cells.length - 1].key.split("-")
    var after = new Date(Number(last[0]), Number(last[1]) - 1, Number(last[2]) + 1)
    monthProc.key = viewKey
    monthProc.command = [helper, "range", cells[0].key, M.dayKey(after)]
    monthProc.running = true
  }
  property bool monthPending: false

  // An empty read is not "nothing changed": it is no answer, so it counts as a
  // failure rather than leaving the last good status on screen.
  function parseAnswer(raw) {
    try {
      var answer = JSON.parse(String(raw || "").trim())
      if (answer && typeof answer === "object") return answer
    } catch (e) {
    }
    return { ok: false, code: "error", error: "The calendar helper gave no answer." }
  }

  function noteResult(answer) {
    var google = answer.ok ? (answer.google || { ok: true }) : answer
    status = google.ok ? "ok" : String(google.code || "error")
    message = google.ok ? "" : String(google.error || "")
  }

  Process {
    id: syncProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var answer = s.parseAnswer(text)
        s.noteResult(answer)
        if (!answer.ok) return
        s.events = M.mergeEvents(s.events, answer)
        s.calendars = M.mergeCalendars(s.calendars, answer)
        // Every account's state, failed ones included, so their chips can say why.
        if ((answer.accounts || []).length > 0) s.accounts = answer.accounts
        if (answer.google && answer.google.ok) {
          s.account = String(answer.account || "")
          s.lastSync = Date.now()
        }
        s.loaded = true
        s.checkReminders()
      }
    }
  }

  Process {
    id: monthProc
    property string key: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var answer = s.parseAnswer(text)
        s.noteResult(answer)
        if (answer.ok) {
          var next = Object.assign({}, s.months)
          var known = s.months[monthProc.key]
          next[monthProc.key] = { events: M.mergeEvents(known ? known.events : s.events, answer), at: Date.now() }
          s.months = next
        }
        if (s.monthPending) monthRetry.restart()
      }
    }
  }

  // The collector finishes just before the process counts as stopped.
  Timer {
    id: monthRetry
    interval: 50
    onTriggered: s.fetchMonth()
  }

  // ---- changing events ---------------------------------------------------

  property bool creating: false
  property string createError: ""
  signal created(string day)
  readonly property var writableCalendars: M.forAccount(calendars, shownAccount)
    .filter(function(c) { return c.writable === true })

  // The request goes over stdin, so event text is never in a process list.
  function runChange(action, request) {
    if (createProc.running) return
    createProc.request = request
    createProc.command = [helper, action]
    createError = ""
    creating = true
    createProc.stdinEnabled = true
    createProc.running = true
  }

  function createEvent(request) { runChange("create", request) }
  function updateEvent(request) { runChange("update", request) }
  function deleteEvent(id) { runChange("delete", { id: id }) }

  Process {
    id: createProc
    property var request: null
    onStarted: {
      write(JSON.stringify(request))
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var answer = s.parseAnswer(text)
        s.creating = false
        if (!answer.ok) {
          s.createError = String(answer.error || "That did not work.")
          return
        }
        if (createProc.request.date) s.jumpTo(createProc.request.date)
        s.openEventId = ""
        s.created(String(createProc.request.date || ""))
        createdSync.restart()
      }
    }
  }

  // The collector finishes just before the process counts as stopped, and a
  // sync already running would miss the new event, so give both a moment.
  Timer {
    id: createdSync
    interval: 300
    onTriggered: {
      if (syncProc.running) restart()
      else s.refresh()
    }
  }

  // ---- reminders ---------------------------------------------------------
  // What has fired is kept on disk, or every shell restart would repeat them.
  // Only event ids and times go in this file, never an event's text.

  property var fired: ({})
  property bool firedReady: false

  FileView {
    id: firedFile
    path: s.stateDir + "/calendar-fired.json"
    printErrors: false
    onLoaded: {
      try {
        s.fired = JSON.parse(text()) || ({})
      } catch (e) {
        s.fired = ({})
      }
      s.firedReady = true
      s.checkReminders()
    }
    onLoadFailed: {
      s.firedReady = true
      s.checkReminders()
    }
  }

  function checkReminders() {
    if (!firedReady || !loaded) return
    var due = M.dueReminders(events, Date.now(), fired)
    if (due.mark.length === 0) return
    var kept = M.pruneFired(fired, Date.now())
    for (var i = 0; i < due.mark.length; i++) kept[due.mark[i]] = Date.now()
    fired = kept
    firedFile.setText(JSON.stringify(kept))
    for (var j = 0; j < due.fire.length; j++) notify(due.fire[j])
  }

  // No shell, and `--` so a title starting with a dash stays a title.
  function notify(e) {
    Quickshell.execDetached(["notify-send", "-a", "Calendar", "--",
      String(e.title), M.reminderBody(e, Date.now())])
  }

  // ---- clocks ------------------------------------------------------------

  // A gap in this tick is the laptop waking. Read straight away, because
  // whatever is on screen is as old as the sleep was.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      var woke = Date.now() - s.now > 120000
      s.now = Date.now()
      if (woke) s.sync()
      s.checkReminders()
    }
  }

  Timer {
    interval: s.refreshMs
    running: true
    repeat: true
    onTriggered: s.sync()
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", s.stateDir]
    onExited: s.sync()
  }

  Component.onCompleted: mkdirProc.running = true
}
