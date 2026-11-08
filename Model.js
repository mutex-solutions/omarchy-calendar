.pragma library

// Pure date and event logic, so it can be tested under plain node. Events come
// from scripts/calendar: `start` and `end` are epoch milliseconds, and an
// all-day event runs from local midnight to the local midnight after its last day.

var MINUTE = 60000
var SOON_MINUTES = 15
// A reminder still fires this long after its event began, so a laptop waking
// into a meeting says so. After that it is history and is dropped silently.
var LATE_GRACE = 5 * MINUTE
// Every timed event reminds this long before it starts, on top of its own
// reminders, the way calendar apps do. Google's default is often none.
var DEFAULT_LEAD = 10 * MINUTE

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
              "August", "September", "October", "November", "December"]
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// One colour per account, in the order the helper lists them. Fixed rather than
// taken from the theme, so an account keeps its colour across theme changes;
// mid-tone, so it reads on a light or a dark background.
var ACCOUNT_COLORS = ["#bd93f9", "#ff79c6", "#50fa7b", "#ffb86c", "#8be9fd", "#f1fa8c"]

function accountColor(accounts, key) {
  for (var i = 0; i < (accounts || []).length; i++)
    if (accounts[i].key === key) return ACCOUNT_COLORS[i % ACCOUNT_COLORS.length]
  return ""
}

function accountLabel(accounts, key) {
  for (var i = 0; i < (accounts || []).length; i++)
    if (accounts[i].key === key) return accounts[i].email || accounts[i].key
  return String(key || "")
}

// "" is every account. A key that no longer exists (an account signed out)
// also means every account, so the page never shows an empty filter.
function effectiveAccount(accounts, key) {
  if (!key) return ""
  for (var i = 0; i < (accounts || []).length; i++)
    if (accounts[i].key === key) return key
  return ""
}

// Events or calendars of one account; "" keeps them all. Local ones belong to
// no Google account, so every filter keeps them.
function forAccount(list, key) {
  if (!key) return list
  return list.filter(function(x) { return x.account === key || x.account === "local" })
}

// What the page says about accounts that could not be read, or "".
function accountTrouble(accounts) {
  var bad = (accounts || []).filter(function(a) { return !a.ok })
  if (bad.length === 0) return ""
  return bad.map(function(a) { return a.key + ": " + (a.error || "could not be read") }).join("; ")
}

function pad(n) { return (n < 10 ? "0" : "") + n }

function dayKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function clock(ms) {
  var d = new Date(ms)
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function startOfDay(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

// Calendar days apart, which milliseconds cannot say across a clock change.
function daysBetween(fromMs, toMs) {
  return Math.round((startOfDay(toMs) - startOfDay(fromMs)) / (24 * 60 * MINUTE))
}

function monthTitle(year, month) { return MONTHS[month] + " " + year }

// Always six weeks, so the page does not change height between months.
function monthGrid(year, month, firstDayOfWeek) {
  var first = new Date(year, month, 1)
  var lead = (first.getDay() - (firstDayOfWeek || 0) + 7) % 7
  var cells = []
  for (var i = 0; i < 42; i++) {
    var d = new Date(year, month, 1 - lead + i)
    cells.push({ key: dayKey(d), day: d.getDate(), inMonth: d.getMonth() === month })
  }
  return cells
}

function weekdayLabels(firstDayOfWeek) {
  var out = []
  for (var i = 0; i < 7; i++) out.push(DAYS[((firstDayOfWeek || 0) + i) % 7])
  return out
}

// day key -> events on that day. A multi-day event is on every day it touches.
// An event ending exactly at midnight is not on the day after.
function indexByDay(events) {
  var out = {}
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var last = Math.max(e.start, e.end - 1)
    var d = new Date(e.start)
    d = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    for (var guard = 0; d.getTime() <= last && guard < 366; guard++) {
      var key = dayKey(d)
      if (!out[key]) out[key] = []
      out[key].push(e)
      d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
    }
  }
  for (var k in out) out[k].sort(byDayOrder)
  return out
}

function byDayOrder(a, b) {
  if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
  return a.start - b.start || String(a.title).localeCompare(String(b.title))
}

// Not over, soonest first. Declined events are not coming up. All-day events
// sort after what has a time today, because a birthday is not the next thing.
function upcoming(events, now) {
  var today = startOfDay(now)
  return events.filter(function(e) { return e.end > now && !e.declined })
    .sort(function(a, b) {
      var sa = a.allDay ? Math.max(a.start, today) + (24 * 60 * MINUTE - 1) : a.start
      var sb = b.allDay ? Math.max(b.start, today) + (24 * 60 * MINUTE - 1) : b.start
      return sa - sb
    })
}

function dayWord(ms, now) {
  var apart = daysBetween(now, ms)
  if (apart === 0) return "Today"
  if (apart === 1) return "Tomorrow"
  var d = new Date(ms)
  if (apart > 1 && apart < 7) return DAYS[d.getDay()]
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3)
}

function dayLine(ms) {
  var d = new Date(ms)
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

function untilWords(ms, now) {
  var minutes = Math.max(1, Math.ceil((ms - now) / MINUTE))
  if (minutes < 60) return "in " + minutes + "m"
  var hours = Math.floor(minutes / 60)
  return "in " + hours + "h" + (minutes % 60 ? " " + (minutes % 60) + "m" : "")
}

// The one line under an event's title on a tile.
function whenWords(e, now) {
  if (e.allDay) return e.start <= now ? "Today, all day" : dayWord(e.start, now) + ", all day"
  if (e.start <= now) return "Now, until " + clock(e.end)
  if (e.start - now < 6 * 60 * MINUTE && daysBetween(now, e.start) === 0) return untilWords(e.start, now)
  return dayWord(e.start, now) + " " + clock(e.start)
}

// The time column in a list.
function timeColumn(e, now) {
  // A later all-day event needs its day, not just "All day".
  if (e.allDay) return e.start <= now ? "All day" : dayWord(e.start, now)
  return daysBetween(now, e.start) === 0 ? clock(e.start) : dayWord(e.start, now)
}

// The same column, narrower, for a tile.
// Day and time, so "Tmrw" alone never leaves you guessing when.
function shortColumn(e, now) {
  var apart = daysBetween(now, e.start)
  if (e.allDay && apart <= 0) return "All day"
  var d = new Date(e.start)
  var day = apart === 1 ? "Tmrw" : DAYS[d.getDay()] + (apart < 7 ? "" : " " + d.getDate())
  if (e.allDay) return day
  return apart === 0 ? clock(e.start) : day + " " + clock(e.start)
}

// What the form sends, or the sentence saying why not. An empty end is an hour.
function newEventRequest(title, date, allDay, start, end, location, calendarId) {
  var t = String(title || "").trim()
  if (t === "") return { error: "Give the event a title." }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "The date must be YYYY-MM-DD." }
  var request = { title: t, date: date, location: String(location || "").trim() }
  if (calendarId) request.calendarId = calendarId
  if (allDay) return request
  if (!/^\d{1,2}:\d{2}$/.test(start)) return { error: "The start must be HH:MM." }
  request.start = pad(Number(start.split(":")[0])) + ":" + start.split(":")[1]
  if (end !== "") {
    if (!/^\d{1,2}:\d{2}$/.test(end)) return { error: "The end must be HH:MM." }
    request.end = pad(Number(end.split(":")[0])) + ":" + end.split(":")[1]
  }
  return request
}

// A failed Google read must not blank what was already known of Google, and a
// helper answer always has the local events fresh. So keep the old Google half.
function mergeEvents(old, answer) {
  var fresh = answer.events || []
  if (answer.google && answer.google.ok) return fresh
  var kept = (old || []).filter(function(e) { return !e.local })
  return kept.concat(fresh).sort(function(a, b) { return a.start - b.start })
}

function mergeCalendars(old, answer) {
  var fresh = answer.calendars || []
  if (answer.google && answer.google.ok) return fresh
  var kept = (old || []).filter(function(c) { return c.id !== "local" })
  return kept.concat(fresh)
}

// Deck's strip: from a quarter of an hour before a timed event until it ends.
// `info`, not `urgent`: an hour-long meeting is not an alarm for an hour.
function noticeFor(events, now) {
  var list = upcoming(events, now)
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (e.allDay) continue
    if (e.start - now > SOON_MINUTES * MINUTE) return null
    return { severity: "info", title: e.title, detail: whenWords(e, now) }
  }
  return null
}

function reminderKey(e, at) { return e.id + "@" + at }

// What to notify about, and what to remember. Several reminders of one event
// due at once (the laptop slept through them) become one notification.
// When an event reminds: its own times, plus DEFAULT_LEAD before a timed one.
function reminderTimes(e) {
  var times = (e.reminders || []).slice()
  if (!e.allDay && times.indexOf(e.start - DEFAULT_LEAD) < 0) times.push(e.start - DEFAULT_LEAD)
  return times.sort(function(a, b) { return a - b })
}

function dueReminders(events, now, fired) {
  var fire = []
  var mark = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var times = reminderTimes(e)
    var due = false
    for (var j = 0; j < times.length; j++) {
      var at = times[j]
      var key = reminderKey(e, at)
      if (at > now || fired[key]) continue
      mark.push(key)
      if (!e.declined && now < e.start + LATE_GRACE) due = true
    }
    if (due) fire.push(e)
  }
  return { fire: fire, mark: mark }
}

// Fired keys are only worth keeping until their reminder could not come round again.
function pruneFired(fired, now) {
  var out = {}
  for (var key in fired) {
    if (now - fired[key] < 7 * 24 * 60 * MINUTE) out[key] = fired[key]
  }
  return out
}

// Notification bodies are markup to the notification server. Event text is not.
function escapeMarkup(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function reminderBody(e, now) {
  var parts = [whenWords(e, now)]
  if (!e.allDay && e.start > now) parts.push(clock(e.start))
  if (e.location) parts.push(e.location)
  return escapeMarkup(parts.join(" · "))
}
