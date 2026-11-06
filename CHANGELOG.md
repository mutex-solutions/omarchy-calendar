# Changelog

## 0.2.0

- **Local events.** Add, edit and delete events with no account, from the page or
  `scripts/calendar`. They remind and show like any other. Google stays optional, and
  losing it no longer hides what is already known.
- The helper is now `scripts/calendar`.

## 0.1.2

- The calendar shows without a Google account. Connecting moved to Settings in the
  page, and New goes there until an account is connected.

## 0.1.1

- Holding the large tile shows Deck's progress hairline, like every other tile (needs Deck 0.10.3).
- Deck installs it as a 4x1 tile with the next two events. It was 2x2 and took up a lot of the grid.
- The sign-in steps use the usual card width.

## 0.1.0

- Upcoming events on the tile, and a notice in Deck's strip near a timed event.
- Reminders as system notifications with the panel closed, once each across
  shell restarts and sleep.
- A full page: month grid, the chosen day, what is coming up.
- New events from the page, or from `scripts/calendar-google create` for agents.
- Standalone bar widget.
