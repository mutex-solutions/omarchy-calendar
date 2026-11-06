#!/usr/bin/env python3
"""python3 tests/test_helper.py: the helper against a fake Google on localhost."""
import http.server, importlib.machinery, importlib.util, io, json, os, sys, threading, unittest, contextlib

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "calendar-google")
loader = importlib.machinery.SourceFileLoader("calendar_google", path)
spec = importlib.util.spec_from_loader("calendar_google", loader)
cg = importlib.util.module_from_spec(spec)
loader.exec_module(cg)

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
MODE = {"status": 200, "reason": "", "tokens": [], "posts": []}


class Fake(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(raw))); self.end_headers()
        self.wfile.write(raw)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path.startswith("/token"):
            return self.reply(200, {"access_token": "tok"})
        MODE["posts"].append((self.path, json.loads(raw)))
        self.reply(200, {"id": "new1", "htmlLink": "https://calendar.google.com/new1"})
    def do_GET(self):
        MODE["tokens"].append(self.headers.get("Authorization"))
        if MODE["status"] != 200:
            return self.reply(MODE["status"], {"error": {"errors": [{"reason": MODE["reason"]}]}, "leak": "SECRET-TEXT"})
        if "/users/me/calendarList/" in self.path:
            return self.reply(200, {"accessRole": "reader" if "readonly" in self.path else "owner"})
        self.reply(200, CALS if "calendarList" in self.path else EVENTS)


class Helper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % cls.server.server_port
        cg.API, cg.TOKEN_URL = base, base + "/token"
        cg.credentials = lambda: {"client_id": "a", "client_secret": "b", "refresh_token": "c"}

    def setUp(self):
        MODE.update(status=200, reason="", tokens=[], posts=[])

    def run_it(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = cg.main(["calendar-google", *args])
        return rc, json.loads(out.getvalue()), out.getvalue()

    def test_reads_only_listed_calendars(self):
        rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
        self.assertEqual(rc, 0)
        self.assertEqual([c["id"] for c in a["calendars"]], ["me@x"])
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
            self.assertEqual((rc, a["ok"], a["code"]), (1, False, code))
            self.assertNotIn("SECRET-TEXT", raw)

    def create(self, request):
        out = io.StringIO()
        stdin = sys.stdin
        sys.stdin = io.TextIOWrapper(io.BytesIO(json.dumps(request).encode()))
        try:
            with contextlib.redirect_stdout(out):
                rc = cg.main(["calendar-google", "create"])
        finally:
            sys.stdin = stdin
        return rc, json.loads(out.getvalue())

    def test_create_timed(self):
        rc, a = self.create({"title": " Dentist ", "date": "2026-11-20", "start": "09:30", "end": "10:15", "location": "Clinic"})
        self.assertEqual((rc, a["ok"], a["id"]), (0, True, "new1"))
        path, body = MODE["posts"][0]
        self.assertIn("/calendars/primary/events", path)
        self.assertIn("sendUpdates=none", path)
        self.assertEqual(body["summary"], "Dentist")
        self.assertTrue(body["start"]["dateTime"].startswith("2026-11-20T09:30:00"))
        self.assertTrue(body["end"]["dateTime"].startswith("2026-11-20T10:15:00"))
        self.assertNotIn("attendees", body)

    def test_create_defaults(self):
        self.create({"title": "One hour", "date": "2026-11-20", "start": "23:30"})
        self.assertTrue(MODE["posts"][0][1]["end"]["dateTime"].startswith("2026-11-21T00:30:00"))
        MODE["posts"].clear()
        self.create({"title": "Holiday", "date": "2026-11-30"})
        body = MODE["posts"][0][1]
        self.assertEqual((body["start"], body["end"]), ({"date": "2026-11-30"}, {"date": "2026-12-01"}))

    def test_create_refuses_before_writing(self):
        for request in ({"date": "2026-11-20"}, {"title": "x"}, {"title": "x", "date": "soon"},
                        {"title": "x", "date": "2026-11-20", "start": "9am"},
                        {"title": "x", "date": "2026-11-20", "start": "10:00", "end": "09:00"},
                        {"title": "x", "date": "2026-11-20", "calendarId": "readonly@x"}, ["x"]):
            rc, a = self.create(request)
            self.assertEqual((rc, a["ok"]), (1, False), request)
        self.assertEqual(MODE["posts"], [])

    def test_bad_arguments(self):
        for args in (["range"], ["range", "x", "y"], ["range", "2026-12-01", "2026-11-01"], ["range", "2026-01-01", "2027-01-01"]):
            rc, a, _ = self.run_it(*args)
            self.assertEqual((rc, a["ok"]), (1, False))

    def test_missing_gws(self):
        saved, cg.credentials = cg.credentials, self.real_missing
        try:
            rc, a, _ = self.run_it("range", "2026-11-01", "2026-12-01")
            self.assertEqual(a["code"], "missing")
        finally:
            cg.credentials = saved

    @staticmethod
    def real_missing():
        raise cg.Failure("gws is not installed.", "missing")


if __name__ == "__main__":
    unittest.main(verbosity=0)
