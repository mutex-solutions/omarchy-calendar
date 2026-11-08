# Calendar

Google Calendar for Omarchy. A section inside
[Deck](https://github.com/mutex-solutions/omarchy-deck), or a bar widget. The stock
clock stays as it is.

- **Tile:** a 4x1 tile lists the next two events, a 2x2 tile more. Half-size shows just the next.
- **Deck's strip:** a notice from 15 minutes before a timed event until it ends.
- **Reminders:** a notification with a sound 10 minutes before every timed event, plus
  any reminders the event has of its own, with the panel closed. Silent under Do Not
  Disturb.
- **Page:** tap the tile for a full month, the chosen day, what is coming up, and
  New to add an event. **Compact** puts a small month above the day's events at
  Deck's usual width; `󰊓` goes back. The choice is remembered.
- **Local events:** work with no account, and can be edited and deleted from the page.
  Google events are added here and changed in Google, through Open in Google.

## Sign in

This is optional: without it you have the month and local events. The steps below are
also under Settings in the page.

Reading and adding go through [gws](https://github.com/googleworkspace/cli), which
needs an OAuth client from your own Google Cloud project.

```bash
sudo pacman -S googleworkspace-cli
```

Then one of:

- **You have a Desktop OAuth client:** save its JSON as
  `~/.config/gws/client_secret.json`, and enable the Calendar API on that project.
- **You do not:** run `gws auth setup`, which needs the `gcloud` CLI, or follow gws's
  manual setup.

```bash
gws auth login -s calendar
```

### More than one account

The first account is gws's own sign-in. Add each further account as a gws sign-in
in a directory of its own under `~/.config/gws-accounts/` (the directory name is
the account's key):

```bash
GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-accounts/work gws auth login -s calendar
```

Settings in the page lists every account and has this command ready to copy (rename
`work`). The page then shows a row of account chips: **All**, or one account. In All,
events are coloured by account; with one chosen, by Google's calendar colours.
The tile follows the choice; reminders and the notice cover every account. To
remove an account, delete its directory.

On Google's consent screen Calendar is a **checkbox**: left unticked, the sign-in
still succeeds but can read nothing, and the page says to sign in again.

**Publish the consent screen to production.** Google expires refresh tokens after 7
days while an app is in Testing, and Calendar would ask you to sign in again every
week. For read-only, sign in with `--readonly` as well; New then reports that the
sign-in cannot write.

## Inside Deck

From Deck's Sections page, or:

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-calendar
```

```json
{ "id": "calendar", "title": "Calendar",
  "file": "/home/YOU/.config/omarchy/plugins/mutex-solutions.calendar/deck/Section.qml",
  "page": "/home/YOU/.config/omarchy/plugins/mutex-solutions.calendar/deck/Page.qml",
  "span": 4, "rows": 1 }
```

`install-bundle.sh` in the Deck repo does this for every section at once. Deck 0.10.2
or later gives the page its full width; older versions show the narrow layout.

Run the Deck section or the bar widget, not both: each would send its own reminders.

## For agents and scripts

The panel and an agent share one helper, so an agent needs nothing else:

```bash
H=~/.config/omarchy/plugins/mutex-solutions.calendar/scripts/calendar
$H range 2026-11-06 2026-11-13
echo '{"title":"Dentist","date":"2026-11-20","start":"09:30","end":"10:15"}' | $H create
echo '{"id":"local/abc","title":"Dentist","date":"2026-11-21","start":"10:00"}' | $H update
echo '{"id":"local/abc"}' | $H delete
```

Only `title` and `date` are required. No `start` makes it all-day, no `end` makes it an
hour. With neither `calendarId` nor `account` it stays local; `"calendarId":"primary"`
sends it to Google, and `account` (a key: `default` or a directory name under
`~/.config/gws-accounts/`) picks which account, else the first. A timed local event
reminds 10 minutes before unless `"remind"` gives other minutes. `update` and `delete` are
for local events only. The panel picks changes up at its next refresh, within 5 minutes.

Local events live in `~/.local/share/deck/calendar-events.json`. If that file is damaged,
the helper reports it and refuses to write, so nothing overwrites it.

## How it is built

| File | Role |
| --- | --- |
| `scripts/calendar` | local events and Google; prints one JSON object |
| `Model.js` | dates, ordering, reminders, tested under node |
| `State.qml` | the single state object, the polling and the reminders |
| `deck/Section.qml` | Deck adapter and the list tiles |
| `deck/Page.qml` | the month, the agenda and the form |
| `Panel.qml` | the standalone bar widget |

What has fired is kept in `~/.local/state/deck/calendar-fired.json` (ids and times, no
event text), so a shell restart does not repeat reminders. A reminder missed while the
laptop slept fires on waking if its event has not been running for more than 5 minutes,
and several missed reminders of one event become one notification.

## Security

The helper was reviewed line by line when it was cut down from OmaCal:

- It contacts only `oauth2.googleapis.com` and `www.googleapis.com/calendar/v3`.
- It gets the sign-in from `gws auth export --unmasked` over a pipe, or from gws's
  `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE` and `credentials.json`. The token stays in that
  process's memory and is never written or printed.
- OmaCal's test overrides for the API address are removed; the tests patch the module.
- Errors never carry Google's response or event text. Event text reaches the helper on
  stdin, reaches `notify-send` without a shell, and is escaped for the notification body.
- Only `https://` links are ever opened.
- New events have no guests and use `sendUpdates=none`, so nobody is emailed.

Omarchy plugins run unsandboxed, so this is what protects the token, and only that.

## Re-create from scratch

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-calendar
# register it as above, or use Deck's Sections page
# sign in as above
omarchy restart shell
H=~/.config/omarchy/plugins/mutex-solutions.calendar/scripts/calendar
$H range "$(date +%F)" "$(date -d +7days +%F)" | jq '{ok, n: (.events | length)}'
```

Tests: `bash scripts/validate.sh`.

## Licence

MIT. The Google half of `scripts/calendar` is derived from
[crmne/omarchy-calendar](https://github.com/crmne/omarchy-calendar); see
`THIRD_PARTY_NOTICES.md`.
