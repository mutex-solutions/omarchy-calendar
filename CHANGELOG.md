# Changelog

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
