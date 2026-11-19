import concurrent.futures
import csv
import io
import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import quiz
from contest import deck
from contest.room import Room, Conflict, Forbidden


class Clock:
    def __init__(self):self.now=1000
    def __call__(self):return self.now


class ContestTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup)
        self.path=Path(self.t.name)/'room.sqlite'
        self.deck=json.loads(quiz.EXAMPLE.read_text())
        self.clock=Clock();self.room=self.open()
        self.a=self.join('Nila');self.b=self.join('নীল')
    def open(self):
        room=Room(self.path,self.deck,clock=self.clock,wall=self.clock);self.addCleanup(room.db.close);return room
    def join(self,name):return self.room.join(self.room.meta()['code'],name,'Raman')
    def act(self,act):
        s=self.room.snapshot();self.room.control(act,s['phase'],s['index'])

    def test_deck_marking_all_quiz_and_audience_types(self):
        q=deck.validate(self.deck)['questions']
        for v in q:
            if v['type'] in deck.GRADED:
                ans=v['answer'][0] if v['type']=='text' else v['answer']
                self.assertTrue(deck.correct(v,deck.response(v,ans)))
            self.assertNotIn('answer',deck.public_question(v))
        self.assertTrue(deck.correct(q[3],'  SUBLIMATION  '));self.assertTrue(deck.correct(q[4],3.009))
        self.assertFalse(deck.correct(q[4],3.02))
        with self.assertRaises(deck.Invalid):deck.response(q[1],['Copper','Copper'])
        with self.assertRaises(deck.Invalid):deck.response(q[5],['Current','Current','Current'])
        with self.assertRaises(deck.Invalid):deck.question(dict(type='number',prompt='n',answer=float('nan')))
    def test_no_early_results_and_pause_with_authoritative_elapsed(self):
        self.act('next');self.clock.now+=4;self.room.submit(self.a,0,'Neptune')
        self.act('pause');self.clock.now+=100
        with self.assertRaises(Conflict):self.room.submit(self.b,0,'Earth')
        self.act('resume');self.clock.now+=4;self.room.submit(self.b,0,'Earth')
        for s in [self.room.snapshot(),self.room.snapshot(self.a)]:
            self.assertFalse({'leaders','answer','distribution','deck'}&s.keys())
            if 'me' in s:self.assertIsNone(s['me']['points'])
        self.act('reveal');s=self.room.snapshot(self.a)
        self.assertEqual(s['me']['points'],933);self.assertEqual(s['team_leaders'][0]['score'],933)
    def test_deadline_stale_action_and_cross_round_submission(self):
        self.act('next');self.clock.now+=30
        with self.assertRaises(Conflict):self.room.submit(self.a,0,'Neptune')
        self.assertEqual('closed',self.room.snapshot()['phase']);self.act('reveal');self.act('next')
        with self.assertRaises(Conflict):self.room.submit(self.a,0,'Neptune')
        with self.assertRaises(Conflict):self.room.control('reveal','open',0)
    def test_concurrent_duplicate_posts_score_once(self):
        self.act('next')
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
            list(ex.map(lambda _:self.room.submit(self.a,0,'Neptune'),range(40)))
        with self.assertRaises(Conflict):self.room.submit(self.a,0,'Mars')
        self.act('reveal');s=self.room.snapshot(self.a)
        self.assertEqual(s['received'],1);self.assertEqual(s['me']['points'],1000)
    def test_ties_have_shared_rank_and_csv_accounts_for_absences(self):
        other=self.join('=formula')
        self.act('next');self.room.submit(self.a,0,'Neptune');self.room.submit(self.b,0,'Neptune')
        self.act('reveal');self.assertEqual([r['rank'] for r in self.room.snapshot()['leaders']],[1,1,3])
        rows=list(csv.DictReader(io.StringIO(self.room.export())));self.assertEqual(len(rows),3)
        self.assertTrue(any(r['player']=="'=formula" and r['answer']=='' for r in rows))
    def test_restart_restores_roster_answers_and_pauses_clock(self):
        self.act('next');self.clock.now+=2;self.room.submit(self.a,0,'Neptune');self.clock.now+=4
        room=self.open();s=room.snapshot(self.a);self.assertEqual(s['phase'],'paused')
        self.assertTrue(s['me']['submitted']);self.assertEqual(s['seconds_left'],24)
        self.clock.now+=60;self.assertEqual(room.snapshot()['seconds_left'],24)
    def test_lobby_lock_and_team_changes(self):
        self.act('lock')
        with self.assertRaises(Conflict):self.join('Other')
        self.act('lock')
        with self.assertRaises(Conflict):self.join('NILA')
        with self.assertRaises(Forbidden):self.room.join('111','Else','Raman')
        with self.assertRaises(Conflict):self.room.control('deck','lobby',-1,{**self.deck,'teams':[]})
    def test_qa_moderation_and_single_vote(self):
        self.room.qa(self.a,'ask','Can light bend?')
        self.assertEqual(self.room.snapshot()['qa'],[])
        q=self.room.snapshot(host=True)['qa'][0]['id']
        self.room.moderate(q,'published');self.room.qa(self.b,'vote',q);self.room.qa(self.b,'vote',q)
        self.assertEqual(self.room.snapshot()['qa'][0]['votes'],1)
        self.room.moderate(q,'hidden');self.assertEqual(self.room.snapshot()['qa'],[])
    def test_local_listeners_concurrent_audience(self):
        room=self.room;srv=quiz.Contest(room,port=0,operator_port=0);srv.start();self.addCleanup(srv.close)
        base='http://%s:%d'%srv.public.server_address
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def req(path,data=None,token=None):
            hdr={'Content-Type':'application/json'}
            if token:hdr['Authorization']='Bearer '+token
            obj=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=hdr)
            try:
                with opener.open(obj,timeout=12) as r:return json.load(r)
            except urllib.error.HTTPError as exc:
                if exc.code!=403:raise RuntimeError(str(exc.code)+' '+exc.read().decode()) from exc
                raise
        with self.assertRaises(urllib.error.HTTPError) as e:req('/api/host/state',token=srv.secret)
        self.assertEqual(e.exception.code,403)
        code=room.meta()['code']
        with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
            tokens=list(pool.map(lambda i:req('/api/join',dict(name='P'+str(i),code=code,team='Raman'))['token'],range(64)))
            self.act('next')
            list(pool.map(lambda t:req('/api/answer',dict(round=0,value='Neptune'),t),tokens))
        self.assertEqual(req('/api/state')['received'],64)
        self.act('reveal');self.assertEqual(req('/api/state')['team_leaders'][0]['score'],64000)
        print('HTTP contest: 64 distinct clients joined and submitted; 64 counted; 64000 team points.')

class PracticeTests(unittest.TestCase):
    def test_independent_progress_timeout_and_shared_final(self):
        clock=Clock();d=json.loads(quiz.EXAMPLE.read_text());d['questions']=d['questions'][:2]
        room=Room(':memory:',d,clock=clock,wall=clock,self_paced=True);self.addCleanup(room.db.close)
        a,b=[room.join(room.meta()['code'],name,'Raman') for name in ['A','B']]
        room.control('next','lobby',-1);room.practice_next(a,-1)
        self.assertEqual(room.snapshot(b)['phase'],'lobby')
        room.submit(a,0,'Neptune');self.assertEqual(room.snapshot(a)['phase'],'reveal')
        self.assertNotIn('leaders',room.snapshot(b));room.practice_next(a,0)
        room.practice_next(b,-1);clock.now+=30
        self.assertEqual(room.snapshot(a)['phase'],'reveal')
        with self.assertRaises(Conflict):room.submit(b,0,'Neptune')
        room.practice_next(a,1);self.assertEqual(room.snapshot(a)['phase'],'finished')
        self.assertEqual(room.snapshot(a)['total_score'],1000)
        room.control('finish','practice',-1)
        self.assertEqual(room.snapshot(b)['leaders'][0]['name'],'A')

class PollTests(unittest.TestCase):
    def test_poll_stream_updates_and_graded_keys_remain_private(self):
        d=json.loads(quiz.EXAMPLE.read_text());d['questions']=[d['questions'][7],d['questions'][0]]
        r=Room(':memory:',d);self.addCleanup(r.db.close);a=r.join(r.meta()['code'],'A','Raman');b=r.join(r.meta()['code'],'B','Raman')
        r.control('next','lobby',-1);r.submit(a,0,'Projection globe')
        self.assertEqual(r.snapshot()['distribution'],[('Projection globe',1)])
        self.assertNotIn('distribution',r.snapshot(b))
        r.control('reveal','open',0);r.control('next','reveal',0)
        r.submit(a,1,'Neptune');self.assertNotIn('distribution',r.snapshot())
