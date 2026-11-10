// node tests/model.test.js  (TZ is set by scripts/validate.sh)
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "../Model.js"), "utf8").replace(/^\.pragma library\n/, "")
const M = {}; vm.runInNewContext(src, M)
const at = (y, mo, d, h = 0, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime()
const ev = (o) => Object.assign({ id: "c/1", title: "Standup", allDay: false, declined: false, reminders: [] }, o)
const now = at(2026, 11, 6, 10, 0)
let n = 0; const t = (name, fn) => { fn(); n++ }

t("grid is six weeks, starts on the chosen weekday", () => {
  const g = M.monthGrid(2026, 10, 1)                       // November 2026, Monday first
  assert.equal(g.length, 42)
  assert.equal(g[0].key, "2026-10-26")
  assert.equal(g[6].key, "2026-11-01"); assert.equal(g[6].inMonth, true)
  assert.equal(M.monthGrid(2026, 10, 0)[0].key, "2026-11-01")  // Sunday first
})
t("grid survives a clock change", () => {
  const keys = M.monthGrid(2026, 2, 1).map(c => c.key)      // March, DST in many zones
  assert.equal(new Set(keys).size, 42)
})
t("every 2026 grid is unique, including midnight-DST zones", () => {
  for (let month = 0; month < 12; month++) {
    const grid = M.monthGrid(2026, month, 1)
    assert.equal(new Set(grid.map(c => c.key)).size, 42, `month ${month + 1}`)
    assert.equal(grid.filter(c => c.inMonth).length, new Date(Date.UTC(2026, month + 1, 0)).getUTCDate())
  }
  assert.equal(M.shiftDayKey("2026-12-31", 1), "2027-01-01")
  assert.equal(M.shiftDayKey("2024-02-28", 1), "2024-02-29")
})
t("a multi-day event is on each day; midnight end is not the next day", () => {
  const i = M.indexByDay([ev({ allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 8) })])
  assert.deepEqual(Object.keys(i), ["2026-11-06", "2026-11-07"])
})
t("all-day sorts first within a day", () => {
  const i = M.indexByDay([ev({ id: "a", start: at(2026, 11, 6, 9), end: at(2026, 11, 6, 10) }),
                          ev({ id: "b", allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 7) })])
  assert.equal(i["2026-11-06"][0].id, "b")
})
t("upcoming drops finished and declined, all-day after timed today", () => {
  const list = M.upcoming([
    ev({ id: "past", start: at(2026, 11, 6, 8), end: at(2026, 11, 6, 9) }),
    ev({ id: "no", declined: true, start: at(2026, 11, 6, 11), end: at(2026, 11, 6, 12) }),
    ev({ id: "bday", allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 7) }),
    ev({ id: "next", start: at(2026, 11, 6, 15), end: at(2026, 11, 6, 16) }),
  ], now)
  assert.deepEqual(list.map(e => e.id), ["next", "bday"])
})
t("when words", () => {
  assert.equal(M.whenWords(ev({ start: now + 12 * 60000, end: now + 3600000 }), now), "in 12m")
  assert.equal(M.whenWords(ev({ start: now + 90 * 60000, end: now + 2 * 3600000 }), now), "in 1h 30m")
  assert.equal(M.whenWords(ev({ start: now - 60000, end: at(2026, 11, 6, 11) }), now), "Now, until 11:00")
  assert.equal(M.whenWords(ev({ start: at(2026, 11, 7, 9), end: at(2026, 11, 7, 10) }), now), "Tomorrow 09:00")
  assert.equal(M.whenWords(ev({ allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 7) }), now), "Today, all day")
})
t("notice only near a timed event, and never urgent", () => {
  assert.equal(M.noticeFor([ev({ start: now + 16 * 60000, end: now + 3600000 })], now), null)
  const soon = M.noticeFor([ev({ start: now + 10 * 60000, end: now + 3600000 })], now)
  assert.equal(soon.severity, "info"); assert.equal(soon.detail, "in 10m")
  assert.equal(M.noticeFor([ev({ allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 7) })], now), null)
})
t("a reminder fires once", () => {
  const e = ev({ start: now + 5 * 60000, end: now + 3600000, reminders: [now - 1000] })
  const first = M.dueReminders([e], now, {})
  assert.equal(first.fire.length, 1)
  const fired = {}; first.mark.forEach(k => fired[k] = now)
  assert.equal(M.dueReminders([e], now + 30000, fired).fire.length, 0)
})
t("not due yet does not fire or mark", () => {
  const r = M.dueReminders([ev({ start: now + 3600000, end: now + 7200000, reminders: [now + 60000] })], now, {})
  assert.equal(r.fire.length, 0); assert.equal(r.mark.length, 0)
})
t("slept through two reminders: one notification, both marked", () => {
  const r = M.dueReminders([ev({ start: now + 60000, end: now + 3600000, reminders: [now - 600000, now - 60000] })], now, {})
  assert.equal(r.fire.length, 1); assert.equal(r.mark.length, 3)  // both, plus the 10-minute one
})
t("woke long after it began: marked, silent", () => {
  const r = M.dueReminders([ev({ start: now - 3600000, end: now + 3600000, reminders: [now - 4000000] })], now, {})
  assert.equal(r.fire.length, 0); assert.equal(r.mark.length, 2)  // its own, plus the 10-minute one
})
t("declined never notifies", () => {
  const r = M.dueReminders([ev({ declined: true, start: now + 60000, end: now + 3600000, reminders: [now - 1000] })], now, {})
  assert.equal(r.fire.length, 0)
})
t("event text is escaped for the notification body", () => {
  assert.ok(M.reminderBody(ev({ start: now + 60000, end: now + 3600000, location: "<b>A&B</b>" }), now).includes("&lt;b&gt;A&amp;B&lt;/b&gt;"))
})
t("prune keeps a week", () => {
  assert.deepEqual(Object.keys(M.pruneFired({ old: now - 8 * 86400000, recent: now - 86400000 }, now)), ["recent"])
})
t("new event defaults are useful today, tomorrow, and near midnight", () => {
  assert.deepEqual(M.defaultEventTimes("2026-11-06", now), { start: "11:00", end: "12:00" })
  assert.deepEqual(M.defaultEventTimes("2026-11-07", now), { start: "09:00", end: "10:00" })
  assert.deepEqual(M.defaultEventTimes("2026-11-06", at(2026, 11, 6, 22, 30)), { start: "23:00", end: "" })
  assert.deepEqual(M.defaultEventTimes("2026-11-06", at(2026, 11, 6, 23, 15)), { start: "23:30", end: "" })
})
t("new event request", () => {
  assert.equal(M.newEventRequest(" ", "2026-11-20", true).error, "Give the event a title.")
  assert.ok(M.newEventRequest("x", "soon", true).error)
  assert.ok(M.newEventRequest("x", "2026-11-20", false, "9am", "").error)
  const r = M.newEventRequest(" Dentist ", "2026-11-20", false, "9:30", "", "Clinic", "c@x")
  assert.deepEqual(JSON.parse(JSON.stringify(r)), { title: "Dentist", date: "2026-11-20", location: "Clinic", calendarId: "c@x", start: "09:30" })
  assert.equal(M.newEventRequest("x", "2026-11-20", true, "", "").start, undefined)
})
t("day line", () => { assert.equal(M.dayLine(now), "Fri 6 November") })
t("a failed Google read keeps Google's events and refreshes local", () => {
  const old = [ev({ id: "g", start: 5, end: 6 }), ev({ id: "l", local: true, start: 1, end: 2 })]
  const fresh = [ev({ id: "l2", local: true, start: 3, end: 4 })]
  assert.deepEqual(M.mergeEvents(old, { events: fresh, google: { ok: false } }).map(e => e.id), ["l2", "g"])
  assert.deepEqual(M.mergeEvents(old, { events: fresh, google: { ok: true } }).map(e => e.id), ["l2"])
  const cals = M.mergeCalendars([{ id: "me" }, { id: "local" }], { calendars: [{ id: "local" }], google: { ok: false } })
  assert.deepEqual(cals.map(c => c.id), ["me", "local"])
})
t("accounts keep their colour by position, and filter cleanly", () => {
  const accounts = [{ key: "default", email: "me@x", ok: true }, { key: "jan", email: "", ok: false, error: "Sign in again." }]
  assert.equal(M.accountColor(accounts, "default"), M.ACCOUNT_COLORS[0])
  assert.equal(M.accountColor(accounts, "jan"), M.ACCOUNT_COLORS[1])
  assert.equal(M.accountColor(accounts, "gone"), "")
  assert.equal(M.accountLabel(accounts, "default"), "me@x")
  assert.equal(M.accountLabel(accounts, "jan"), "jan")
  const list = [ev({ id: "a", account: "default" }), ev({ id: "b", account: "jan" })]
  assert.deepEqual(M.forAccount(list, "jan").map(e => e.id), ["b"])
  assert.equal(M.forAccount(list, "").length, 2)
  assert.deepEqual(M.forAccount(list.concat([ev({ id: "l", account: "local" })]), "jan").map(e => e.id), ["b", "l"])
  assert.equal(M.effectiveAccount(accounts, "jan"), "jan")
  assert.equal(M.effectiveAccount(accounts, "gone"), "")
  assert.equal(M.accountTrouble(accounts), "jan: Sign in again.")
  assert.equal(M.accountTrouble([accounts[0]]), "")
})
t("a later all-day event shows its day in lists", () => {
  const later = ev({ allDay: true, start: at(2026, 11, 24), end: at(2026, 11, 25) })
  assert.equal(M.timeColumn(later, now), "Tue 24 Nov")
  assert.equal(M.shortColumn(later, now), "Tue 24")
  const today = ev({ allDay: true, start: at(2026, 11, 6), end: at(2026, 11, 7) })
  assert.equal(M.timeColumn(today, now), "All day")
  assert.equal(M.shortColumn(today, now), "All day")
  assert.equal(M.shortColumn(ev({ allDay: true, start: at(2026, 11, 7), end: at(2026, 11, 8) }), now), "Tmrw")
})
t("every timed event reminds 10 minutes before, once", () => {
  const e = ev({ start: now + 20 * 60000, end: now + 3600000, reminders: [] })
  assert.deepEqual(M.reminderTimes(e), [now + 10 * 60000])
  assert.deepEqual(M.reminderTimes(ev({ start: now, end: now + 1, reminders: [now - 600000] })), [now - 600000])
  assert.deepEqual(M.reminderTimes(ev({ start: now, end: now + 1, reminders: [now - 3600000] })), [now - 3600000, now - 600000])
  assert.deepEqual(M.reminderTimes(ev({ allDay: true, start: now, end: now + 1, reminders: [] })), [])
  assert.equal(M.dueReminders([e], now + 10 * 60000, {}).fire.length, 1)
  assert.equal(M.dueReminders([e], now + 9 * 60000, {}).fire.length, 0)
})
t("tile column carries the time", () => {
  assert.equal(M.shortColumn(ev({ start: at(2026, 11, 7, 9), end: at(2026, 11, 7, 10) }), now), "Tmrw 09:00")
  assert.equal(M.shortColumn(ev({ start: at(2026, 11, 6, 15), end: at(2026, 11, 6, 16) }), now), "15:00")
  assert.equal(M.shortColumn(ev({ start: at(2026, 11, 10, 14), end: at(2026, 11, 10, 15) }), now), "Tue 14:00")
})
t("ISO weeks include year boundaries and use Thursday for either week start", () => {
  assert.equal(M.isoWeekForKey("2021-01-01"), 53)
  assert.equal(M.isoWeekForKey("2026-01-01"), 1)
  assert.equal(M.isoWeekForKey("2027-01-01"), 53)
  const monday = M.monthGrid(2026, 0, 1)
  const sunday = M.monthGrid(2026, 0, 0)
  assert.equal(M.isoWeekForRow(monday, 0), 1)
  assert.equal(M.isoWeekForRow(sunday, 0), 1)
  assert.equal(M.isoWeekForRow(monday, 5), M.isoWeekForKey(monday[41].key))
})
t("year progress is whole days completed and handles leap years", () => {
  assert.equal(M.yearProgressPercent(at(2026, 1, 1)), 0)
  assert.equal(M.yearProgressPercent(at(2026, 12, 31)), 100)
  assert.equal(M.yearProgressPercent(at(2024, 12, 31)), 100)
  assert.ok(M.yearProgress(at(2024, 7, 2)) > M.yearProgress(at(2023, 7, 2)))
})
t("upcoming is grouped by day, including an all-day event already underway", () => {
  const groups = M.upcomingGroups([
    ev({ id: "later", start: at(2026, 11, 7, 9), end: at(2026, 11, 7, 10) }),
    ev({ id: "next", start: at(2026, 11, 6, 15), end: at(2026, 11, 6, 16) }),
    ev({ id: "span", allDay: true, start: at(2026, 11, 5), end: at(2026, 11, 8) }),
  ], now, 6)
  assert.deepEqual(groups.map(g => g.label), ["Today · 6 Nov", "Tomorrow · 7 Nov"])
  assert.deepEqual(groups.map(g => g.events.map(e => e.id)), [["next", "span"], ["later"]])
  assert.equal(M.upcomingGroups([ev({ id: "a", start: now, end: now + 1 }), ev({ id: "b", start: now, end: now + 1 })], now, 1)[0].events.length, 1)
})
console.log("model ok: " + n + " tests")
