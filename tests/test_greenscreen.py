"""Green-screen booth service: settings cleaning, exhibit loading, capture storage and HTTP access."""

import http.client
import io
import json
import socket
import sys
import tempfile
import unittest
import zipfile
from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import greenscreen  # noqa: E402
from booth import config  # noqa: E402
from booth.captures import Store  # noqa: E402

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
WEBM = b"\x1a\x45\xdf\xa3" + b"\x00" * 64
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def write_project(folder: Path, extension: dict, files: dict) -> Path:
    assets = {}
    for asset_id, (name, data) in files.items():
        (folder / "assets").mkdir(exist_ok=True)
        (folder / "assets" / name).write_bytes(data)
        assets[asset_id] = {"path": f"assets/{name}", "sha256": sha256(data).hexdigest()}
    project = {
        "format": "openexhibit",
        "version": 1,
        "title": "Moon walk",
        "assets": assets,
        "extensions": {"greenscreen": extension},
    }
    (folder / "project.oes.json").write_text(json.dumps(project))
    return folder / "project.oes.json"


class SettingsTests(unittest.TestCase):
    def test_defaults_fill_missing_and_wrong_values(self):
        clean = config.clean_settings(
            {"countdown": "3", "key": {"tolerance": 9, "color": "green"}, "mirror": 1}
        )
        self.assertEqual(clean["countdown"], config.DEFAULTS["countdown"])
        self.assertEqual(clean["key"]["tolerance"], 1.0)
        self.assertEqual(clean["key"]["color"], "#00b140")
        self.assertIs(clean["mirror"], True)
        self.assertEqual(clean["person"]["crop"], [0.0, 0.0, 0.0, 0.0])
        self.assertEqual(config.clean_settings(None), config.clean_settings({}))

    def test_values_are_clamped_and_kept(self):
        clean = config.clean_settings(
            {
                "clip_seconds": 999,
                "keep_minutes": 0,
                "key": {"color": "#0047BB", "softness": 0},
                "person": {"scale": 0.5, "crop": [0.1, 0.9, -1, 0.2]},
                "title": "  Stand on the Moon  ",
            }
        )
        self.assertEqual(clean["clip_seconds"], 30)
        self.assertEqual(clean["keep_minutes"], 1)
        self.assertEqual(clean["key"]["color"], "#0047bb")
        self.assertEqual(clean["key"]["softness"], 0.005)
        self.assertEqual(clean["person"]["crop"], [0.1, 0.45, 0.0, 0.2])
        self.assertEqual(clean["title"], "Stand on the Moon")


class ProjectTests(unittest.TestCase):
    def test_folder_project_with_backgrounds_overlay_and_warnings(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            project = write_project(
                folder,
                {
                    "backgrounds": [
                        {"asset": "a_moon", "name": "On the Moon", "fit": "contain"},
                        {"asset": "a_old", "name": "Old film"},
                        {"asset": "a_missing"},
                    ],
                    "overlay": "a_frame",
                    "countdown": 2,
                },
                {"a_moon": ("moon.webm", WEBM), "a_old": ("old.ogv", b"OggS"), "a_frame": ("frame.png", PNG)},
            )
            booth = config.from_project(project, folder / "unused")
            self.assertEqual([m.name for m in booth.backgrounds], ["On the Moon"])
            self.assertEqual(booth.backgrounds[0].fit, "contain")
            self.assertEqual(booth.backgrounds[0].kind, "video")
            self.assertEqual(booth.overlay.mime, "image/png")
            self.assertEqual(booth.settings["title"], "Moon walk")
            self.assertEqual(booth.settings["countdown"], 2)
            self.assertEqual(len(booth.warnings), 2)
            self.assertIn("Ogg Theora", booth.warnings[0])

    def test_package_is_verified_and_unpacked(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "src"
            folder.mkdir()
            project = write_project(
                folder,
                {"backgrounds": [{"asset": "a_moon", "name": "Moon"}]},
                {"a_moon": ("moon.webm", WEBM)},
            )
            package = Path(tmp) / "booth.oex"
            with zipfile.ZipFile(package, "w") as archive:
                archive.write(project, "project.oes.json")
                archive.write(folder / "assets" / "moon.webm", "assets/moon.webm")
                manifest = {
                    "project.oes.json": sha256(project.read_bytes()).hexdigest(),
                    "assets/moon.webm": sha256(WEBM).hexdigest(),
                }
                archive.writestr("manifest.json", json.dumps(manifest))
            unpacked = Path(tmp) / "unpacked"
            unpacked.mkdir()
            booth = config.from_project(package, unpacked)
            self.assertEqual(booth.backgrounds[0].path.read_bytes(), WEBM)
            self.assertTrue(booth.backgrounds[0].path.is_relative_to(unpacked))

    def test_escaping_asset_paths_and_missing_booth_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            project = write_project(folder, {"backgrounds": [{"asset": "a_bad"}]}, {})
            data = json.loads(project.read_text())
            data["assets"]["a_bad"] = {"path": "../../etc/passwd", "sha256": "0" * 64}
            project.write_text(json.dumps(data))
            booth = config.from_project(project, folder)
            self.assertEqual(booth.backgrounds, [])
            self.assertIn("not among", booth.warnings[0])
            del data["extensions"]["greenscreen"]
            project.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                config.from_project(project, folder)


class CaptureTests(unittest.TestCase):
    def test_add_get_expire_and_reindex(self):
        with tempfile.TemporaryDirectory() as tmp:
            now = [1000.0]
            store = Store(Path(tmp), keep_minutes=1, clock=lambda: now[0])
            photo = store.add(io.BytesIO(JPEG), len(JPEG), "image/jpeg")
            clip = store.add(io.BytesIO(MP4), len(MP4), "video/mp4")
            self.assertRegex(photo.code, r"^[A-Za-z0-9_-]{12}$")
            self.assertEqual(store.get(photo.code).path.read_bytes(), JPEG)
            self.assertEqual(clip.kind, "clip")
            self.assertIsNone(store.get("../../secret"))
            again = Store(Path(tmp), keep_minutes=1, clock=lambda: now[0])  # a restarted service
            self.assertEqual(again.get(photo.code).mime, "image/jpeg")
            now[0] += 61
            self.assertIsNone(store.get(photo.code))
            self.assertEqual(store.sweep(), 1)
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_wrong_type_size_or_content_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(Path(tmp), keep_minutes=5)
            for data, mime in [(JPEG, "image/png"), (WEBM, "image/jpeg"), (b"", "video/webm")]:
                with self.assertRaises(ValueError):
                    store.add(io.BytesIO(data), len(data), mime)
            with self.assertRaises(ValueError):
                store.add(io.BytesIO(JPEG[:8]), len(JPEG), "image/jpeg")  # upload ended early
            self.assertEqual(list(Path(tmp).iterdir()), [])


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        folder = Path(self.tmp.name)
        video = WEBM + bytes(range(256)) * 40
        self.video = video
        project = write_project(
            folder,
            {"backgrounds": [{"asset": "a_moon", "name": "Moon"}], "keep_minutes": 5},
            {"a_moon": ("moon.webm", video)},
        )
        booth = config.from_project(project, folder)
        self.settings_file = folder / "calibration.json"
        self.service = greenscreen.BoothService(
            booth, Store(folder / "captures", 5), "127.0.0.1", free_port(), free_port(), self.settings_file
        )
        self.service.start()
        self.op_port = self.service.operator.server_address[1]
        self.pub_port = self.service.public.server_address[1]

    def tearDown(self):
        self.service.close()
        self.tmp.cleanup()

    def request(self, port, method, path, body=None, headers=None, token=True):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        headers = dict(headers or {})
        if token:
            headers["Authorization"] = "Bearer " + self.service.secret
        connection.request(method, path, body, headers)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response, data

    def test_booth_api_needs_the_token_and_the_right_host(self):
        response, _ = self.request(self.op_port, "GET", "/api/booth", token=False)
        self.assertEqual(response.status, 403)
        response, _ = self.request(self.op_port, "GET", "/api/booth", headers={"Host": "evil.example:80"})
        self.assertEqual(response.status, 403)
        response, data = self.request(self.op_port, "GET", "/api/booth")
        state = json.loads(data)
        self.assertEqual(
            state["backgrounds"][0], {"name": "Moon", "kind": "video", "fit": "cover", "url": "/media/bg/0"}
        )
        self.assertTrue(state["local_only"])

    def test_public_listener_serves_only_capture_pages(self):
        for path in ["/booth", "/api/booth", "/media/bg/0", "/qr/AAAAAAAAAAAA.svg", "/booth.js"]:
            response, _ = self.request(self.pub_port, "GET", path)
            self.assertEqual(response.status, 404, path)
        response, data = self.request(self.pub_port, "GET", "/p/AAAAAAAAAAAA", token=False)
        self.assertEqual(response.status, 404)
        self.assertIn(b"no longer here", data)

    def test_media_supports_byte_ranges(self):
        response, data = self.request(
            self.op_port, "GET", "/media/bg/0", headers={"Range": "bytes=10-19"}, token=False
        )
        self.assertEqual(response.status, 206)
        self.assertEqual(data, self.video[10:20])
        self.assertEqual(response.getheader("Content-Range"), f"bytes 10-19/{len(self.video)}")
        response, data = self.request(
            self.op_port, "GET", "/media/bg/0", headers={"Range": "bytes=-5"}, token=False
        )
        self.assertEqual(data, self.video[-5:])
        response, _ = self.request(
            self.op_port, "GET", "/media/bg/0", headers={"Range": "bytes=999999-"}, token=False
        )
        self.assertEqual(response.status, 416)
        response, _ = self.request(self.op_port, "GET", "/media/bg/7", token=False)
        self.assertEqual(response.status, 404)

    def test_capture_round_trip_to_a_phone(self):
        response, data = self.request(
            self.op_port, "POST", "/api/capture", JPEG, {"Content-Type": "image/jpeg"}
        )
        self.assertEqual(response.status, 200, data)
        capture = json.loads(data)
        self.assertEqual(capture["kind"], "photo")
        self.assertTrue(capture["url"].endswith("/p/" + capture["code"]))
        response, page = self.request(self.pub_port, "GET", f"/p/{capture['code']}", token=False)
        self.assertEqual(response.status, 200)
        self.assertIn(b"Save photo", page)
        response, photo = self.request(
            self.pub_port, "GET", f"/p/{capture['code']}/file?download=1", token=False
        )
        self.assertEqual(photo, JPEG)
        self.assertIn("attachment", response.getheader("Content-Disposition"))
        response, svg = self.request(self.op_port, "GET", f"/qr/{capture['code']}.svg", token=False)
        self.assertTrue(svg.startswith(b"<svg"))
        response, data = self.request(
            self.op_port, "POST", "/api/capture", b"GIF89a", {"Content-Type": "image/gif"}
        )
        self.assertEqual(response.status, 400)
        response, data = self.request(
            self.op_port, "POST", "/api/captures/clear", b"{}", {"Content-Type": "application/json"}
        )
        self.assertEqual(json.loads(data)["deleted"], 1)
        response, _ = self.request(self.pub_port, "GET", f"/p/{capture['code']}", token=False)
        self.assertEqual(response.status, 404)

    def test_settings_are_cleaned_saved_and_cross_origin_posts_refused(self):
        body = json.dumps({"settings": {"key": {"tolerance": 0.31, "color": "#00ff00"}, "keep_minutes": 9}})
        headers = {"Content-Type": "application/json", "Origin": "http://evil.example"}
        response, _ = self.request(self.op_port, "POST", "/api/settings", body, headers)
        self.assertEqual(response.status, 403)
        del headers["Origin"]
        response, data = self.request(self.op_port, "POST", "/api/settings", body, headers)
        settings = json.loads(data)["settings"]
        self.assertEqual(settings["key"]["tolerance"], 0.31)
        self.assertEqual(settings["key"]["softness"], config.DEFAULTS["key"]["softness"])
        self.assertEqual(self.service.store.keep, 9 * 60)
        self.assertEqual(json.loads(self.settings_file.read_text())["key"]["color"], "#00ff00")

    def test_stop_request(self):
        self.request(self.op_port, "POST", "/api/stop", b"{}", {"Content-Type": "application/json"})
        self.assertTrue(self.service.stop.wait(2))


if __name__ == "__main__":
    unittest.main()
