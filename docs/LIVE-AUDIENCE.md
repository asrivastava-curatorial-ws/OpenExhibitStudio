# Live audience sessions

Interactive presentations in the style of AhaSlides and Mentimeter, running entirely on your own
computer and local network. Visitors join from a phone browser — no app, no account, no internet.

## Run a session from Studio

1. Open an exhibit (the *Live audience talk* template is a good start) and go to **Live audience**.
2. **Who can join** — choose *Local network* so phones on the same Wi-Fi/LAN can reach this
   computer. *This computer only* is for rehearsing with browser windows on one machine.
3. **Pace** — *Presenter-led* (you move everyone through the slides) or *Self-paced* (each person
   works through the questions on their own; useful for school groups arriving at different times).
4. Press **Start session and present**. Two things open in your browser:
   - the **presenter console** (private: only reachable on this computer), and
   - via **F** in the console, the **projector window** — drag it to the projector and press F11.
5. Visitors scan the QR code on the projector or type the address and six-digit room code.

**Edit slides** opens the slide editor. Edits save to the running session automatically; press
**Save slides into this exhibit** in Studio and then save the project to keep them in the exhibit
file. **Stop session** ends it; answers stay in the session database shown in Studio.

## Presenter controls

| Key / clicker | Action |
| --- | --- |
| → , Space, Page Down, Enter | Next step — start, reveal the answer, show the leaderboard, next slide (the button label says which) |
| ← , Page Up | Previous slide (already-played slides are shown with their results, not reopened) |
| P | Pause / resume the timer |
| S | Spin the wheel (spinner slides) |
| L | Lock / unlock joining |
| F | Open the projector window |

Presentation clickers send Page Down / Page Up, so they work without setup. Rapid double presses
move two steps. A scored question closes by itself when its timer ends or when everyone has
answered.

The right-hand panel shows the next slide, your presenter notes, and tabs for **Q&A** (approve,
hide or mark questions answered), **Ideas** (moderate open-ended answers) and **People**.

## Slide types

| Type | What participants do | Shown on the projector |
| --- | --- | --- |
| Content | Read a heading, text (bullets with “- ”) and a picture | Title, big-statement or text-and-picture layouts |
| Pick one | Tap one option (scored) | Coloured tiles; reveal marks the answer and shows counts |
| Pick several | Select every correct option (scored, all-or-nothing) | Tiles with counts |
| Type an answer | Type text; several spellings can be accepted (scored) | Correct answer on reveal |
| Numeric answer | Enter a number within a tolerance (scored) | Correct answer on reveal |
| Correct order | Drag items into order (scored) | Correct sequence on reveal |
| Match pairs / Categorise | Choose a partner or group for each item (scored) | Correct pairs on reveal |
| Poll | Tap one option | Live bars |
| Word cloud | Send a word or short phrase | Live word cloud (same words grow) |
| Rating scale | Rate 1–N with labelled ends | Histogram and average |
| Ranking | Drag options into a personal ranking | Bars by Borda score |
| Open-ended ideas | Share up to N ideas; upvote others | Idea cards sorted by votes |
| Audience Q&A | Ask questions; upvote approved ones | Approved questions by votes |
| Spinner wheel | Watch | Animated wheel of participants or your own entries |

Scored questions award full points for a correct answer, or — with the speed bonus on — from full
points down to half as the timer runs out. Team scores add up their members. Equal scores share a
rank. Polls and other opinion slides can be untimed (they stay open until you move on) and can
show results live or only after you reveal them.

Everyone can send emoji reactions (they float up the projector) and questions at any time, unless
you switch that off in **Session settings**.

## The slide editor

- **+ Add slide** opens a gallery of all types; new slides go after the selected one. Drag slides
  in the list to reorder; hover for duplicate and delete.
- The right panel edits the selected slide: text, options (tick the correct ones), timer, points,
  explanation shown after the answer, picture (resized automatically), presenter notes.
- **Session settings**: teams, leaderboard frequency (after each question / at the end / never),
  speed bonus, anonymous joining, reactions, Q&A, and a light projector theme for bright rooms.
- **Paste questions** accepts Moodle's Aiken format, so existing question banks paste straight in:

  ```text
  What is the chemical symbol for gold?
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
  ```

  One letter makes a *Pick one* question, several letters *Pick several*; a block without an
  `ANSWER:` line becomes a poll, and a block of plain lines becomes a content slide.
- **Import file** reads slide decks (`.quiz.json`), Aiken text files (`.txt`), PowerPoint
  (`.pptx` — slide text and one embedded picture per slide) and up to 60 PDF pages as pictures (needs
  Poppler's `pdftoppm`). **Download** saves the deck as JSON.

Slides can be edited only before a session starts (in the lobby). To change a running session's
slides, stop it, edit, and start a new session.

## Results

- **⇩ Answers** — one row per participant per scored or poll question (CSV, opens in Excel or
  LibreOffice).
- **⇩ Summary** — poll counts, word frequencies, ranking scores, ideas with votes, spinner results
  and every audience question: the sheet to keep for evaluation reports.

Both exports protect against spreadsheet formula injection. Each session has its own SQLite
database (shown in Studio). **Resume a saved session** reopens it with all participants and
answers, for example after a power cut; a question that was open resumes paused.

## On a projection-mapped surface

The projector window is an ordinary browser page. For warped or edge-blended projection, add the
**live audience board** component to a scene (Live audience → *Add live audience board*), assign
that scene to the projector output and run the exhibit in the Player. The Player draws the current
slide, results and standings through the output's warp, mask and blend.

## Without Studio

```sh
python3 tools/quiz.py --bind 192.168.1.20 --deck tools/contest/decks/science-show.quiz.json --db talk.sqlite --open-host
python3 tools/quiz.py --bind 192.168.1.20 --deck my.quiz.json --db class.sqlite --self-paced
```

The service prints the presenter, projector and join links. Use the address of the computer's
network interface (`ip -4 addr` on Linux, `ipconfig` on Windows).

## Network, privacy and security

- Phones connect to TCP port **8786** on the presenting computer. Allow it in the firewall
  (Windows asks the first time). Guest Wi-Fi networks that isolate devices from each other block
  phones from reaching the computer — use a staff network or a dedicated router.
- The presenter console listens on port **8787** on `127.0.0.1` only, behind a random token in
  the link Studio opens. Phones and other computers cannot reach it.
- Traffic is plain HTTP on the local network. Run sessions on a network you control.
- Only display names (or *Guest N* when anonymous) and answers are stored, in the session
  database on this computer. Delete the database file to delete the session.
- Updates reach phones within a fraction of a second (long-polling); tested with 64 simultaneous
  participants on one computer. Larger audiences and specific phones still need a rehearsal on
  site.

## How this compares with AhaSlides

Covered: the slide types above, live results, leaderboards, teams, speed scoring, self-paced mode,
Q&A with moderation and upvotes, reactions, spinner wheel, presenter notes, clicker control,
PowerPoint/PDF/Aiken import and exports. Not covered: cloud hosting and remote participants over
the internet, PowerPoint/Google Slides add-ins, AI question generation, image-choice and
pin-on-image questions, audio/video slides, and per-slide themes.
