"""Real Chrome run of the 0.3 live-audience UI: editor, presenter, projector and two phones.

    python3 tests/audience_browser.py --chromium /usr/bin/google-chrome [--shots DIR]

Walks the showcase deck through every slide type with keyboard presenter control, checks that
updates arrive without reloading, and fails on any JavaScript exception.
"""
import argparse
import json
import sys
import tempfile
import time
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"tools"))
import quiz  # noqa: E402

DECK = ROOT/"tools/contest/decks/science-show.quiz.json"


def run(chromium, shots=None):
    shot_dir = Path(shots) if shots else None
    if shot_dir:
        shot_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp, sync_playwright() as pw:
        room = quiz.Room(Path(tmp)/"room.sqlite", json.loads(DECK.read_text()))
        service = quiz.Contest(room, port=0, operator_port=0)
        service.start()
        browser = None
        try:
            browser = pw.chromium.launch(executable_path=chromium, args=["--no-sandbox", "--no-proxy-server", "--disable-dev-shm-usage"])
            ctx = lambda w, h: browser.new_context(viewport={"width": w, "height": h}, accept_downloads=True, has_touch=w < 500)
            host_ctx, disp_ctx, p1_ctx, p2_ctx = ctx(1440, 900), ctx(1600, 900), ctx(390, 844), ctx(412, 860)
            host, display, p1, p2 = [c.new_page() for c in (host_ctx, disp_ctx, p1_ctx, p2_ctx)]
            errors = []
            for pg in (host, display, p1, p2):
                pg.on("pageerror", lambda exc: errors.append(str(exc)))
            snap = lambda page, name: shot_dir and page.screenshot(path=str(shot_dir/f"{name}.png"))

            # --- editor: rename, add a poll from the gallery, paste Aiken text, save
            host.goto(service.host_url.replace("/host#", "/edit#"))
            expect(host.get_by_text("Session settings")).to_be_visible()
            title = host.get_by_label("Session title")
            title.fill("Science after dark · Bengaluru")
            host.locator(".e-item").last.click()                              # new slides go after the selected one
            host.get_by_role("button", name="+ Add slide").click()
            host.get_by_role("button", name="Ranking").first.click()
            expect(host.locator(".e-item.on")).to_contain_text("Ranking")
            host.get_by_role("button", name="⎘ Paste questions").click()
            host.locator("dialog textarea").fill("Which gas do plants absorb?\nA. Oxygen\nB. Carbon dioxide\nANSWER: B")
            host.get_by_role("button", name="Add to my slides").click()
            expect(host.locator(".e-item").last).to_contain_text("Which gas do plants absorb?")
            host.keyboard.press("Control+s")
            expect(host.locator("#e-status")).to_have_text("Saved ✓")
            snap(host, "01-editor")
            saved = room.snapshot(host=True)["deck"]
            assert saved["title"] == "Science after dark · Bengaluru" and len(saved["questions"]) == 14, saved["title"]

            # --- presenter + projector + two phones join
            host.goto(service.host_url)
            display.goto(service.audience_url)
            expect(display.get_by_text("Scan the code, or open")).to_be_visible()
            for page, name in ((p1, "Asha"), (p2, "মীরা")):
                page.goto(service.join_url)
                page.get_by_label("Display name").fill(name)
                page.get_by_role("button", name="Join").click()
                expect(page.get_by_text("You’re in")).to_be_visible()
                assert page.evaluate("document.documentElement.scrollWidth<=innerWidth"), "phone layout overflows"
            expect(display.locator(".names")).to_contain_text("মীরা")
            snap(display, "02-projector-lobby"); snap(p1, "03-phone-joined")
            expect(host.locator("#h-people")).to_have_text("2 joined")

            nxt = lambda: host.keyboard.press("ArrowRight")
            nxt()                                                            # welcome slide
            expect(display.locator(".st-prompt")).to_have_text("Welcome to Science after dark")
            nxt()                                                            # poll
            expect(p1.get_by_role("button", name="Space")).to_be_visible()
            p1.get_by_role("button", name="Space").click(); p2.get_by_role("button", name="Engines").click()
            expect(display.locator(".bar").first.locator("b")).to_have_text("1")
            snap(display, "04-projector-poll"); snap(p1, "05-phone-poll-result")
            p1.get_by_role("button", name="React 👏").click()
            nxt()                                                            # word cloud
            for page, word in ((p1, "Electricity"), (p2, "electricity")):
                page.get_by_label("Your answer").fill(word); page.get_by_role("button", name="Submit").click()
            expect(display.locator("#st-cloud canvas")).to_be_visible()
            time.sleep(1.2); snap(display, "06-projector-cloud")
            nxt()                                                            # quiz: pick one
            expect(display.locator("#st-ring svg")).to_be_visible()
            p1.get_by_role("button", name="Neptune").click(); p2.get_by_role("button", name="Mars").click()
            expect(display.get_by_text("Everyone has answered")).to_be_visible()
            nxt()                                                            # reveal
            expect(display.locator(".tile.right")).to_contain_text("Neptune")
            expect(p1.get_by_text("Correct!")).to_be_visible(); expect(p2.get_by_text("Not quite")).to_be_visible()
            snap(display, "07-projector-reveal"); snap(p1, "08-phone-correct")
            nxt()                                                            # leaderboard
            expect(display.locator(".rk").first).to_contain_text("Asha")
            snap(display, "09-projector-leaderboard")
            nxt()                                                            # multiple
            for page in (p1, p2):
                page.get_by_role("button", name="Copper").click(); page.get_by_role("button", name="Aluminium").click()
                page.get_by_role("button", name="Submit").click()
            nxt(); nxt(); nxt()                                              # reveal, leaderboard, number
            p1.get_by_label("Your answer").fill("3"); p1.get_by_role("button", name="Submit").click()
            host.keyboard.press("p")
            expect(display.get_by_text("⏸ Paused")).to_be_visible()
            host.keyboard.press("p")
            p2.get_by_label("Your answer").fill("2.5"); p2.get_by_role("button", name="Submit").click()
            nxt(); nxt(); nxt()                                              # reveal, leaderboard, scale
            p1.get_by_role("button", name="5", exact=True).click(); p1.get_by_role("button", name="Submit").click()
            expect(display.locator("#st-avg")).to_have_text("5.0")
            nxt()                                                            # ranking
            p1.get_by_role("button", name="Move Planetarium show up").click()
            p1.get_by_role("button", name="Submit order").click()
            expect(display.locator(".bar").first).to_contain_text("Robotics lab")
            nxt()                                                            # open-ended ideas
            p1.get_by_label("Your idea").fill("A monsoon simulator"); p1.get_by_role("button", name="Share idea (2 left)").click()
            expect(display.locator(".ic")).to_contain_text("A monsoon simulator")
            p2.get_by_role("button", name="▲ 0").click()
            expect(display.locator(".ic b")).to_have_text("▲ 1")
            snap(display, "10-projector-ideas")
            nxt()                                                            # Q&A slide
            p2.locator("#p-extra").get_by_placeholder("Type your question").fill("Why is the sky blue?")
            p2.locator("#p-extra").get_by_role("button", name="Send").click()
            host.get_by_role("button", name="Show").first.click()
            expect(display.locator(".qalist .q")).to_contain_text("Why is the sky blue?")
            snap(host, "11-presenter-qa")
            nxt()                                                            # spinner
            host.keyboard.press("s")
            expect(display.locator("#st-winner")).to_contain_text("🎉", timeout=9000)
            winner = display.locator("#st-winner").inner_text()
            assert any(n in winner for n in ("Asha", "মীরা")), winner
            snap(display, "12-projector-spinner")
            host.keyboard.press("ArrowLeft")                                  # back to review the Q&A slide
            expect(host.locator("#h-status")).to_contain_text("review")
            nxt()
            nxt(); nxt()                                                     # thank-you slide, ranking slide added in editor
            p1.get_by_role("button", name="Submit order").click()
            nxt()                                                            # pasted quiz question
            p1.get_by_role("button", name="Carbon dioxide").click(); p2.get_by_role("button", name="Oxygen").click()
            nxt(); nxt()                                                     # reveal → final (last slide skips the per-round board)
            expect(display.locator(".podium")).to_be_visible()
            expect(p1.get_by_text("Final rank #1")).to_be_visible()
            snap(display, "13-projector-podium"); snap(p1, "14-phone-final")

            with host.expect_download() as dl:
                host.get_by_role("button", name="⇩ Summary").click()
            summary = Path(dl.value.path()).read_text(encoding="utf-8-sig")
            for needle in ("A monsoon simulator", "Why is the sky blue?", "Electricity".casefold(), "Borda score"):
                assert needle in summary, needle
            assert not errors, errors
            print("PASS Chrome: editor (gallery, Aiken paste, autosave), presenter keys, projector updates without reload, "
                  "two phones incl. Bengali name, poll/cloud/quiz/multiple/number/pause/scale/ranking/ideas/Q&A/spinner, "
                  "back-navigation review, podium, summary CSV; zero JS exceptions.")
        except Exception:
            if shot_dir:
                for name, page in (("host", host), ("display", display), ("p1", p1), ("p2", p2)):
                    page.screenshot(path=str(shot_dir/f"fail-{name}.png"))
            raise
        finally:
            if browser:
                browser.close()
            service.close()


if __name__ == "__main__":
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument("--chromium", required=True)
    a.add_argument("--shots")
    args = a.parse_args()
    run(args.chromium, args.shots)
