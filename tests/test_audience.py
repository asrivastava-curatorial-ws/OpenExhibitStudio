"""0.3 live-audience features: presenter navigation, ideas, spinner, ranking, reactions, long-poll, text import."""
import csv
import io
import json
import sys
import threading
import time
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
from contest import deck
from contest.room import Room, Conflict


class Clock:
    def __init__(self): self.now = 1000.0
    def __call__(self): return self.now


def build(*slides, **settings):
    return {"format": "oes-quiz", "version": 1, "title": "Test session", "teams": [], **settings, "questions": list(slides)}


CHOICE = {"type": "choice", "prompt": "Largest planet?", "options": ["Earth", "Jupiter"], "answer": "Jupiter", "seconds": 20, "points": 1000}
POLL = {"type": "poll", "prompt": "Favourite gallery?", "options": ["Space", "Energy", "Life"], "seconds": 60}
CONTENT = {"type": "slide", "prompt": "Welcome", "body": "- Scan the code\n- Pick a name", "layout": "title"}


class AudienceTests(unittest.TestCase):
    def room(self, d, **kw):
        self.clock = Clock()
        r = Room(":memory:", d, clock=self.clock, wall=self.clock, **kw)
        self.addCleanup(r.db.close)
        return r

    def join(self, r, name):
        return r.join(r.meta()["code"], name, None)

    def advance(self, r):
        s = r.snapshot()
        r.control("advance", s["phase"], s["index"])
        return r.snapshot()

    def test_advance_walks_like_a_clicker(self):
        r = self.room(build(CONTENT, CHOICE, POLL))
        a, b = self.join(r, "Asha"), self.join(r, "Bilal")
        self.assertEqual(self.advance(r)["index"], 0)                       # lobby → content slide
        s = self.advance(r)                                                 # content → quiz opens
        self.assertEqual((s["index"], s["phase"]), (1, "open"))
        r.submit(a, 1, "Jupiter")
        self.assertEqual(r.snapshot()["phase"], "open")
        r.submit(b, 1, "Earth")
        self.assertEqual(r.snapshot()["phase"], "closed", "closes once everyone has answered")
        self.assertEqual(self.advance(r)["phase"], "reveal")
        s = self.advance(r)
        self.assertEqual(s["phase"], "standings")
        self.assertEqual(s["leaders"][0]["name"], "Asha")
        s = self.advance(r)                                                 # standings → live poll
        self.assertEqual((s["index"], s["phase"]), (2, "open"))
        r.submit(a, 2, "Space")
        self.assertEqual(r.snapshot()["distribution"], [("Space", 1)])
        self.assertEqual(self.advance(r)["phase"], "finished")              # last slide → final

    def test_presenter_press_tolerates_auto_close_race(self):
        r = self.room(build(CHOICE, POLL))
        a = self.join(r, "Asha")
        self.advance(r)
        r.submit(a, 0, "Jupiter")                                           # everyone answered → closed
        r.control("advance", "open", 0)                                     # press sent while the view said "open"
        self.assertEqual(r.snapshot()["phase"], "reveal")
        with self.assertRaises(Conflict):
            r.control("advance", "open", 0)                                 # a stale press for an old step is still refused

    def test_back_reviews_without_reopening(self):
        r = self.room(build(CHOICE, POLL, CONTENT))
        a = self.join(r, "Asha")
        self.advance(r); r.submit(a, 0, "Jupiter")
        self.advance(r); self.advance(r); self.advance(r)                   # reveal, standings, poll
        s = r.snapshot()
        r.control("back", s["phase"], s["index"])
        s = r.snapshot()
        self.assertEqual((s["index"], s["phase"], s["reviewing"]), (0, "reveal", True))
        with self.assertRaises(Conflict):
            r.submit(a, 0, "Earth")
        s = self.advance(r); s = self.advance(r)                            # standings, then back to the poll
        self.assertEqual((s["index"], s["phase"]), (1, "reveal"), "an already-played slide is reviewed, not reopened")

    def test_open_ended_ideas_limits_votes_and_moderation(self):
        idea = {"type": "open", "prompt": "What should we build next?", "max_entries": 2, "seconds": 90}
        r = self.room(build(idea, dict(idea, moderate=True)))
        a, b = self.join(r, "Asha"), self.join(r, "Bilal")
        self.advance(r)
        r.idea(a, 0, "A wave tank"); r.idea(a, 0, "A tesla coil")
        with self.assertRaises(Conflict):
            r.idea(a, 0, "A third idea")
        first = r.snapshot(b)["ideas"][-1]["id"]
        r.idea_vote(b, first); r.idea_vote(b, first)
        s = r.snapshot(b)
        self.assertEqual(s["ideas"][0]["votes"], 1)
        self.assertEqual(s["me"]["voted"], [first])
        self.assertEqual(s["received"], 1)
        with self.assertRaises(Conflict):
            r.submit(a, 0, "not an answer")
        r.control("skip", "open", 0)
        r.idea(b, 1, "Moderated idea")
        self.assertEqual(r.snapshot()["ideas"], [])
        pending = r.snapshot(host=True)["ideas"][0]
        self.assertEqual(pending["status"], "pending")
        r.moderate_idea(pending["id"], "shown")
        self.assertEqual(r.snapshot()["ideas"][0]["body"], "Moderated idea")
        rows = list(csv.reader(io.StringIO(r.summary())))
        self.assertIn("A wave tank", [row[3] for row in rows])

    def test_spinner_entries_players_and_remove_winner(self):
        wheel = {"type": "spinner", "prompt": "Who answers next?", "source": "players", "remove_winner": True, "seconds": 60}
        r = self.room(build(wheel))
        names = {"Asha", "Bilal", "Chen"}
        for n in names:
            self.join(r, n)
        self.advance(r)
        winners = set()
        for _ in range(3):
            s = r.snapshot(host=True)
            r.control("spin", s["phase"], s["index"])
            spin = r.snapshot()["spinner"]
            self.assertEqual(spin["entries"][spin["index"]], spin["winner"])
            winners.add(spin["winner"])
        self.assertEqual(winners, names, "remove_winner never picks the same person twice")
        s = r.snapshot(host=True)
        with self.assertRaises(Conflict):
            r.control("spin", s["phase"], s["index"])

    def test_ranking_poll_uses_borda_scores_and_scale_range(self):
        rank = {"type": "rank", "prompt": "Rank the galleries", "options": ["A", "B", "C"], "seconds": 60}
        scale = {"type": "scale", "prompt": "Rate the visit", "scale_max": 10, "low_label": "Poor", "high_label": "Superb"}
        r = self.room(build(rank, scale))
        a, b = self.join(r, "Asha"), self.join(r, "Bilal")
        self.advance(r)
        r.submit(a, 0, ["B", "A", "C"]); r.submit(b, 0, ["B", "C", "A"])
        self.assertEqual(r.snapshot()["distribution"][0], ("B", 6))
        self.advance(r)
        r.submit(a, 1, 10)
        with self.assertRaises(deck.Invalid):
            r.submit(b, 1, 11)
        self.assertEqual(r.snapshot()["question"]["high_label"], "Superb")

    def test_reactions_rate_limit_and_switch(self):
        r = self.room(build(POLL))
        a = self.join(r, "Asha")
        pulse = r.snapshot()["pulse"]
        r.react(a, "👏"); r.react(a, "👏")
        self.assertEqual(r.snapshot()["reactions"], {"👏": 1})
        self.clock.now += 1; r.react(a, "❤️")
        self.assertEqual(r.snapshot()["pulse"], pulse+2)
        with self.assertRaises(deck.Invalid):
            r.react(a, "💣")
        quiet = self.room(build(POLL, reactions=False))
        t = self.join(quiet, "Asha")
        with self.assertRaises(Conflict):
            quiet.react(t, "👍")

    def test_anonymous_join_and_guest_names(self):
        r = self.room(build(POLL, anonymous=True))
        r.join(r.meta()["code"], "", None); r.join(r.meta()["code"], "  ", None)
        self.assertEqual(r.snapshot(host=True)["roster"][0]["name"], "Guest 2")

    def test_long_poll_wakes_on_change_and_at_deadline(self):
        r = Room(":memory:", build(CHOICE))
        self.addCleanup(r.db.close)
        v = r.snapshot()["version"]
        done = []
        t = threading.Thread(target=lambda: (r.wait(v, timeout=5), done.append(time.monotonic())))
        start = time.monotonic(); t.start(); time.sleep(0.2)
        r.join(r.meta()["code"], "Asha", None)
        t.join(3)
        self.assertTrue(done and done[0]-start < 1.5, "a join wakes the waiting request")
        quick = Room(":memory:", build(dict(CHOICE, seconds=3)))
        self.addCleanup(quick.db.close)
        quick.join(quick.meta()["code"], "Asha", None)
        quick.control("next", "lobby", -1)
        v = quick.snapshot()["version"]
        start = time.monotonic(); quick.wait(v, timeout=20)
        self.assertLess(time.monotonic()-start, 4.5)
        self.assertEqual(quick.snapshot()["phase"], "closed", "the deadline is broadcast without another request")

    def test_text_import_aiken_and_extensions(self):
        text = """What is the chemical symbol for gold?
A. Ag
B. Au
ANSWER: B

Which are noble gases?
A) Neon
B) Oxygen
C) Argon
ANSWER: A, C

Which gallery should open next?
A. Robots
B. Oceans

Welcome to the science club
Scan the code on the screen to join."""
        d = deck.from_text(text, "Chemistry")
        types = [q["type"] for q in d["questions"]]
        self.assertEqual(types, ["choice", "multiple", "poll", "slide"])
        self.assertEqual(d["questions"][0]["answer"], "Au")
        self.assertEqual(d["questions"][1]["answer"], ["Argon", "Neon"])
        self.assertEqual(d["questions"][3]["body"], "Scan the code on the screen to join.")
        with self.assertRaises(deck.Invalid):
            deck.from_text("\n\n")

    def test_old_decks_still_validate_and_new_settings_default(self):
        old = json.loads((ROOT/"tools/contest/museum.quiz.json").read_text())
        d = deck.validate(old)
        self.assertEqual((d["leaderboard"], d["theme"], d["anonymous"]), ("each", "dark", False))
        with self.assertRaises(deck.Invalid):
            deck.validate(dict(old, theme="neon"))


if __name__ == "__main__":
    unittest.main()
