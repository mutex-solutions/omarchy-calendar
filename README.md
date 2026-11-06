# Calendar

Google Calendar for Omarchy. A section inside
[Deck](https://github.com/mutex-solutions/omarchy-deck), or a bar widget. The stock
clock stays as it is.

- **Tile:** what is next. At 2x2 or 4x1 it lists what is coming up.
- **Deck's strip:** a notice from 15 minutes before a timed event until it ends.
- **Reminders:** system notifications from each event's own Google reminders, with
  the panel closed.
- **Page:** tap the tile for a full month, the chosen day, what is coming up, and
  New to add an event.

Edit and delete in Google for now: every event has an Open in Google button.

## Sign in

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
  "span": 2, "rows": 2 }
```

`install-bundle.sh` in the Deck repo does this for every section at once. Deck 0.10.2
or later gives the page its full width; older versions show the narrow layout.

Run the Deck section or the bar widget, not both: each would send its own reminders.

## For agents and scripts

The panel and an agent share one helper, so an agent needs nothing else:

```bash
H=~/.config/omarchy/plugins/mutex-solutions.calendar/scripts/calendar-google
$H range 2026-11-06 2026-11-13
echo '{"title":"Dentist","date":"2026-11-20","start":"09:30","end":"10:15"}' | $H create
```

Only `title` and `date` are required. No `start` makes it all-day, no `end` makes it an
hour. `location` and `calendarId` are optional. The panel picks an event up at its next
refresh, within 5 minutes.

## How it is built

| File | Role |
| --- | --- |
| `scripts/calendar-google` | talks to Google; prints one JSON object |
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
H=~/.config/omarchy/plugins/mutex-solutions.calendar/scripts/calendar-google
$H range "$(date +%F)" "$(date -d +7days +%F)" | jq '{ok, n: (.events | length)}'
```

Tests: `bash scripts/validate.sh`.

## Licence

MIT. `scripts/calendar-google` is derived from
[crmne/omarchy-calendar](https://github.com/crmne/omarchy-calendar); see
`THIRD_PARTY_NOTICES.md`.
