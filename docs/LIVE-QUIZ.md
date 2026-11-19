# Hold a museum quiz contest

## Start a room

1. Connect the host computer, audience phones and any scoreboard computer to the same local network. Internet access is optional. On a single laptop, use separate browser profiles for separate participants.
2. In Studio, use **File → Examples → Science after hours · live contest**. Choose **View → Live quiz contest**.
3. For phones, choose the host’s Wi-Fi or Ethernet IPv4 address. For a rehearsal on one computer, choose **127.0.0.1**. Select **Host-paced live** or **Self-paced individual** and click **Start new contest**.
4. The private host console opens on the host computer. Use **Projector view** for an ordinary full-screen browser display. For a warped projection, open the exhibit in the standalone Player. Its live scoreboard layer renders through the assigned projector’s warp, mask and blend settings.
5. Participants scan the projected QR or enter the displayed local URL and room code. They choose a display name and, when offered, a team. No installation, email address or account is required. If a guest Wi-Fi network isolates clients, use a network that permits the phones to reach the selected host on TCP 8786.

## Run the contest

**Start contest** opens the first round. The server decides the deadline and records one answer per participant per round. A phone can reconnect in the same browser profile and retain its entry. Keep separate profiles or devices for different entrants.

Use **Pause** for a discussion, **Resume** to restart the clock and **Reveal answer** to publish the answer and explanation. **Show standings** displays individual and team scores. **Next round** advances. **Lock joining** closes registration while existing participants continue. **Finish contest** closes entries. Export the answer-by-answer CSV with **Export results**. A missed round has a blank answer and zero points.

In self-paced mode the host opens the session once. Each participant starts, answers, views feedback and advances on their own device. Individual round timers start when that participant opens the round. The host ends the session to publish shared standings. A self-paced room is useful when school groups arrive at different times.

| Round | What the visitor does |
| --- | --- |
| Pick one, true/false or picture question | Select one option. A true/false round uses two choices. Any round can carry a local PNG or JPEG illustration. |
| Pick several | Select the complete set of correct choices. |
| Type an answer | Enter text. The author can allow several spellings. Marking normalizes Unicode, case and repeated spaces. |
| Numeric answer | Enter a number within the author’s absolute tolerance. |
| Correct order | Use the labelled up and down buttons to arrange all items. Enter the choices in a different order from the answer when authoring. |
| Match pairs or categorise | Choose a counterpart for each left-hand item. Categories can repeat. |
| Poll, rating scale or word cloud | Submit an ungraded response. The author can display arriving responses live or wait for reveal. |
| Content slide | Read an explanation or picture between rounds. |

**Scoring.** With speed bonus off, a correct answer receives the round’s full point value. With speed bonus on, the award decreases linearly from full points at opening to half the maximum just before expiry. Paused time is excluded. Incorrect, unanswered and late entries score zero. Matching and multi-select items use all-or-nothing marking. Team scores sum the members’ points. Equal scores share a rank.

**Audience questions.** Participants can ask questions while the contest runs. The host publishes, hides or marks each question answered. A participant can upvote a published question once. Unmoderated word-cloud entries appear publicly if the author enables live results for that round.

## Create and carry your own competition

In the host lobby choose **Edit contest**. Set the title and teams, add or reorder rounds and supply answers and explanations. Choose **Save deck to room**. To carry it to another installation, choose **Download deck** in the editor. In Studio choose **Import deck into exhibit**, then save or export your project. This explicit import keeps the project file and current event’s attendance records independent.

The editor imports version 1 quiz JSON, slide text and an embedded picture from PPTX, or up to 60 PDF pages as local images. PDF conversion needs Poppler. The PPTX importer reads slides in presentation order. Use a PDF export when exact page appearance matters. External links, macros, animations, slide transitions and original Office layouts are outside the PPTX conversion. Imported content slides can be converted to questions.

## Restart, backup and local access

Each new contest gets a separate SQLite database and a fresh room code. Studio displays the database path. Stop its service before copying the database. For a live database backup use SQLite’s backup command so journaled transactions are included. **Resume saved contest** opens the same room and restores participants’ answers. An interrupted live round reopens paused if time remains, or closed if its deadline has passed. The host reviews it before continuing. Participant tokens remain valid for that saved room. Operator access gets a fresh private link on each launch.

The default public port is 8786. The operator listener binds to loopback on port 8787 and checks its private bearer token. Only share the visitor URL or QR. Standard LAN mode uses HTTP. Use an isolated venue LAN for this mode. Results and display names stay in the room database until its operator removes it.

A headless host can run the following commands from the release directory. Substitute the address of the host’s actual local interface. The program prints the host, projector and join links.

```sh
python3 tools/quiz.py --bind 192.168.1.20 --db event.sqlite --open-host
python3 tools/quiz.py --bind 192.168.1.20 --deck my.quiz.json --db separate-event.sqlite --self-paced
```

The native scoreboard defaults to the local operator listener. A Player on a second computer can use the public listener with `bash player.sh examples/14-live-quiz/project.oes.json --quiz-url http://192.168.1.20:8786`. On Windows use `Player.cmd --project "C:\Exhibits\live-quiz\project.oes.json" --quiz-url http://192.168.1.20:8786`. The address is an operator-provided launch option. Project documents cannot choose a remote polling destination.

The sample deck is `tools/contest/museum.quiz.json`. This independent implementation uses the publicly documented AhaSlides quiz, poll, word-cloud, Q&A and reporting workflows as design references. [AhaSlides features](https://ahaslides.com/features/) · [Quiz formats](https://ahaslides.com/features/online-quiz-creator/)
