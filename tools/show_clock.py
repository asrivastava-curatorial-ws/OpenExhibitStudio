#!/usr/bin/env python3
"""Authenticated LAN timeline clock. Operators control it on the publishing machine."""
import argparse
import hashlib
import hmac
import os
import re
import secrets
import socket
import threading
import time

def mac(key,body):
    return hmac.new(key.encode(),body.encode("ascii"),hashlib.sha256).hexdigest()

class Clock:
    def __init__(self, track, duration, repeat):
        self.track,self.duration,self.repeat=track,duration,repeat
        self.epoch=secrets.token_hex(6)
        self.start=time.monotonic();self.offset=0.;self.running=True
        self.lock=threading.Lock()
    def position(self):
        t=self.offset+(time.monotonic()-self.start if self.running else 0)
        cycle=int(t/self.duration) if self.repeat else 0
        return (t%self.duration if self.repeat else min(t,self.duration)),cycle,(self.running and (self.repeat or t<self.duration))
    def command(self,cmd):
        with self.lock:
            if cmd=="pause" and self.running:
                self.offset+=time.monotonic()-self.start;self.running=False
            if cmd=="resume" and not self.running:
                self.start=time.monotonic();self.running=True
            if cmd=="restart":
                self.epoch=secrets.token_hex(6);self.start=time.monotonic();self.running=True;self.offset=0
    def reply(self,payload,key):
        if len(payload)>160:return None
        try:msg,sig=payload.decode("ascii").rsplit("|",1)
        except (UnicodeError,ValueError):return None
        if not hmac.compare_digest(mac(key,msg),sig):return None
        if not re.fullmatch(r"OEC1\|P\|[a-f0-9]{24}",msg):return None
        with self.lock:
            at,cycle,playing=self.position()
            text="OEC1|S|%s|%s|%s|%d|%d|%d"%(msg.split("|")[2],self.epoch,self.track,round(at*1000),cycle,int(playing))
            return (text+"|"+mac(key,text)).encode("ascii")

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--timeline",required=True);p.add_argument("--duration",type=float,required=True)
    p.add_argument("--bind",default="127.0.0.1");p.add_argument("--port",type=int,default=18442)
    p.add_argument("--repeat",action="store_true");p.add_argument("--console",action="store_true")
    a=p.parse_args();key=os.getenv("OES_CLOCK_KEY","")
    if len(key)<32:p.error("Set OES_CLOCK_KEY to a shared random key of at least 32 characters.")
    if not re.fullmatch("[a-zA-Z0-9_-]{1,96}",a.timeline) or not 0<a.duration<=86400:p.error("Invalid timeline or duration.")
    clock=Clock(a.timeline,a.duration,a.repeat)
    if a.console:
        def console():
            try:
                while True:clock.command(input("pause / resume / restart > ").strip().lower())
            except EOFError:return
        threading.Thread(target=console,daemon=True).start()
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        sock.bind((a.bind,a.port))
        print("Clock listening at",sock.getsockname(),flush=True)
        while True:
            data,addr=sock.recvfrom(256)
            reply=clock.reply(data,key)
            if reply:sock.sendto(reply,addr)
