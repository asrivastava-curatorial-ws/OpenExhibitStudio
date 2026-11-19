"""Real Chromium operator, projector and two isolated participant browser profiles."""
import argparse
import csv
import io
import json
import sys
import tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright, expect
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import quiz


def run(chromium,screenshot=None):
    with tempfile.TemporaryDirectory() as tmp, sync_playwright() as pw:
        room=quiz.Room(Path(tmp)/'room.sqlite',json.loads(quiz.EXAMPLE.read_text()))
        service=quiz.Contest(room,port=0,operator_port=0);service.start()
        browser=None
        try:
            browser=pw.chromium.launch(executable_path=chromium,args=['--no-sandbox','--no-proxy-server','--disable-dev-shm-usage'])
            contexts=[browser.new_context(viewport={'width':w,'height':h},accept_downloads=True) for w,h in [(1180,850),(1280,720),(390,844),(420,820)]]
            host,display,*players=[ctx.new_page() for ctx in contexts]
            failures=[]
            for pg in [host,display,*players]:pg.on('pageerror',lambda exc:failures.append(str(exc)))
            host.goto(service.host_url);display.goto(service.audience_url)
            expect(host.get_by_role('button',name='Edit contest')).to_be_visible()
            host.get_by_role('button',name='Edit contest').click()
            host.get_by_label('Contest title').fill('Museum quiz final')
            host.get_by_role('button',name='Save deck to room').click()
            expect(display.get_by_role('heading',name='Museum quiz final')).to_be_visible()
            for page,name,team in zip(players,['Arun','মীরা'],['Faraday','Raman']):
                page.goto(service.join_url);page.get_by_label('Display name').fill(name)
                page.get_by_label('Team',exact=True).select_option(team)
                page.get_by_role('button',name='Join contest').click()
                expect(page.get_by_role('heading',name='Waiting for the first round')).to_be_visible()
                assert page.evaluate("document.documentElement.scrollWidth<=innerWidth"),'Phone layout overflows'
            expect(display.get_by_text('2 joined · joining open')).to_be_visible()
            import cv2,numpy as np
            qr_image=display.get_by_alt_text('QR code to join this contest').screenshot()
            decoded=cv2.QRCodeDetector().detectAndDecode(cv2.imdecode(np.frombuffer(qr_image,np.uint8),cv2.IMREAD_GRAYSCALE))[0]
            assert decoded==service.join_url,(decoded,service.join_url)
            host.get_by_role('button',name='Start contest').click()
            for page,answer in zip(players,['Neptune','Earth']):
                page.get_by_role('radio',name=answer).check();page.get_by_role('button',name='Submit answer').click()
                expect(page.get_by_text('Answer recorded')).to_be_visible()
            players[0].reload();expect(players[0].get_by_text('Answer recorded')).to_be_visible()
            players[0].get_by_label('Ask the host').fill('How long is a Neptunian year?')
            players[0].get_by_role('button',name='Send question').click()
            expect(display.get_by_text('How long is a Neptunian year?')).to_have_count(0)
            host.get_by_role('button',name='Publish',exact=True).click()
            expect(display.get_by_text('How long is a Neptunian year?')).to_be_visible()
            players[1].get_by_role('button',name='Upvote').click()
            expect(host.get_by_text('published · 1 votes')).to_be_visible()
            host.get_by_role('button',name='Pause',exact=True).click();expect(display.get_by_text('The host paused the clock.')).to_be_visible()
            host.get_by_role('button',name='Resume',exact=True).click()
            host.get_by_role('button',name='Reveal answer').click()
            expect(display.get_by_text('Neptune takes about 165 Earth years to complete one orbit.')).to_be_visible()
            host.get_by_role('button',name='Show standings').click();expect(display.get_by_role('heading',name='Leaderboard')).to_be_visible()
            if screenshot:display.screenshot(path=screenshot)
            host.get_by_role('button',name='Next round').click()
            players[0].get_by_role('checkbox',name='Copper').check();players[0].get_by_role('checkbox',name='Aluminium').check()
            players[0].get_by_role('button',name='Submit answer').click()
            expect(players[0].get_by_text('Answer recorded')).to_be_visible()
            host.get_by_role('button',name='Reveal answer').click()
            host.on('dialog',lambda d:d.accept());host.get_by_role('button',name='Finish contest').click()
            expect(players[0].get_by_role('heading',name='Final standings')).to_be_visible()
            with host.expect_download() as d:host.get_by_role('button',name='Export results').click()
            rows=list(csv.DictReader(io.StringIO(Path(d.value.path()).read_text(encoding='utf-8-sig'))))
            assert len(rows)==4 and len([r for r in rows if int(r['points'])>0])==2,rows
            assert failures==[],failures
            print('PASS actual Chromium: edited deck, QR join link, host/projector plus two mobile viewports, Unicode, responses, reconnection, moderation, upvote, pause/resume, reveal, rankings, multiple answers and CSV; zero JS exceptions.')
        finally:
            if browser:browser.close()
            service.close();room.db.close()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--chromium',default='chromium');p.add_argument('--screenshot');a=p.parse_args()
    import shutil
    run(shutil.which(a.chromium) or a.chromium,a.screenshot)
