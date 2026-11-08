#!/usr/bin/env python3
"""python3 tests/test_helper.py: the helper against a fake Google on localhost."""
import http.server, importlib.machinery, importlib.util, io, json, os, sys, tempfile, threading, unittest, contextlib

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "calendar")
loader = importlib.machinery.SourceFileLoader("calendar_helper", path)
spec = importlib.util.spec_from_loader("calendar_helper", loader)
cg = importlib.util.module_from_spec(spec)
loader.exec_module(cg)
REAL_ACCOUNT_DIRS = cg.account_dirs

CALS = {"items": [
    {"id": "me@x", "summary": "Me", "primary": True, "selected": True, "accessRole": "owner",
     "backgroundColor": "#123456", "defaultReminders": [{"method": "popup", "minutes": 10}]},
    {"id": "hidden@x", "summary": "No", "selected": False, "accessRole": "owner"},
]}
EVENTS = {"items": [
    {"id": "e1", "summary": "Standup", "start": {"dateTime": "2026-11-06T09:00:00+07:00"},
     "end": {"dateTime": "2026-11-06T09:30:00+07:00"}, "reminders": {"useDefault": True},
     "htmlLink": "https://calendar.google.com/x", "hangoutLink": "https://meet.google.com/x"},
    {"id": "e2", "summary": "Holiday", "start": {"date": "2026-11-07"}, "end": {"date": "2026-11-09"},
     "htmlLink": "javascript:alert(1)"},
    {"id": "e3", "status": "cancelled", "start": {"date": "2026-11-07"}},
    {"id": "e4", "eventType": "workingLocation", "start": {"date": "2026-11-07"}},
    {"id": "e5", "summary": "Declined", "start": {"dateTime": "2026-11-06T10:00:00+07:00"},
     "end": {"dateTime": "2026-11-06T11:00:00+07:00"},
     "attendees": [{"self": True, "responseStatus": "declined"}]},
]}
# A second account, told apart by its access token.
CALS2 = {"items": [
    {"id": "you@y", "summary": "Work", "primary": True, "selected": True, "accessRole": "writer",
     "backgroundColor": "#654321"},
    {"id": "me@x", "summary": "Shared into both", "selected": True, "accessRole": "reader"},
]}
MODE = {"status": 200, "reason": "", "tokens": [], "posts": [], "broken": ""}


class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(raw))); self.end_headers()
        self.wfile.write(raw)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.startswith("/token"):
            refresh = dict(x.split("=") for x in raw.decode().split("&"))["refresh_token"]
            if refresh == MODE["broken"]:
                return self.reply(400, {"error": "invalid_grant"})
            return self.reply(200, {"access_token": "tok" if refresh == "c" else "tok-" + refresh})
        MODE["posts"].append((self.path, json.loads(raw), self.headers.get("Authorization")))
        self.reply(200, {"id": "new1", "htmlLink": "https://calendar.google.com/new1"})
    def do_GET(self):
        MODE["tokens"].append(self.headers.get("Authorization"))
        if MODE["status"] != 200:
            return self.reply(MODE["status"], {"error": {"errors": [{"reason": MODE["reason"]}]}, "leak": "SECRET-TEXT"})
        if "/users/me/calendarList/" in self.path:
            return self.reply(200, {"accessRole": "reader" if "readonly" in self.path else "owner"})
        second = self.headers.get("Authorization") == "Bearer tok-c2"
        self.reply(200, (CALS2 if second else CALS) if "calendarList" in self.path else EVENTS)


class Helper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % cls.server.server_port
        cg.API, cg.TOKEN_URL = base, base + "/token"
        # None is the first account; "/x/work" an extra one in its own directory.
        cg.credentials = lambda d=None: {"client_id": "a", "client_secret": "b",
                                         "refresh_token": "c" if d is None else "c2"}

    def setUp(self):
        MODE.update(status=200, reason="", tokens=[], posts=[])
        self.data = tempfile.TemporaryDirectory()
        os.environ["XDG_DATA_HOME"] = self.data.name
        self.addCleanup(self.data.cleanup)
        MODE.update(status=200, reason="", tokens=[], posts=[], broken="")
        cg.account_dirs = lambda: [None]

    def two_accounts(self):
        cg.account_dirs = lambda: [None, "/x/work"]

    def run_it(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cg.main(["calendar", *args])
        return rc, json.loads(out.getvalue()), out.getvalue()

    def test_reads_only_listed_calendars(self):
        rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual(rc, 0)
        self.assertEqual([c["id"] for c in a["calendars"]], ["me@x", "local"])
        self.assertEqual(a["account"], "me@x")
        self.assertEqual(MODE["tokens"][0], "Bearer tok")

    def test_drops_cancelled_and_working_location(self):
        _, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual({e["title"] for e in a["events"]}, {"Standup", "Holiday", "Declined"})

    def test_event_shape(self):
        _, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        e = {x["title"]: x for x in a["events"]}
        self.assertEqual(e["Standup"]["end"] - e["Standup"]["start"], 1800000)
        self.assertEqual(e["Standup"]["reminders"], [e["Standup"]["start"] - 600000])
        self.assertEqual(e["Standup"]["joinUrl"], "https://meet.google.com/x")
        self.assertTrue(e["Holiday"]["allDay"])
        self.assertTrue(e["Declined"]["declined"])

    def test_only_web_links_survive(self):
        _, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual({x["title"]: x for x in a["events"]}["Holiday"]["url"], "")

    def test_failures_have_a_code_and_never_google_text(self):
        for status, reason, code in [(401, "", "signin"), (403, "insufficientPermissions", "signin"),
                                     (403, "accessNotConfigured", "signin"), (500, "", "error")]:
            MODE.update(status=status, reason=reason)
            rc, a, raw = self.run_it("range", "2026-11-01", "2026-12-01")
            self.assertEqual((rc, a["ok"], a["google"]["ok"], a["google"]["code"]), (0, True, False, code))
            self.assertNotIn("SECRET-TEXT", raw)

    def create(self, request, action="create"):
        out = io.StringIO()
        stdin = sys.stdin
        sys.stdin = io.TextIOWrapper(io.BytesIO(json.dumps(request).encode()))
        try:
            with contextlib.redirect_stdout(out):
                rc = cg.main(["calendar", action])
        finally:
            sys.stdin = stdin
        return rc, json.loads(out.getvalue())

    def test_create_timed(self):
        rc, a = self.create({"title": " Dentist ", "date": "2026-11-20", "start": "09:30", "end": "10:15",
                             "location": "Clinic", "calendarId": "primary"})
        self.assertEqual((rc, a["ok"], a["id"]), (0, True, "new1"))
        path, body, _ = MODE["posts"][0]
        self.assertIn("/calendars/primary/events", path)
        self.assertIn("sendUpdates=none", path)
        self.assertEqual(body["summary"], "Dentist")
        self.assertTrue(body["start"]["dateTime"].startswith("2026-11-20T09:30:00"))
        self.assertTrue(body["end"]["dateTime"].startswith("2026-11-20T10:15:00"))
        self.assertNotIn("attendees", body)

    def test_create_defaults(self):
        self.create({"title": "One hour", "date": "2026-11-20", "start": "23:30", "calendarId": "primary"})
        self.assertTrue(MODE["posts"][0][1]["end"]["dateTime"].startswith("2026-11-21T00:30:00"))
        MODE["posts"].clear()
        self.create({"title": "Holiday", "date": "2026-11-30", "calendarId": "primary"})
        body = MODE["posts"][0][1]
        self.assertEqual((body["start"], body["end"]), ({"date": "2026-11-30"}, {"date": "2026-12-01"}))

    def test_create_refuses_before_writing(self):
        for request in ({"date": "2026-11-20"}, {"title": "x"}, {"title": "x", "date": "soon"},
                        {"title": "x", "date": "2026-11-20", "start": "9am"},
                        {"title": "x", "date": "2026-11-20", "start": "10:00", "end": "09:00"},
                        {"title": "x", "date": "2026-11-20", "calendarId": "readonly@x"}):
            rc, a = self.create(request)
            self.assertEqual((rc, a["ok"]), (1, False), request)
        self.assertEqual(MODE["posts"], [])

    def offline(self):
        def fail(config_dir=None):
            raise cg.Failure("gws is not installed.", "missing")
        saved, cg.credentials = cg.credentials, fail
        self.addCleanup(setattr, cg, "credentials", saved)

    def local(self):
        return self.run_it("range", "2026-11-01", "2026-12-01")[1]

    def test_local_needs_no_account(self):
        self.offline()
        rc, a = self.create({"title": "Dentist", "date": "2026-11-20", "start": "09:30", "location": "Clinic"})
        self.assertEqual(rc, 0)
        self.assertTrue(a["id"].startswith("local/"))
        self.assertEqual(MODE["posts"], [])
        answer = self.local()
        self.assertEqual((answer["ok"], answer["google"]["code"]), (True, "missing"))
        self.assertEqual([c["id"] for c in answer["calendars"]], ["local"])
        e = answer["events"][0]
        self.assertEqual((e["id"], e["title"], e["local"], e["location"]), (a["id"], "Dentist", True, "Clinic"))
        self.assertEqual(e["end"] - e["start"], 3600000)
        self.assertEqual(e["reminders"], [e["start"] - 600000])

    def test_local_all_day_has_no_reminder_unless_asked(self):
        self.offline()
        self.create({"title": "Holiday", "date": "2026-11-20"})
        self.create({"title": "Passport", "date": "2026-11-21", "remind": 60})
        e = {x["title"]: x for x in self.local()["events"]}
        self.assertTrue(e["Holiday"]["allDay"])
        self.assertEqual(e["Holiday"]["reminders"], [])
        self.assertEqual(e["Passport"]["reminders"], [e["Passport"]["start"] - 3600000])

    def test_local_only_in_range(self):
        self.offline()
        self.create({"title": "Later", "date": "2027-01-20"})
        self.assertEqual(self.local()["events"], [])

    def test_local_update_and_delete(self):
        self.offline()
        _, a = self.create({"title": "Old", "date": "2026-11-20", "start": "09:00"})
        rc, _ = self.create({"id": a["id"], "title": "New", "date": "2026-11-21", "start": "10:00"}, "update")
        self.assertEqual(rc, 0)
        e = self.local()["events"]
        self.assertEqual((len(e), e[0]["id"], e[0]["title"]), (1, a["id"], "New"))
        self.assertEqual(self.create({"id": a["id"]}, "delete")[0], 0)
        self.assertEqual(self.local()["events"], [])
        self.assertEqual(self.create({"id": a["id"]}, "delete")[0], 1)

    def test_google_events_cannot_be_changed_here(self):
        for action in ("update", "delete"):
            rc, a = self.create({"id": "me@x/e1", "title": "x", "date": "2026-11-20"}, action)
            self.assertEqual((rc, a["ok"]), (1, False))
        self.assertEqual(MODE["posts"], [])

    def test_a_damaged_file_is_refused_and_kept(self):
        self.offline()
        self.create({"title": "Keep", "date": "2026-11-20"})
        path = cg.local_path()
        with open(path, "w") as handle:
            handle.write("{broken")
        rc, a = self.create({"title": "New", "date": "2026-11-20"})
        self.assertEqual((rc, a["ok"]), (1, False))
        with open(path) as handle:
            self.assertEqual(handle.read(), "{broken")

    def test_google_and_local_merge(self):
        self.create({"title": "Local one", "date": "2026-11-06", "start": "08:00"})
        titles = [e["title"] for e in self.local()["events"]]
        self.assertIn("Local one", titles)
        self.assertIn("Standup", titles)

    def test_two_accounts_are_tagged_and_merged(self):
        self.two_accounts()
        rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual(rc, 0)
        self.assertEqual([(x["key"], x["email"], x["ok"]) for x in a["accounts"]],
                         [("default", "me@x", True), ("work", "you@y", True)])
        # me@x is listed by both accounts: shown once, from the first.
        self.assertEqual([(c["id"], c["account"]) for c in a["calendars"]],
                         [("me@x", "default"), ("you@y", "work"), ("local", "local")])
        self.assertEqual({e["account"] for e in a["events"]}, {"default", "work"})
        self.assertEqual(a["google"], {"ok": True})
        self.assertEqual(len({e["id"] for e in a["events"]}), len(a["events"]))
        self.assertEqual(a["account"], "me@x")

    def test_one_account_failing_keeps_the_other(self):
        self.two_accounts()
        MODE["broken"] = "c2"
        rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual((rc, a["ok"]), (0, True))
        self.assertEqual([(x["key"], x["ok"], x.get("code")) for x in a["accounts"]],
                         [("default", True, None), ("work", False, "signin")])
        self.assertEqual({e["account"] for e in a["events"]}, {"default"})

    def test_every_account_failing_is_a_google_failure_not_a_lost_answer(self):
        self.two_accounts()
        self.create({"title": "Mine", "date": "2026-11-06"})
        MODE.update(status=401)
        rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual((rc, a["ok"], a["google"]["ok"], a["google"]["code"]), (0, True, False, "signin"))
        self.assertEqual([x["ok"] for x in a["accounts"]], [False, False])
        self.assertEqual([e["title"] for e in a["events"]], ["Mine"])

    def test_create_goes_to_the_named_account(self):
        self.two_accounts()
        rc, a = self.create({"title": "Sync", "date": "2026-11-20", "calendarId": "you@y", "account": "work"})
        self.assertEqual((rc, a["ok"]), (0, True))
        path, _, auth = MODE["posts"][0]
        self.assertIn("/calendars/you%40y/events", path)
        self.assertEqual(auth, "Bearer tok-c2")
        MODE["posts"].clear()
        rc, a = self.create({"title": "x", "date": "2026-11-20", "account": "nobody"})
        self.assertEqual((rc, a["ok"], a["code"]), (1, False, "signin"))
        self.assertEqual(MODE["posts"], [])

    def test_account_dirs_finds_signed_in_directories(self):
        import tempfile
        saved = (cg.account_dirs, os.environ.get("XDG_CONFIG_HOME"), os.environ.pop("GOOGLE_WORKSPACE_CLI_CONFIG_DIR", None))
        cg.account_dirs = REAL_ACCOUNT_DIRS
        try:
            with tempfile.TemporaryDirectory() as home:
                os.environ["XDG_CONFIG_HOME"] = home
                root = os.path.join(home, "gws-accounts")
                for name, signed in (("jan", True), ("empty", False), (".hidden", True)):
                    os.makedirs(os.path.join(root, name))
                    if signed:
                        open(os.path.join(root, name, "credentials.enc"), "w").close()
                self.assertEqual(cg.account_dirs(), [None, os.path.join(root, "jan")])
                self.assertEqual([cg.account_key(d) for d in cg.account_dirs()], ["default", "jan"])
                os.environ["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = root
                self.assertEqual(cg.account_dirs(), [None])
        finally:
            cg.account_dirs = saved[0]
            if saved[1] is None: os.environ.pop("XDG_CONFIG_HOME", None)
            else: os.environ["XDG_CONFIG_HOME"] = saved[1]
            if saved[2] is None: os.environ.pop("GOOGLE_WORKSPACE_CLI_CONFIG_DIR", None)
            else: os.environ["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = saved[2]

    def test_bad_arguments(self):
        for args in (["range"], ["range", "x", "y"], ["range", "2026-12-01", "2026-11-01"], ["range", "2026-01-01", "2027-01-01"]):
            rc, a, _ = self.run_it(*args)
            self.assertEqual((rc, a["ok"]), (1, False))

    def test_missing_gws(self):
        saved, cg.credentials = cg.credentials, lambda d=None: self.real_missing()
        try:
            rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
            self.assertEqual(a["google"]["code"], "missing")
        finally:
            cg.credentials = saved

    @staticmethod
    def real_missing():
        raise cg.Failure("gws is not installed.", "missing")


if __name__ == "__main__":
    unittest.main(verbosity=0)
