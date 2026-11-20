"""Real Chrome run of the green-screen booth with Chrome's simulated camera.

    python3 tests/greenscreen_browser.py --chromium /usr/bin/google-chrome [--shots DIR]

The simulated camera plays a generated clip: a figure (orange face, grey shirt) in front of green.
The test reads the booth canvas and checks that the green became the background while the figure
kept its colours; it then switches backgrounds (including the sample video), checks the overlay,
takes a photo and a video clip and downloads both as a phone would, saves calibration from the
setup panel, and fails on any JavaScript exception.
"""

import argparse
import base64
import io
import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from hashlib import sha256
from pathlib import Path

import numpy as np
from PIL import Image
from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import greenscreen  # noqa: E402
from booth import config  # noqa: E402
from booth.captures import Store  # noqa: E402

GREEN, ORANGE, GREY = (0, 177, 64), (230, 120, 40), (60, 60, 60)
BLUE_BG, PURPLE_BG = (40, 80, 200), (150, 40, 160)


def camera_clip(path: Path, width=640, height=360, frames=15):
    """A Y4M clip for --use-file-for-fake-video-capture (BT.601 limited-range 4:2:0)."""
    rgb = np.zeros((height, width, 3), np.float32)
    rgb[:] = GREEN
    left, right = int(width * 0.38), int(width * 0.62)
    rgb[int(height * 0.25) : int(height * 0.7), left:right] = ORANGE
    rgb[int(height * 0.7) :, left - 30 : right + 30] = GREY
    r, g, b = (rgb[..., i] / 255 for i in range(3))
    y = 16 + 65.481 * r + 128.553 * g + 24.966 * b
    u = 128 - 37.797 * r - 74.203 * g + 112.0 * b
    v = 128 + 112.0 * r - 93.786 * g - 18.214 * b

    def half(plane):
        return plane.reshape(height // 2, 2, width // 2, 2).mean(axis=(1, 3))

    planes = [np.clip(p, 0, 255).round().astype(np.uint8).tobytes() for p in (y, half(u), half(v))]
    with path.open("wb") as out:
        out.write(f"YUV4MPEG2 W{width} H{height} F15:1 Ip A1:1 C420jpeg\n".encode())
        for _ in range(frames):
            out.write(b"FRAME\n" + b"".join(planes))


def booth_project(folder: Path) -> Path:
    assets = folder / "assets"
    assets.mkdir(parents=True)
    Image.new("RGB", (1920, 1080), BLUE_BG).save(assets / "blue.png")
    Image.new("RGB", (1920, 1080), PURPLE_BG).save(assets / "purple.png")
    overlay = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
    overlay.paste((255, 255, 255, 255), (1720, 40, 1880, 200))
    overlay.save(assets / "overlay.png")
    shutil.copy(ROOT / "examples/16-green-screen/assets/space.webm", assets / "space.webm")
    files = {"blue": "blue.png", "purple": "purple.png", "overlay": "overlay.png", "space": "space.webm"}
    project = {
        "format": "openexhibit",
        "version": 1,
        "title": "Booth test",
        "assets": {
            key: {"path": f"assets/{name}", "sha256": sha256((assets / name).read_bytes()).hexdigest()}
            for key, name in files.items()
        },
        "extensions": {
            "greenscreen": {
                "title": "Booth test",
                "backgrounds": [
                    {"asset": "blue", "name": "Blue"},
                    {"asset": "purple", "name": "Purple"},
                    {"asset": "space", "name": "Space video"},
                ],
                "overlay": "overlay",
                "countdown": 1,
                "clip_seconds": 2,
                "cycle_seconds": 0,
                "mirror": False,
            }
        },
    }
    (folder / "project.oes.json").write_text(json.dumps(project))
    return folder / "project.oes.json"


def near(pixel, expected, tolerance):
    return all(abs(int(a) - int(b)) <= tolerance for a, b in zip(pixel[:3], expected))


def canvas(page) -> Image.Image:
    data = page.evaluate("() => document.getElementById('stage').toDataURL('image/png')")
    return Image.open(io.BytesIO(base64.b64decode(data.split(",", 1)[1]))).convert("RGB")


def wait_for_pixels(page, checks, what, seconds=12):
    """checks: [(x, y, colour, tolerance)] on the 1920 × 1080 canvas; colour None means 'dark'."""
    deadline = time.monotonic() + seconds
    while True:
        image = canvas(page)
        seen = [image.getpixel((x, y)) for x, y, _, _ in checks]
        ok = [
            (sum(p) < 150) if colour is None else near(p, colour, tol)
            for p, (_, _, colour, tol) in zip(seen, checks)
        ]
        if all(ok):
            return image
        if time.monotonic() > deadline:
            raise AssertionError(f"{what}: saw {seen}")
        time.sleep(0.25)


def fetch(url):
    with urllib.request.urlopen(url, timeout=10) as response:
        return response.status, response.headers, response.read()


def run(chromium, shots=None):
    shot_dir = Path(shots) if shots else None
    if shot_dir:
        shot_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp, sync_playwright() as pw:
        tmp = Path(tmp)
        clip_file = tmp / "camera.y4m"
        camera_clip(clip_file)
        project = booth_project(tmp / "exhibit")
        booth = config.from_project(project, tmp)
        settings_file = tmp / "calibration.json"
        service = greenscreen.BoothService(
            booth, Store(tmp / "captures", 30), "127.0.0.1", 0, 0, settings_file
        )
        service.start()
        browser = page = None
        try:
            browser = pw.chromium.launch(
                executable_path=chromium,
                args=[
                    "--no-sandbox",
                    "--no-proxy-server",
                    "--disable-dev-shm-usage",
                    "--use-fake-ui-for-media-stream",
                    "--use-fake-device-for-media-stream",
                    f"--use-file-for-fake-video-capture={clip_file}",
                    "--autoplay-policy=no-user-gesture-required",
                    "--enable-unsafe-swiftshader",
                ],
            )
            page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()
            errors = []
            page.on("pageerror", lambda exc: errors.append(str(exc)))
            page.goto(service.booth_url)
            expect(page.locator("body")).to_have_attribute("data-camera", "live", timeout=15000)
            assert "#" not in page.url, "the token should leave the address bar"

            # --- keying: green → background, figure kept, overlay on top
            figure = [(960, 500, ORANGE, 24), (960, 950, GREY, 18)]
            wait_for_pixels(
                page,
                [(100, 100, BLUE_BG, 18), (1800, 900, BLUE_BG, 18), (1800, 120, (255, 255, 255), 6)] + figure,
                "keyed over the blue background",
            )
            expect(page.locator("body")).to_have_attribute("data-present", "yes", timeout=5000)
            page.keyboard.press("ArrowRight")
            wait_for_pixels(page, [(100, 100, PURPLE_BG, 18)] + figure, "second background")
            page.get_by_role("button", name="Space video").click()
            wait_for_pixels(page, [(1200, 120, None, 0)] + figure, "video background")
            first = page.evaluate("() => document.getElementById('stage').toDataURL('image/png').length")
            time.sleep(1.0)
            assert (
                page.evaluate("() => document.getElementById('stage').toDataURL('image/png').length") != first
            ), "the video background should move"
            page.get_by_role("button", name="Purple").click()
            fps = page.evaluate(
                """() => new Promise(done => {
                    let frames = 0;
                    const start = performance.now();
                    const count = () => (++frames, performance.now() - start < 2000
                        ? requestAnimationFrame(count) : done(frames / ((performance.now() - start) / 1000)));
                    requestAnimationFrame(count);
                })"""
            )
            if shot_dir:
                page.screenshot(path=str(shot_dir / "booth.png"))

            # --- photo: countdown, QR, download page, the JPEG a phone receives
            page.get_by_role("button", name="Take a photo").click()
            result = page.locator("#result")
            expect(result).to_be_visible(timeout=15000)
            code = result.get_attribute("data-code")
            page.wait_for_function(
                "() => document.getElementById('qr').naturalWidth > 0"
            )  # the QR code loaded
            status, _, html = fetch(f"{service.download_root}/p/{code}")
            assert status == 200 and b"Save photo" in html
            _, headers, photo = fetch(f"{service.download_root}/p/{code}/file?download=1")
            assert headers["Content-Type"] == "image/jpeg" and "attachment" in headers["Content-Disposition"]
            picture = Image.open(io.BytesIO(photo)).convert("RGB")
            assert picture.size == (1920, 1080), picture.size
            assert near(picture.getpixel((100, 100)), PURPLE_BG, 26), picture.getpixel((100, 100))
            assert near(picture.getpixel((960, 500)), ORANGE, 30), picture.getpixel((960, 500))
            if shot_dir:
                page.screenshot(path=str(shot_dir / "photo-result.png"))
            page.keyboard.press("Escape")
            expect(result).to_be_hidden()

            # --- video clip: countdown, recording, upload, a playable file for the phone
            page.keyboard.press("r")
            expect(page.locator("#recording")).to_be_visible(timeout=5000)
            expect(result).to_be_visible(timeout=20000)
            clip_code = result.get_attribute("data-code")
            assert clip_code != code
            status, _, html = fetch(f"{service.download_root}/p/{clip_code}")
            assert status == 200 and b"Save video" in html
            _, headers, clip = fetch(f"{service.download_root}/p/{clip_code}/file")
            suffix = ".mp4" if headers["Content-Type"] == "video/mp4" else ".webm"
            clip_path = tmp / f"clip{suffix}"
            clip_path.write_bytes(clip)
            probe = json.loads(
                subprocess.check_output(
                    ["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-of", "json"]
                    + ["-show_entries", "stream=width,height,nb_read_packets", str(clip_path)]
                )
            )["streams"][0]
            assert (probe["width"], probe["height"]) == (1280, 720), probe
            # Frames follow the booth's drawing rate; software WebGL in a container draws only a few per second.
            assert int(probe["nb_read_packets"]) >= 3, probe
            still = tmp / "clip-frame.png"
            subprocess.run(
                ["ffmpeg", "-loglevel", "error", "-y", "-i", str(clip_path), "-frames:v", "1", str(still)],
                check=True,
            )
            frame = Image.open(still).convert("RGB")
            assert near(frame.getpixel((640, 333)), ORANGE, 40), frame.getpixel((640, 333))
            assert near(frame.getpixel((60, 60)), PURPLE_BG, 40), frame.getpixel((60, 60))
            page.get_by_role("button", name="Done").click()

            # --- setup: matte view, colour detection, saved calibration
            page.keyboard.press("Control+Shift+S")
            setup = page.locator("#setup")
            expect(setup).to_be_visible()
            setup.get_by_label("Show matte (white = kept)").check()
            wait_for_pixels(page, [(100, 100, (0, 0, 0), 10), (960, 500, (255, 255, 255), 10)], "matte view")
            setup.get_by_role("button", name="Detect from edges").click()
            detected = setup.locator("input[type=color]").input_value()
            rgb = tuple(int(detected[i : i + 2], 16) for i in (1, 3, 5))
            assert near(rgb, GREEN, 24), detected
            setup.locator("label.slider", has_text="Tolerance").locator("input").evaluate(
                "el => { el.value = '0.31'; el.dispatchEvent(new Event('input')); }"
            )
            setup.get_by_role("button", name="Save").click()
            expect(page.locator("#message")).to_contain_text("saved")
            saved = json.loads(settings_file.read_text())
            assert saved["key"]["tolerance"] == 0.31 and saved["key"]["color"] == detected, saved["key"]
            assert service.settings["key"]["tolerance"] == 0.31
            setup.get_by_role("button", name="Close").click()
            wait_for_pixels(page, [(100, 100, PURPLE_BG, 18)], "normal view after setup")

            assert not errors, errors
            print(
                "PASS Chrome booth: simulated camera keyed over picture and video backgrounds with overlay, "
                f"photo (1920×1080 JPEG) and {suffix[1:].upper()} clip (1280×720, {probe['nb_read_packets']} frames) "
                "downloaded as a phone would, matte view, colour detection and saved calibration; "
                f"{fps:.1f} frames/s drawn; zero JS exceptions."
            )
        except Exception:
            if shot_dir and page:
                page.screenshot(path=str(shot_dir / "fail-booth.png"))
            raise
        finally:
            if browser:
                browser.close()
            service.close()


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--chromium", required=True)
    cli.add_argument("--shots")
    options = cli.parse_args()
    run(options.chromium, options.shots)
