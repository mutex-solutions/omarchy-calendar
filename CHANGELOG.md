# Changelog

## Unreleased

- Custom tile navigation now stays inside the originating Deck panel rather than
  using global IPC, so opening the page cannot jump to another monitor.

- Editing a local event preserves its custom reminder lead when `remind` is
  omitted instead of resetting it to ten minutes.
- Added saved Automatic/Sunday/Monday week starts, an ISO week-number gutter and
  Omarchy's year-progress rail. Preferences live in `calendar-view.json`.
- Upcoming events are grouped by day. New-event times default to the next hour
  today (09:00 on another day), and primary calendar/account labels no longer
  repeat the same address.
- Month grids are generated as civil dates in UTC and validated across five time
  zones, including midnight-DST transitions. Text forms cooperate with Deck's
  keyboard cursor, event text renders plainly, and the UI ships an English
  translation catalog.

## 0.3.3

- **Every timed event reminds 10 minutes before**, on top of its own reminders.
  Google events often had none, so meetings passed without a word.
- **Reminders play a sound**, except under Omarchy's Do Not Disturb.
- The tile's list shows the time with the day (`Tmrw 09:00`), and its column no
  longer cuts off "All day".

## 0.3.2

- **Compact view**, by choice: a small month on top and the day's events below, at
  Deck's usual width. It only appeared before when the screen was too narrow.
  Remembered with the account filter.

## 0.3.1

- A later all-day event in a list shows its day (`Tue 24 Nov`), not just "All day".

## 0.3.0

Merges this laptop's work with 0.2.x from the other device.

- **Local events.** Add, edit and delete events with no account, from the page or
  `scripts/calendar`. They remind and show like any other, and stay visible under
  every account filter.
- The calendar shows without a Google account. Connecting moved to Settings in the
  page, which also lists every account and how to add another.
- One read covers local events and every account; Google failing, even every
  account at once, no longer hides the local ones or what was already known.
- The helper is now `scripts/calendar`.
- Deck installs it as a 4x1 tile with the next two events.
- Holding the large tile shows Deck's progress hairline (needs Deck 0.10.3 or later).

## 0.2.1

- A failed account's chip says "sign in again" only when signing in would
  fix it (`code: signin`); a hiccup at Google (a 5xx on the token endpoint,
  offline) says "unavailable" and clears at the next refresh. Seen on the
  first day: one 5xx read as "sign in again" on a perfectly good account.
- The page asks for its full width through Deck's `preferredWidth` (Deck
  0.10.2), so month and agenda sit side by side.

## 0.2.0

- More than one Google account. Each extra account is a gws sign-in in its own
  directory, `~/.config/gws-accounts/<name>/`; the helper reads them all side by
  side and tags every calendar and event with its account.
- A row of account chips on the page: All, or one account. In All, events are
  coloured by account; with one chosen, by Google's own calendar colours. The
  choice is remembered and the tile follows it. Reminders and Deck's notice keep
  watching every account.
- One account failing (signed out, offline) no longer hides the others: its chip
  says so and the rest stay on screen.
- A calendar shared into two accounts is shown once.
- New events go to the account that owns the chosen calendar (`"account"` in the
  `create` request).

## 0.1.0

- Upcoming events on the tile, and a notice in Deck's strip near a timed event.
- Reminders as system notifications with the panel closed, once each across
  shell restarts and sleep.
- A full page: month grid, the chosen day, what is coming up.
- New events from the page, or from `scripts/calendar-google create` for agents.
- Standalone bar widget.
