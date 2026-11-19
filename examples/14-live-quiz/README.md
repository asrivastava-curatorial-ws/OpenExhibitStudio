# Science after hours · team quiz contest

A ten-round team quiz (Faraday, Raman and Curie) with a projection-mapped live scoreboard.

1. Open this project in Studio and go to **Live audience**.
2. Under **Who can join**, choose the local network (or *This computer only* to rehearse with
   separate browser windows), then press **Start session and present**.
3. Phones scan the QR code, pick a name and a team. Move through the rounds with → in the
   presenter console: open a round, reveal the answer, show the leaderboard.
4. Open the project in the Player to show the live board through the output's warp and blend
   (`bash player.sh examples/14-live-quiz/project.oes.json`).

The deck covers every scored question type plus a poll, a word cloud and a rating scale. See
[docs/LIVE-AUDIENCE.md](../../docs/LIVE-AUDIENCE.md) for scoring, exports and resuming a session.
