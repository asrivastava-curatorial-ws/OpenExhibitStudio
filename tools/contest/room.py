"""One persistent live-audience room. All state transitions are serialized.

0.3 additions: a change counter with a condition variable (clients long-poll instead of polling
every second), presenter "advance"/"back" navigation, auto-close when everyone answered, emoji
reactions, open-ended idea boards with voting and moderation, spinner wheels, ranking polls and a
per-slide summary export.
"""
import collections
import csv
import hashlib
import io
import json
import secrets
import sqlite3
import threading
import time

from . import deck

REACTIONS = ("👍", "❤️", "😂", "😮", "👏", "🤔")


class Conflict(ValueError):
    pass


class Forbidden(ValueError):
    pass


def token_hash(token):
    return hashlib.sha256(str(token).encode()).hexdigest()


def dump(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


class Room:
    def __init__(self, dbfile, initial_deck, capacity=400, clock=time.monotonic, wall=time.time, self_paced=False):
        self.clock, self.wall, self.capacity = clock, wall, capacity
        self.lock = threading.RLock()
        self.changed = threading.Condition(self.lock)
        self.version = 1
        self.pulse = 0
        self.reactions = collections.Counter()
        self.last_reaction = {}
        self.spin = None
        self.db = sqlite3.connect(dbfile, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS room(id INTEGER PRIMARY KEY CHECK(id=1), deck TEXT, code TEXT, phase TEXT,
            idx INTEGER, elapsed REAL, deadline REAL, locked INTEGER);
        CREATE TABLE IF NOT EXISTS players(id INTEGER PRIMARY KEY, name TEXT, normalized TEXT UNIQUE, team TEXT, token TEXT UNIQUE);
        CREATE TABLE IF NOT EXISTS answers(round INTEGER, player INTEGER, value TEXT, points INTEGER, elapsed REAL,
            PRIMARY KEY(round,player));
        CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY, v TEXT);
        CREATE TABLE IF NOT EXISTS practice(player INTEGER PRIMARY KEY, idx INTEGER, phase TEXT, deadline REAL, start REAL);
        CREATE TABLE IF NOT EXISTS questions(id INTEGER PRIMARY KEY, player INTEGER, body TEXT, status TEXT);
        CREATE TABLE IF NOT EXISTS votes(question INTEGER, player INTEGER, PRIMARY KEY(question,player));
        CREATE TABLE IF NOT EXISTS ideas(id INTEGER PRIMARY KEY, round INTEGER, player INTEGER, body TEXT, status TEXT);
        CREATE TABLE IF NOT EXISTS idea_votes(idea INTEGER, player INTEGER, PRIMARY KEY(idea,player));
        CREATE TABLE IF NOT EXISTS spins(id INTEGER PRIMARY KEY, round INTEGER, label TEXT);
        """)
        with self.db:
            if not self.db.execute("SELECT 1 FROM room").fetchone():
                self.db.execute("INSERT INTO room VALUES(1,?,?,'lobby',-1,0,0,0)",
                                (dump(deck.validate(initial_deck)), self.new_code()))
            self.db.execute("INSERT OR IGNORE INTO settings VALUES('mode',?)", ("practice" if self_paced else "live",))
            self.db.execute("INSERT OR IGNORE INTO settings VALUES('max_idx','-1')")
            self.practice_mode = self.db.execute("SELECT v FROM settings WHERE k='mode'").fetchone()[0] == "practice"
            self.practice_clocks = {}
            state = self.meta()
            self.deck = deck.validate(json.loads(state["deck"]))
            self.started = self.clock()
            if state["phase"] == "open" and self.deck["questions"][state["idx"]]["seconds"]:
                duration = self.deck["questions"][state["idx"]]["seconds"]
                elapsed = min(duration, max(state["elapsed"], duration - max(0, state["deadline"] - self.wall())))
                self.db.execute("UPDATE room SET phase=?,elapsed=?,deadline=0", ("paused" if elapsed < duration else "closed", elapsed))

    # ------------------------------------------------------------------ plumbing
    @staticmethod
    def new_code():
        return str(100000 + secrets.randbelow(900000))

    def meta(self):
        with self.lock:
            return self.db.execute("SELECT * FROM room").fetchone()

    def bump(self, pulse_only=False):
        """Record a change and wake every waiting long-poll request (caller holds the lock)."""
        if pulse_only:
            self.pulse += 1
        else:
            self.version += 1
        self.changed.notify_all()

    def wait(self, since, pulse=None, timeout=20.0):
        """Block until the room changes after `since` (or `pulse` for projector reactions)."""
        end = time.monotonic() + max(0.0, min(timeout, 25.0))
        with self.changed:
            while self.version == since and (pulse is None or self.pulse == pulse):
                remaining = end - time.monotonic()
                s = self.meta()
                if s["phase"] == "open" and s["idx"] >= 0 and self.deck["questions"][s["idx"]]["seconds"]:
                    # Wake at the round deadline so the closing is broadcast promptly.
                    left = self.deck["questions"][s["idx"]]["seconds"] - self.elapsed(s)
                    remaining = min(remaining, left + 0.05)
                if remaining <= 0:
                    with self.db:
                        self.tick()
                    break
                self.changed.wait(remaining)

    def max_idx(self):
        return int(self.db.execute("SELECT v FROM settings WHERE k='max_idx'").fetchone()[0])

    def elapsed(self, state):
        return state["elapsed"] + (max(0, self.clock()-self.started) if state["phase"] == "open" else 0)

    def tick(self):
        s = self.meta()
        seconds = self.deck["questions"][s["idx"]]["seconds"] if s["idx"] >= 0 else 0
        if s["phase"] == "open" and seconds and self.elapsed(s) >= seconds:
            self.db.execute("UPDATE room SET phase='closed',elapsed=?,deadline=0", (self.deck["questions"][s["idx"]]["seconds"],))
            self.bump()
            return self.meta()
        return s

    def player(self, token):
        row = self.db.execute("SELECT * FROM players WHERE token=?", (token_hash(token),)).fetchone()
        if row is None:
            raise Forbidden("Rejoin this room to participate.")
        return row

    # ------------------------------------------------------------------ audience actions
    def join(self, code, name, team):
        with self.lock, self.db:
            s = self.tick()
            if not secrets.compare_digest(str(code).encode(), s["code"].encode()):
                raise Forbidden("Check the six-digit room code.")
            if self.deck.get("anonymous") and (not isinstance(name, str) or not name.strip()):
                count = self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0]
                name = "Guest %d" % (count + 1)
                while self.db.execute("SELECT 1 FROM players WHERE normalized=?", (deck.normal(name),)).fetchone():
                    count += 1
                    name = "Guest %d" % (count + 1)
            name = deck.string(name, 32, "Display name")
            if s["locked"] or s["phase"] == "finished":
                raise Conflict("Joining is closed.")
            if self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0] >= self.capacity:
                raise Conflict("The room is full.")
            if self.deck["teams"] and team not in self.deck["teams"]:
                raise deck.Invalid("Select a team.")
            token = secrets.token_urlsafe(32)
            try:
                self.db.execute("INSERT INTO players(name,normalized,team,token) VALUES(?,?,?,?)",
                                (name, deck.normal(name), team if self.deck["teams"] else "", token_hash(token)))
            except sqlite3.IntegrityError as exc:
                raise Conflict("That display name is already in use.") from exc
            if self.practice_mode:
                self.db.execute("INSERT INTO practice VALUES(?, -1, 'lobby',0,0)", (self.player(token)["id"],))
            self.bump()
            return token

    def practice_state(self, pid):
        row = self.db.execute("SELECT * FROM practice WHERE player=?", (pid,)).fetchone()
        idx, phase = row["idx"], row["phase"]
        if phase != "open":
            return idx, phase, 0
        duration = self.deck["questions"][idx]["seconds"]
        if not duration:
            return idx, phase, 0
        if pid not in self.practice_clocks:
            self.practice_clocks[pid] = self.clock()+max(0, min(duration, row["deadline"]-self.wall()))
        left = max(0, min(duration, self.practice_clocks[pid]-self.clock()))
        if left == 0:
            self.db.execute("UPDATE practice SET phase='reveal' WHERE player=?", (pid,))
            self.practice_clocks.pop(pid, None)
            phase = "reveal"
        return idx, phase, left

    def practice_next(self, token, idx):
        with self.lock, self.db:
            if not self.practice_mode or self.meta()["phase"] != "practice":
                raise Conflict("Self-paced play is unavailable.")
            pid = self.player(token)["id"]
            current, phase, _ = self.practice_state(pid)
            if idx != current or phase not in ("lobby", "reveal"):
                raise Conflict("Refresh your current round.")
            if current+1 >= len(self.deck["questions"]):
                self.db.execute("UPDATE practice SET phase='finished' WHERE player=?", (pid,))
            else:
                duration = self.deck["questions"][current+1]["seconds"]
                self.practice_clocks[pid] = self.clock()+duration
                self.db.execute("UPDATE practice SET idx=idx+1,phase='open',deadline=?,start=? WHERE player=?", (self.wall()+duration, self.wall(), pid))
            self.bump()

    def submit(self, token, idx, value):
        with self.lock, self.db:
            player = self.player(token)
            s = self.tick()
            personal = self.practice_mode and s["phase"] == "practice"
            if self.practice_mode and not personal:
                raise Conflict("Self-paced play is closed.")
            if personal:
                round_idx, phase, left = self.practice_state(player["id"])
            else:
                round_idx, phase, left = s["idx"], s["phase"], 0
            if type(idx) is not int or idx != round_idx or idx < 0:
                raise Conflict("The host has moved to another slide.")
            q = self.deck["questions"][idx]
            if q["type"] in {"slide", "open", "qa", "spinner"}:
                raise Conflict("This slide does not take answers.")
            val = deck.response(q, value)
            old = self.db.execute("SELECT value FROM answers WHERE round=? AND player=?", (idx, player["id"])).fetchone()
            if old:
                if json.loads(old[0]) == val:
                    return
                raise Conflict("Your answer has already been recorded.")
            elapsed = q["seconds"]-left if personal else self.elapsed(s)
            if phase != "open" or (q["seconds"] and elapsed >= q["seconds"]):
                raise Conflict("This round is closed for answers.")
            factor = 1 - .5 * min(1, elapsed/q["seconds"]) if self.deck["speed_bonus"] and q["seconds"] else 1
            points = int(q["points"] * factor + .5) if deck.correct(q, val) else 0
            self.db.execute("INSERT INTO answers VALUES(?,?,?,?,?)", (idx, player["id"], dump(val), points, elapsed))
            if personal:
                self.db.execute("UPDATE practice SET phase='reveal' WHERE player=?", (player["id"],))
                self.practice_clocks.pop(player["id"], None)
            elif q["type"] in deck.GRADED and self.deck.get("auto_close", True):
                received = self.db.execute("SELECT COUNT(*) FROM answers WHERE round=?", (idx,)).fetchone()[0]
                players = self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0]
                if received >= players:
                    self.db.execute("UPDATE room SET phase='closed',elapsed=?,deadline=0", (self.elapsed(s),))
            self.bump()

    def idea(self, token, idx, text):
        """Add an open-ended response (idea board)."""
        with self.lock, self.db:
            p = self.player(token)
            s = self.tick()
            q = self.deck["questions"][s["idx"]] if s["idx"] >= 0 else {}
            if type(idx) is not int or idx != s["idx"] or q.get("type") != "open" or s["phase"] != "open":
                raise Conflict("This slide is not collecting ideas.")
            body = deck.string(text, 200, "Idea")
            count = self.db.execute("SELECT COUNT(*) FROM ideas WHERE round=? AND player=?", (idx, p["id"])).fetchone()[0]
            if count >= q.get("max_entries", 3):
                raise Conflict("You have shared the maximum number of ideas for this slide.")
            self.db.execute("INSERT INTO ideas(round,player,body,status) VALUES(?,?,?,?)",
                            (idx, p["id"], body, "pending" if q.get("moderate") else "shown"))
            self.bump()

    def idea_vote(self, token, ident):
        with self.lock, self.db:
            p = self.player(token)
            row = self.db.execute("SELECT round FROM ideas WHERE id=? AND status='shown'", (ident,)).fetchone()
            if not row or row["round"] != self.meta()["idx"]:
                raise Conflict("This idea is unavailable.")
            self.db.execute("INSERT OR IGNORE INTO idea_votes VALUES(?,?)", (ident, p["id"]))
            self.bump()

    def moderate_idea(self, ident, status):
        if status not in {"shown", "hidden"}:
            raise deck.Invalid("Unknown moderation status.")
        with self.lock, self.db:
            if not self.db.execute("UPDATE ideas SET status=? WHERE id=?", (status, ident)).rowcount:
                raise Conflict("Unknown idea.")
            self.bump()

    def react(self, token, emoji):
        with self.lock:
            if not self.deck.get("reactions", True):
                raise Conflict("Reactions are switched off for this session.")
            if emoji not in REACTIONS:
                raise deck.Invalid("Unknown reaction.")
            pid = self.player(token)["id"]
            now = self.clock()
            if now - self.last_reaction.get(pid, -10) < 0.6:
                return
            self.last_reaction[pid] = now
            self.reactions[emoji] += 1
            self.bump(pulse_only=True)

    def qa(self, token, action, value):
        with self.lock, self.db:
            p = self.player(token)
            if self.meta()["phase"] == "finished":
                raise Conflict("This session has finished.")
            if not self.deck.get("qa", True):
                raise Conflict("Questions are switched off for this session.")
            if action == "ask":
                body = deck.string(value, 240, "Question")
                if self.db.execute("SELECT COUNT(*) FROM questions WHERE player=?", (p["id"],)).fetchone()[0] >= 8:
                    raise Conflict("Question limit reached.")
                self.db.execute("INSERT INTO questions(player,body,status) VALUES(?,?,'pending')", (p["id"], body))
            elif action == "vote":
                if not self.db.execute("SELECT 1 FROM questions WHERE id=? AND status='published'", (value,)).fetchone():
                    raise Conflict("This question is unavailable.")
                self.db.execute("INSERT OR IGNORE INTO votes VALUES(?,?)", (value, p["id"]))
            else:
                raise deck.Invalid("Unknown audience action.")
            self.bump()

    def moderate(self, ident, status):
        if status not in {"published", "hidden", "answered"}:
            raise deck.Invalid("Unknown moderation status.")
        with self.lock, self.db:
            if not self.db.execute("UPDATE questions SET status=? WHERE id=?", (status, ident)).rowcount:
                raise Conflict("Unknown audience question.")
            self.bump()

    # ------------------------------------------------------------------ presenter control
    def _enter(self, index):
        """Show slide `index`: open it fresh, or review it if it was already played."""
        if index <= self.max_idx():
            self.db.execute("UPDATE room SET phase='reveal',idx=?,deadline=0", (index,))
            return
        q = self.deck["questions"][index]
        self.started = self.clock()
        self.spin = None
        self.db.execute("UPDATE room SET phase='open',idx=?,elapsed=0,deadline=?", (index, self.wall()+q["seconds"]))
        self.db.execute("UPDATE settings SET v=? WHERE k='max_idx'", (str(index),))

    def _finish(self):
        self.db.execute("UPDATE room SET phase='finished',locked=1,deadline=0")

    def control(self, action, expected, idx, data=None):
        with self.lock, self.db:
            s = self.tick()
            phase, index = s["phase"], s["idx"]
            if expected != phase or idx != index:
                # A round can close on its own (deadline, or everyone answered) while the presenter's
                # key press is in flight; on the same slide that does not change what "next" means.
                answering = {"open", "paused", "closed"}
                same_step = idx == index and expected in answering and phase in answering
                if not (same_step and action in {"advance", "reveal", "skip", "back", "spin", "lock"}):
                    raise Conflict("The room changed. Refresh the presenter view.")
            q = self.deck["questions"][index] if index >= 0 else {}
            last = index + 1 >= len(self.deck["questions"])
            graded = q.get("type") in deck.GRADED
            if action == "advance":
                # One button / key does the right thing, like a presentation clicker.
                if phase == "lobby":
                    action = "next"
                elif phase in {"open", "paused", "closed"}:
                    hidden_results = q.get("type") in {"poll", "scale", "cloud", "rank", "open"} and not q.get("live_results")
                    action = "reveal" if graded or hidden_results else ("finish" if last else "skip")
                elif phase == "reveal":
                    # On the last slide the final podium replaces the per-question leaderboard.
                    board = graded and not last and self.deck.get("leaderboard", "each") == "each"
                    action = "standings" if board else ("finish" if last else "next")
                elif phase == "standings":
                    action = "finish" if last else "next"
                elif phase == "practice":
                    raise Conflict("Self-paced play is running; use Finish when everyone is done.")
                else:
                    raise Conflict("The session has finished.")
            if action == "lock":
                self.db.execute("UPDATE room SET locked=?", (not s["locked"],))
            elif action == "deck" and phase == "lobby":
                new = deck.validate(data)
                if new["teams"] != self.deck["teams"] and self.db.execute("SELECT 1 FROM players LIMIT 1").fetchone():
                    raise Conflict("Team rosters are fixed once players have joined.")
                self.db.execute("UPDATE room SET deck=?", (dump(new),))
                self.deck = new
            elif action == "next" and phase == "lobby" and self.practice_mode:
                self.db.execute("UPDATE room SET phase='practice'")
            elif action == "finish" and phase == "practice":
                self.db.execute("UPDATE room SET phase='finished',idx=?,locked=1", (len(self.deck["questions"])-1,))
            elif action == "next" and phase in {"lobby", "reveal", "standings"} and not last:
                self._enter(index+1)
            elif action == "skip" and phase in {"open", "paused", "closed"} and not graded and not last:
                self._enter(index+1)
            elif action == "back" and phase not in {"lobby", "practice"} and index > 0:
                if phase == "finished":
                    self.db.execute("UPDATE room SET locked=0")
                self.db.execute("UPDATE room SET phase='reveal',idx=?,deadline=0", (index-1 if phase != "finished" else index,))
            elif action == "pause" and phase == "open":
                self.db.execute("UPDATE room SET phase='paused',elapsed=?,deadline=0", (self.elapsed(s),))
            elif action == "resume" and phase == "paused":
                self.started = self.clock()
                self.db.execute("UPDATE room SET phase='open',deadline=?", (self.wall()+q["seconds"]-s["elapsed"],))
            elif action == "reveal" and phase in {"open", "closed", "paused"}:
                self.db.execute("UPDATE room SET phase='reveal',elapsed=?,deadline=0", (self.elapsed(s),))
            elif action == "standings" and phase == "reveal":
                self.db.execute("UPDATE room SET phase='standings'")
            elif action == "finish" and phase in {"reveal", "standings", "open", "paused", "closed"} and (last or phase in {"reveal", "standings"}):
                self._finish()
            elif action == "spin" and q.get("type") == "spinner" and phase in {"open", "paused", "closed", "reveal"}:
                entries = self.spinner_entries(index, q)
                if not entries:
                    raise Conflict("The spinner has no entries yet.")
                pick = secrets.randbelow(len(entries))
                self.spin = {"round": index, "seq": (self.spin or {}).get("seq", 0)+1, "index": pick,
                             "label": entries[pick], "entries": entries}
                self.db.execute("INSERT INTO spins(round,label) VALUES(?,?)", (index, entries[pick]))
            else:
                raise Conflict("That action is unavailable in this phase.")
            self.bump()

    def spinner_entries(self, index, q):
        if q.get("source") == "players":
            names = [r[0] for r in self.db.execute("SELECT name FROM players ORDER BY id LIMIT 200")]
        else:
            names = list(q.get("options", []))
        if q.get("remove_winner"):
            taken = collections.Counter(r[0] for r in self.db.execute("SELECT label FROM spins WHERE round=?", (index,)))
            kept = []
            for n in names:
                if taken[n]:
                    taken[n] -= 1
                else:
                    kept.append(n)
            names = kept
        return names

    # ------------------------------------------------------------------ views
    def distribution(self, idx, typ):
        if typ == "rank":
            scores = collections.Counter()
            for row in self.db.execute("SELECT value FROM answers WHERE round=?", (idx,)):
                order = json.loads(row[0])
                for pos, item in enumerate(order):
                    scores[item] += len(order) - pos
            return scores.most_common(40)
        counts = collections.Counter()
        for row in self.db.execute("SELECT value FROM answers WHERE round=?", (idx,)):
            val = json.loads(row[0])
            for v in val if isinstance(val, list) else [val]:
                counts[str(deck.normal(v) if typ == "cloud" else v)] += 1
        if typ == "scale":
            return sorted(counts.items(), key=lambda kv: int(kv[0]))
        return counts.most_common(60 if typ == "cloud" else 40)

    def idea_list(self, idx, host):
        return [dict(r) for r in self.db.execute("""
            SELECT i.id,i.body,i.status,COUNT(v.player) AS votes FROM ideas i LEFT JOIN idea_votes v ON v.idea=i.id
            WHERE i.round=? AND (? OR i.status='shown') GROUP BY i.id ORDER BY votes DESC,i.id DESC LIMIT 120""", (idx, host))]

    def snapshot(self, token=None, host=False):
        with self.lock, self.db:
            s = self.tick()
            phase, idx = s["phase"], s["idx"]
            session_phase = phase
            person = self.player(token) if token else None
            personal = self.practice_mode and session_phase == "practice" and person is not None
            left = None
            if personal:
                idx, phase, left = self.practice_state(person["id"])
            reveal = phase in {"reveal", "standings", "finished"}
            q = self.deck["questions"][idx] if idx >= 0 else None
            data = dict(title=self.deck["title"], code=s["code"], phase=phase, index=idx, rounds=len(self.deck["questions"]),
                        teams=self.deck["teams"], locked=bool(s["locked"]), speed_bonus=self.deck["speed_bonus"],
                        question=deck.public_question(q) if q else None,
                        seconds_left=left if left is not None else max(0, q["seconds"]-self.elapsed(s)) if q else 0,
                        self_paced=self.practice_mode, session_phase=session_phase,
                        players=self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0],
                        received=self.db.execute("SELECT COUNT(*) FROM answers WHERE round=?", (idx,)).fetchone()[0],
                        version=self.version, pulse=self.pulse, reactions=dict(self.reactions),
                        settings={k: self.deck.get(k) for k in ("anonymous", "reactions", "qa", "leaderboard", "theme")},
                        graded_rounds=sum(1 for x in self.deck["questions"] if x["type"] in deck.GRADED),
                        reviewing=bool(idx >= 0 and idx < self.max_idx() and phase == "reveal"))
            data["qa"] = [dict(r) for r in self.db.execute("""
                SELECT q.id,q.body,q.status,COUNT(v.player) AS votes FROM questions q LEFT JOIN votes v ON q.id=v.question
                WHERE (? OR q.status IN ('published','answered')) GROUP BY q.id ORDER BY votes DESC,q.id LIMIT 200""", (host,))]
            if q and q["type"] == "open":
                data["ideas"] = self.idea_list(idx, host)
                data["received"] = self.db.execute("SELECT COUNT(DISTINCT player) FROM ideas WHERE round=?", (idx,)).fetchone()[0]
            if q and q["type"] == "spinner":
                spin = self.spin if self.spin and self.spin["round"] == idx else None
                data["spinner"] = dict(entries=spin["entries"] if spin else self.spinner_entries(idx, q),
                                       seq=spin["seq"] if spin else 0, index=spin["index"] if spin else None,
                                       winner=spin["label"] if spin else None)
            if token:
                player = person
                own = self.db.execute("SELECT value,points FROM answers WHERE round=? AND player=?", (idx, player["id"])).fetchone()
                data["me"] = dict(name=player["name"], team=player["team"], submitted=bool(own),
                                  value=json.loads(own["value"]) if own else None, points=own["points"] if own and reveal else None)
                if q and q["type"] == "open":
                    data["me"]["ideas"] = self.db.execute("SELECT COUNT(*) FROM ideas WHERE round=? AND player=?", (idx, player["id"])).fetchone()[0]
                    data["me"]["voted"] = [r[0] for r in self.db.execute(
                        "SELECT v.idea FROM idea_votes v JOIN ideas i ON i.id=v.idea WHERE i.round=? AND v.player=?", (idx, player["id"]))]
                if reveal and not personal:
                    total = self.db.execute("SELECT COALESCE(SUM(points),0) FROM answers WHERE player=? AND round<=?", (player["id"], idx)).fetchone()[0]
                    data["me"]["total"] = total
            if host or s["phase"] == "lobby":
                # Display names are public anyway (leaderboards); the lobby screen greets new arrivals.
                data["roster"] = [dict(r) for r in self.db.execute("SELECT name,team FROM players ORDER BY id DESC LIMIT 60")]
            if host:
                data["deck"] = self.deck
                data["max_index"] = self.max_idx()
            if personal:
                data["total_score"] = self.db.execute("SELECT COALESCE(SUM(points),0) FROM answers WHERE player=?", (person["id"],)).fetchone()[0]
                data["received"] = int(bool(data["me"]["submitted"]))
            if q and q.get("live_results") and not self.practice_mode and not reveal and (not token or host or data["me"]["submitted"]):
                data["distribution"] = self.distribution(idx, q["type"])
            if q and reveal:
                data["answer"] = q.get("answer")
                data["explanation"] = q.get("explanation", "")
                if q["type"] in {"choice", "poll", "multiple", "cloud", "scale", "rank"} and not personal:
                    data["distribution"] = self.distribution(idx, q["type"])
                if personal:
                    data.pop("distribution", None)
                    return data
                if phase in {"standings", "finished"} or q["type"] in deck.GRADED:
                    rows = [dict(r) for r in self.db.execute("""
                        SELECT p.name,p.team,COALESCE(SUM(a.points),0) AS score FROM players p
                        LEFT JOIN answers a ON a.player=p.id AND a.round<=? GROUP BY p.id ORDER BY score DESC,p.normalized,p.id""", (idx,))]
                    totals = collections.Counter()
                    for row in rows:
                        if row["team"]:
                            totals[row["team"]] += row["score"]
                    data["leaders"] = ranks(rows)[:30]
                    data["team_leaders"] = ranks([{"name": k, "score": v} for k, v in sorted(totals.items(), key=lambda it: (-it[1], it[0]))])
                    if token and person is not None:
                        me = next((r for r in ranks(rows) if r["name"] == person["name"]), None)
                        if me:
                            data["me"]["rank"] = me["rank"]
            return data

    def export(self):
        def cell(v):
            s = str(v)
            return "'"+s if s.lstrip().startswith(("=", "+", "-", "@")) or s.startswith(("\t", "\r", "\n")) else s
        with self.lock, self.db:
            out = io.StringIO(newline="")
            writer = csv.writer(out)
            writer.writerow(["player", "team", "round", "question", "answer", "points", "elapsed_seconds"])
            count = max(0, self.meta()["idx"]+1, self.max_idx()+1)
            if self.practice_mode:
                row = self.db.execute("SELECT MAX(idx) FROM practice").fetchone()
                count = max(0, (row[0] if row[0] is not None else -1)+1)
            players = self.db.execute("SELECT * FROM players ORDER BY id").fetchall()
            for p in players:
                by_round = {a["round"]: a for a in self.db.execute("SELECT * FROM answers WHERE player=?", (p["id"],))}
                for idx in range(count):
                    if self.deck["questions"][idx]["type"] in {"slide", "open", "qa", "spinner"}:
                        continue
                    a = by_round.get(idx)
                    val = json.loads(a["value"]) if a else ""
                    writer.writerow([cell(p["name"]), cell(p["team"]), idx+1, cell(self.deck["questions"][idx]["prompt"]),
                                     cell(dump(val) if isinstance(val, list) else val), a["points"] if a else 0,
                                     round(a["elapsed"], 3) if a else ""])
            return out.getvalue()

    def summary(self):
        """One row per result line: poll counts, word frequencies, ideas, spins and Q&A."""
        def cell(v):
            s = str(v)
            return "'"+s if s.lstrip().startswith(("=", "+", "-", "@")) else s
        with self.lock, self.db:
            out = io.StringIO(newline="")
            w = csv.writer(out)
            w.writerow(["slide", "type", "prompt", "item", "count_or_score", "note"])
            for idx, q in enumerate(self.deck["questions"]):
                if idx > max(self.max_idx(), self.meta()["idx"]):
                    break
                label = deck.LABELS.get(q["type"], q["type"])
                if q["type"] in deck.GRADED:
                    n, right = self.db.execute("SELECT COUNT(*),SUM(points>0) FROM answers WHERE round=?", (idx,)).fetchone()
                    w.writerow([idx+1, label, cell(q["prompt"]), "correct answers", right or 0, f"{n} responses"])
                    if q["type"] in {"choice", "multiple"}:
                        for item, c in self.distribution(idx, q["type"]):
                            w.writerow([idx+1, label, cell(q["prompt"]), cell(item), c, "correct" if (item == q.get("answer") or item in (q.get("answer") or [])) else ""])
                elif q["type"] in {"poll", "cloud", "scale", "rank"}:
                    for item, c in self.distribution(idx, q["type"]):
                        w.writerow([idx+1, label, cell(q["prompt"]), cell(item), c, "Borda score" if q["type"] == "rank" else ""])
                elif q["type"] == "open":
                    for i in self.idea_list(idx, True):
                        w.writerow([idx+1, label, cell(q["prompt"]), cell(i["body"]), i["votes"], i["status"]])
                elif q["type"] == "spinner":
                    for (lbl,) in self.db.execute("SELECT label FROM spins WHERE round=? ORDER BY id", (idx,)):
                        w.writerow([idx+1, label, cell(q["prompt"]), cell(lbl), 1, "spin result"])
            for r in self.db.execute("""SELECT q.body,q.status,COUNT(v.player) FROM questions q LEFT JOIN votes v ON v.question=q.id
                                        GROUP BY q.id ORDER BY q.id"""):
                w.writerow(["", "Audience Q&A", "", cell(r[0]), r[2], r[1]])
            return out.getvalue()


def ranks(rows):
    previous, rank = None, 0
    for i, row in enumerate(rows):
        if row["score"] != previous:
            previous, rank = row["score"], i+1
        row["rank"] = rank
    return rows
