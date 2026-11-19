import hashlib
import json
import secrets
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from page_marks import CODES, decode, rotations
from show_clock import Clock, mac


class ToolTests(unittest.TestCase):
    def test_page_codes_and_rotations(self):
        for page, code in enumerate(CODES, 1):
            for rotated in rotations(code):
                cells = [[0] * 6 for _ in range(6)]
                for i, v in enumerate(rotated):
                    cells[1 + i // 4][1 + i % 4] = int(v)
                self.assertEqual(decode(cells), page)
                cells[1][1] ^= 1
                self.assertEqual(decode(cells), page)
        self.assertIsNone(decode([[0] * 6 for _ in range(6)]))

    def test_clock_auth_and_nonce(self):
        c = Clock("sequence", 12, True)
        key = secrets.token_hex(20)
        msg = "OEC1|P|" + secrets.token_hex(12)
        req = msg + "|" + mac(key, msg)
        self.assertIsNone(c.reply(req.encode(), "wrong"))
        reply = c.reply(req.encode(), key).decode()
        body, sig = reply.rsplit("|", 1)
        self.assertEqual(sig, mac(key, body))
        self.assertIn(msg.split("|")[-1], body)
        self.assertIn("sequence", body)
        c.command("pause")
        self.assertFalse(c.position()[2])
        c.command("restart")
        self.assertTrue(c.position()[2])

    @unittest.skipUnless(shutil.which("node"), "Node required for firmware generator check")
    def test_block_generator(self):
        code = """const m=require(process.argv[1]);const block={type:'oes_analog',pin:'A0',channel:'dial'};const s=m.generateExhibitSketch([block]);if(!s.includes('analogRead(A0)'))process.exit(1);try{m.generateExhibitSketch([block,block]);process.exit(2)}catch(e){}"""
        subprocess.run(["node", "-e", code, str(ROOT / "firmware/blockly/generate.js")], check=True)

    @unittest.skipUnless(shutil.which("pdftoppm"), "Poppler required")
    def test_pdf_book_import(self):
        try:
            from reportlab.pdfgen import canvas
        except ImportError:
            self.skipTest("ReportLab required for PDF fixture.")
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            pdf = base / "fixture.pdf"
            book = base / "book"
            cv = canvas.Canvas(str(pdf))
            cv.drawString(20, 400, "First page")
            cv.showPage()
            cv.drawString(20, 400, "Second page")
            cv.save()
            subprocess.run(
                [sys.executable, str(ROOT / "tools/import_pdf.py"), str(pdf), str(book)], check=True
            )
            p = json.loads((book / "project.oes.json").read_text())
            self.assertEqual(len(p["scenes"]), 2)
            for a in p["assets"].values():
                self.assertEqual(hashlib.sha256((book / a["path"]).read_bytes()).hexdigest(), a["sha256"])
