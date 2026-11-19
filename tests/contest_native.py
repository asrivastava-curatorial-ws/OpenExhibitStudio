"""Real private/public services driving the native Godot exhibit player."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import quiz
with tempfile.TemporaryDirectory() as td:
    room=quiz.Room(Path(td)/'room.sqlite',json.loads(quiz.EXAMPLE.read_text()))
    service=quiz.Contest(room,port=0,operator_port=0);service.start()
    try:
        t=room.join(room.meta()['code'],'Gallery visitor','Raman')
        prog=subprocess.Popen(['godot','--max-fps','40','--quit-after','1100','--audio-driver','Dummy','--path',str(ROOT/'app'),'--script','res://qa/check_contest.gd','--','--examples',str(ROOT/'examples'),'--quiz-url','http://%s:%d'%service.operator.server_address],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        passed=False
        with prog:
            for line in prog.stdout:
                print(line.rstrip(),flush=True)
                if line.startswith('PASS native'):passed=True
                if line.startswith('BOARD lobby'):room.control('next','lobby',-1)
                elif line.startswith('BOARD open'):room.submit(t,0,'Neptune');room.control('reveal','open',0)
                elif line.startswith('BOARD reveal'):room.control('standings','reveal',0)
        if prog.returncode or not passed:raise SystemExit(1)
    finally:service.close();room.db.close()
