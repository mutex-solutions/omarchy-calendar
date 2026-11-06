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
  assert.equal(r.fire.length, 1); assert.equal(r.mark.length, 2)
})
t("woke long after it began: marked, silent", () => {
  const r = M.dueReminders([ev({ start: now - 3600000, end: now + 3600000, reminders: [now - 4000000] })], now, {})
  assert.equal(r.fire.length, 0); assert.equal(r.mark.length, 1)
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
t("new event request", () => {
  assert.equal(M.newEventRequest(" ", "2026-11-20", true).error, "Give the event a title.")
  assert.ok(M.newEventRequest("x", "soon", true).error)
  assert.ok(M.newEventRequest("x", "2026-11-20", false, "9am", "").error)
  const r = M.newEventRequest(" Dentist ", "2026-11-20", false, "9:30", "", "Clinic", "c@x")
  assert.deepEqual(JSON.parse(JSON.stringify(r)), { title: "Dentist", date: "2026-11-20", location: "Clinic", calendarId: "c@x", start: "09:30" })
  assert.equal(M.newEventRequest("x", "2026-11-20", true, "", "").start, undefined)
})
console.log("model ok: " + n + " tests")
