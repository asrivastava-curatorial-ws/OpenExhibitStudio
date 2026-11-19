import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from deploy import deploy, verify


def package(path, title, extra=None):
    project = json.loads((ROOT / "tools/data/layouts.json").read_text())["project"]
    project["title"] = title
    files = {"project.oes.json": json.dumps(project).encode(), **(extra or {})}
    with zipfile.ZipFile(path, "w") as z:
        for n, data in files.items():
            z.writestr(n, data)
        z.writestr("manifest.json", json.dumps({n: hashlib.sha256(b).hexdigest() for n, b in files.items()}))


class DeploymentTests(unittest.TestCase):
    def test_update_rollback_and_idempotency(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            a = root / "a.oex"
            b = root / "b.oex"
            dest = root / "deployment"
            package(a, "one")
            package(b, "two")
            first = deploy(dest, "install", a)
            second = deploy(dest, "install", b)
            self.assertEqual(deploy(dest, "install", b), second)
            state = deploy(dest, "rollback")
            self.assertEqual(state["active"], first["active"])
            self.assertEqual(verify(dest / state["active"]), "one")

    def test_corrupt_update_leaves_active_release(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)
            a = path / "a.oex"
            b = path / "bad.oex"
            dest = path / "deployment"
            package(a, "one")
            initial = deploy(dest, "install", a)
            b.write_bytes(b"power interrupted")
            with self.assertRaises(zipfile.BadZipFile):
                deploy(dest, "install", b)
            self.assertEqual(deploy(dest, "status"), initial)

    def test_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "bad.oex"
            package(a, "one", {"assets/../../etc": b"x"})
            with self.assertRaises(ValueError):
                verify(a)

    def test_reference_schema(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest("Install jsonschema for schema validation.")
        schema = json.loads((ROOT / "docs/project.schema.json").read_text())
        for project in (ROOT / "examples").glob("*/project.oes.json"):
            jsonschema.validate(json.loads(project.read_text()), schema)
