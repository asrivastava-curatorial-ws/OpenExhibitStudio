"""One persistent, host-paced quiz room. All state transitions are serialized."""
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
        """)
        with self.db:
            if not self.db.execute("SELECT 1 FROM room").fetchone():
                self.db.execute("INSERT INTO room VALUES(1,?,?,'lobby',-1,0,0,0)",
                                (dump(deck.validate(initial_deck)), self.new_code()))
            self.db.execute("INSERT OR IGNORE INTO settings VALUES('mode',?)", ("practice" if self_paced else "live",))
            self.practice_mode = self.db.execute("SELECT v FROM settings WHERE k='mode'").fetchone()[0]=="practice"
            self.practice_clocks = {}
            state = self.meta()
            self.deck = deck.validate(json.loads(state["deck"]))
            self.started = self.clock()
            if state["phase"] == "open":
                duration = self.deck["questions"][state["idx"]]["seconds"]
                elapsed = min(duration, max(state["elapsed"], duration - max(0, state["deadline"] - self.wall())))
                self.db.execute("UPDATE room SET phase=?,elapsed=?,deadline=0", ("paused" if elapsed < duration else "closed", elapsed))

    @staticmethod
    def new_code():
        return str(100000 + secrets.randbelow(900000))

    def meta(self):
        with self.lock:
            return self.db.execute("SELECT * FROM room").fetchone()

    def elapsed(self, state):
        return state["elapsed"] + (max(0, self.clock()-self.started) if state["phase"] == "open" else 0)

    def tick(self):
        s = self.meta()
        if s["phase"] == "open" and self.elapsed(s) >= self.deck["questions"][s["idx"]]["seconds"]:
            self.db.execute("UPDATE room SET phase='closed',elapsed=?,deadline=0", (self.deck["questions"][s["idx"]]["seconds"],))
            return self.meta()
        return s

    def player(self, token):
        row = self.db.execute("SELECT * FROM players WHERE token=?", (token_hash(token),)).fetchone()
        if row is None:
            raise Forbidden("Rejoin this room to participate.")
        return row

    def join(self, code, name, team):
        with self.lock, self.db:
            s = self.tick()
            if not secrets.compare_digest(str(code).encode(), s["code"].encode()):
                raise Forbidden("Check the six-digit room code.")
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
                self.db.execute("INSERT INTO practice VALUES(?, -1, 'lobby',0,0)",(self.player(token)["id"],))
            return token

    def practice_state(self, pid):
        row = self.db.execute("SELECT * FROM practice WHERE player=?",(pid,)).fetchone()
        idx,phase = row["idx"],row["phase"]
        if phase!="open":
            return idx,phase,0
        duration=self.deck["questions"][idx]["seconds"]
        if pid not in self.practice_clocks:
            self.practice_clocks[pid]=self.clock()+max(0,min(duration,row["deadline"]-self.wall()))
        left = max(0,min(duration,self.practice_clocks[pid]-self.clock()))
        if left==0:
            self.db.execute("UPDATE practice SET phase='reveal' WHERE player=?",(pid,))
            self.practice_clocks.pop(pid,None)
            phase="reveal"
        return idx,phase,left

    def practice_next(self,token,idx):
        with self.lock,self.db:
            if not self.practice_mode or self.meta()["phase"]!="practice":raise Conflict("Self-paced play is unavailable.")
            pid=self.player(token)["id"]
            current,phase,_=self.practice_state(pid)
            if idx!=current or phase not in ("lobby","reveal"):raise Conflict("Refresh your current round.")
            if current+1>=len(self.deck["questions"]):
                self.db.execute("UPDATE practice SET phase='finished' WHERE player=?",(pid,))
            else:
                duration=self.deck["questions"][current+1]["seconds"]
                self.practice_clocks[pid]=self.clock()+duration
                self.db.execute("UPDATE practice SET idx=idx+1,phase='open',deadline=?,start=? WHERE player=?",(self.wall()+duration,self.wall(),pid))

    def submit(self, token, idx, value):
        with self.lock, self.db:
            player = self.player(token)
            s = self.tick()
            personal=self.practice_mode and s["phase"]=="practice"
            if self.practice_mode and not personal:raise Conflict("Self-paced play is closed.")
            if personal:
                round_idx,phase,left=self.practice_state(player["id"])
            else:
                round_idx,phase,left=s["idx"],s["phase"],0
            if type(idx) is not int or idx != round_idx or idx < 0:
                raise Conflict("The host has moved to another round.")
            q = self.deck["questions"][idx]
            val = deck.response(q, value)
            old = self.db.execute("SELECT value FROM answers WHERE round=? AND player=?", (idx, player["id"])).fetchone()
            if old:
                if json.loads(old[0]) == val:
                    return
                raise Conflict("Your answer has already been recorded.")
            elapsed = q["seconds"]-left if personal else self.elapsed(s)
            if phase != "open" or elapsed >= q["seconds"]:
                raise Conflict("This round is closed for answers.")
            factor = 1 - .5 * min(1, elapsed/q["seconds"]) if self.deck["speed_bonus"] else 1
            points = int(q["points"] * factor + .5) if deck.correct(q, val) else 0
            self.db.execute("INSERT INTO answers VALUES(?,?,?,?,?)", (idx, player["id"], dump(val), points, elapsed))
            if personal:
                self.db.execute("UPDATE practice SET phase='reveal' WHERE player=?",(player["id"],))
                self.practice_clocks.pop(player["id"],None)

    def control(self, action, expected, idx, data=None):
        with self.lock, self.db:
            s = self.tick()
            phase, index = s["phase"], s["idx"]
            if expected != phase or idx != index:
                raise Conflict("The room changed. Refresh the host view.")
            q = self.deck["questions"][index] if index >= 0 else {}
            if action == "lock":
                self.db.execute("UPDATE room SET locked=?", (not s["locked"],))
            elif action == "deck" and phase == "lobby":
                new = deck.validate(data)
                if new["teams"] != self.deck["teams"] and self.db.execute("SELECT 1 FROM players LIMIT 1").fetchone():
                    raise Conflict("Team rosters are fixed once players have joined.")
                self.db.execute("UPDATE room SET deck=?", (dump(new),))
                self.deck = new
            elif action=="next" and phase=="lobby" and self.practice_mode:
                self.db.execute("UPDATE room SET phase='practice'")
            elif action=="finish" and phase=="practice":
                self.db.execute("UPDATE room SET phase='finished',idx=?,locked=1",(len(self.deck["questions"])-1,))
            elif action == "next" and phase in {"lobby", "reveal", "standings"} and index + 1 < len(self.deck["questions"]):
                q = self.deck["questions"][index+1]
                self.started = self.clock()
                self.db.execute("UPDATE room SET phase='open',idx=idx+1,elapsed=0,deadline=?", (self.wall()+q["seconds"],))
            elif action == "pause" and phase == "open":
                self.db.execute("UPDATE room SET phase='paused',elapsed=?,deadline=0", (self.elapsed(s),))
            elif action == "resume" and phase == "paused":
                self.started = self.clock()
                self.db.execute("UPDATE room SET phase='open',deadline=?", (self.wall()+q["seconds"]-s["elapsed"],))
            elif action == "reveal" and phase in {"open", "closed", "paused"}:
                self.db.execute("UPDATE room SET phase='reveal',elapsed=?,deadline=0", (self.elapsed(s),))
            elif action == "standings" and phase == "reveal":
                self.db.execute("UPDATE room SET phase='standings'")
            elif action == "finish" and phase in {"reveal", "standings"}:
                self.db.execute("UPDATE room SET phase='finished',locked=1")
            else:
                raise Conflict("That action is unavailable in this phase.")

    def qa(self, token, action, value):
        with self.lock, self.db:
            p = self.player(token)
            if self.meta()["phase"] == "finished":
                raise Conflict("This contest has finished.")
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

    def moderate(self, ident, status):
        if status not in {"published", "hidden", "answered"}:
            raise deck.Invalid("Unknown moderation status.")
        with self.lock, self.db:
            if not self.db.execute("UPDATE questions SET status=? WHERE id=?", (status, ident)).rowcount:
                raise Conflict("Unknown audience question.")

    def distribution(self,idx,typ):
        counts=collections.Counter()
        for row in self.db.execute("SELECT value FROM answers WHERE round=?",(idx,)):
            val=json.loads(row[0])
            for v in val if isinstance(val,list) else [val]:
                counts[str(deck.normal(v) if typ=="cloud" else v)]+=1
        return counts.most_common(40)

    def snapshot(self, token=None, host=False):
        with self.lock, self.db:
            s = self.tick()
            phase, idx = s["phase"], s["idx"]
            session_phase=phase
            person=self.player(token) if token else None
            personal=self.practice_mode and session_phase=="practice" and person is not None
            left=None
            if personal:
                idx,phase,left=self.practice_state(person["id"])
            reveal = phase in {"reveal", "standings", "finished"}
            q = self.deck["questions"][idx] if idx >= 0 else None
            data = dict(title=self.deck["title"], code=s["code"], phase=phase, index=idx, rounds=len(self.deck["questions"]),
                        teams=self.deck["teams"], locked=bool(s["locked"]), speed_bonus=self.deck["speed_bonus"],
                        question=deck.public_question(q) if q else None, seconds_left=left if left is not None else max(0,q["seconds"]-self.elapsed(s)) if q else 0,
                        self_paced=self.practice_mode,session_phase=session_phase,
                        players=self.db.execute("SELECT COUNT(*) FROM players").fetchone()[0],
                        received=self.db.execute("SELECT COUNT(*) FROM answers WHERE round=?", (idx,)).fetchone()[0])
            data["qa"] = [dict(r) for r in self.db.execute("""
                SELECT q.id,q.body,q.status,COUNT(v.player) AS votes FROM questions q LEFT JOIN votes v ON q.id=v.question
                WHERE (? OR q.status IN ('published','answered')) GROUP BY q.id ORDER BY votes DESC,q.id LIMIT 200""", (host,))]
            if token:
                player = person
                own = self.db.execute("SELECT value,points FROM answers WHERE round=? AND player=?", (idx, player["id"])).fetchone()
                data["me"] = dict(name=player["name"], team=player["team"], submitted=bool(own),
                                  value=json.loads(own["value"]) if own else None, points=own["points"] if own and reveal else None)
            if host:
                data["deck"] = self.deck
            if personal:
                data["total_score"]=self.db.execute("SELECT COALESCE(SUM(points),0) FROM answers WHERE player=?",(person["id"],)).fetchone()[0]
                data["received"]=int(bool(data["me"]["submitted"]))
            if q and q.get("live_results") and not self.practice_mode and not reveal and (not token or host or data["me"]["submitted"]):
                data["distribution"]=self.distribution(idx,q["type"])
            if q and reveal:
                data["answer"] = q.get("answer")
                data["explanation"] = q.get("explanation", "")
                if q["type"] in {"choice","poll","multiple","cloud","scale"} and not personal:
                    data["distribution"]=self.distribution(idx,q["type"])
                if personal:
                    data.pop("distribution",None)
                    return data
                rows = [dict(r) for r in self.db.execute("""
                    SELECT p.name,p.team,COALESCE(SUM(a.points),0) AS score FROM players p
                    LEFT JOIN answers a ON a.player=p.id AND a.round<=? GROUP BY p.id ORDER BY score DESC,p.normalized,p.id""", (idx,))]
                totals = collections.Counter()
                for row in rows:
                    if row["team"]: totals[row["team"]] += row["score"]
                data["leaders"] = ranks(rows)[:30]
                data["team_leaders"] = ranks([{"name":k,"score":v} for k,v in sorted(totals.items(),key=lambda it:(-it[1],it[0]))])
            return data

    def export(self):
        def cell(v):
            s = str(v)
            return "'"+s if s.lstrip().startswith(("=", "+", "-", "@")) or s.startswith(("\t", "\r", "\n")) else s
        with self.lock, self.db:
            out = io.StringIO(newline="")
            writer = csv.writer(out)
            writer.writerow(["player","team","round","question","answer","points","elapsed_seconds"])
            count = max(0,self.meta()["idx"]+1)
            if self.practice_mode:
                row=self.db.execute("SELECT MAX(idx) FROM practice").fetchone()
                count=max(0,(row[0] if row[0] is not None else -1)+1)
            players = self.db.execute("SELECT * FROM players ORDER BY id").fetchall()
            for p in players:
                by_round = {a["round"]:a for a in self.db.execute("SELECT * FROM answers WHERE player=?", (p["id"],))}
                for idx in range(count):
                    a = by_round.get(idx)
                    val = json.loads(a["value"]) if a else ""
                    writer.writerow([cell(p["name"]),cell(p["team"]),idx+1,cell(self.deck["questions"][idx]["prompt"]),
                                     cell(dump(val) if isinstance(val,list) else val),a["points"] if a else 0,
                                     round(a["elapsed"],3) if a else ""])
            return out.getvalue()


def ranks(rows):
    previous, rank = None, 0
    for i,row in enumerate(rows):
        if row["score"] != previous:
            previous,rank = row["score"], i+1
        row["rank"] = rank
    return rows
