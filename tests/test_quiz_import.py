import io
import sys
import zipfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from contest.slides import convert


class SlideTests(unittest.TestCase):
    def test_pptx_presentation_order_survives_import(self):
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w') as z:
            z.writestr(
                'ppt/presentation.xml',
                '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId r:id="b"/><p:sldId r:id="a"/></p:sldIdLst></p:presentation>',
            )
            z.writestr(
                'ppt/_rels/presentation.xml.rels',
                '<Relationships><Relationship Id="a" Target="slides/slide1.xml"/><Relationship Id="b" Target="slides/slide2.xml"/></Relationships>',
            )
            for i in (1, 2):
                z.writestr(
                    f'ppt/slides/slide{i}.xml',
                    f'<root xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:t>Round {i}</a:t></root>',
                )
        deck = convert(out.getvalue(), 'my event.pptx')
        self.assertEqual([q['prompt'] for q in deck['questions']], ['Round 2', 'Round 1'])
        self.assertEqual(deck['questions'][0]['type'], 'slide')

    def test_pdf_decodes_two_real_local_pages(self):
        import shutil

        if not shutil.which('pdftoppm'):
            self.skipTest('Poppler required.')
        try:
            from reportlab.pdfgen import canvas
        except ImportError:
            self.skipTest('ReportLab PDF test input required.')
        out = io.BytesIO()
        doc = canvas.Canvas(out)
        doc.drawString(20, 100, 'Lens')
        doc.showPage()
        doc.drawString(20, 100, 'Prism')
        doc.save()
        deck = convert(out.getvalue(), 'Optics.pdf')
        self.assertEqual(len(deck['questions']), 2)
        self.assertTrue(all(q['image'].startswith('data:image/jpeg;base64,') for q in deck['questions']))
