#!/usr/bin/env python3
"""Provision the pinned offline Windows payload from official archives or a local cache.

The Godot digest is the official SHA-512 for 4.7.1. The embedded-Python digest was carried over
from 0.2.0 and has not been re-verified for 0.3.0; Setup-Windows.ps1 uses an installed Python instead.
"""
import argparse
import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
GODOT="Godot_v4.7.1-stable_win64.exe.zip"
PYTHON="python-3.14.10-embed-amd64.zip"
DATA=[(GODOT,"https://github.com/godotengine/godot/releases/download/4.7.1-stable/","sha512","a6b02c527c18ba9936e63562032701432b2dc57d98d6483ceaccb00fe14af16af5773ae8a55e7b4d614edf121c4d9e420d870f804edb1dac16362298a01ce6c4"),(PYTHON,"https://www.python.org/ftp/python/3.14.10/","sha256","90905e64a840557d8c1bc4f5b74db3d7ee85e3ffb217611cac1c7813acea4159")]


def provision(cache,out,offline):
    cache.mkdir(exist_ok=True,parents=True);out.mkdir(exist_ok=True,parents=True)
    for name,base,algorithm,expected in DATA:
        file=cache/name
        if not file.is_file():
            if offline:raise ValueError("Missing "+name)
            with tempfile.NamedTemporaryFile(dir=cache,delete=False) as f:
                tmp=Path(f.name)
                try:
                    with urllib.request.urlopen(base+name,timeout=80) as stream:shutil.copyfileobj(stream,f)
                except BaseException:
                    tmp.unlink(missing_ok=True);raise
            if hashlib.new(algorithm,tmp.read_bytes()).hexdigest()!=expected:tmp.unlink();raise ValueError("Bad downloaded digest for "+name)
            tmp.replace(file)
        if hashlib.new(algorithm,file.read_bytes()).hexdigest()!=expected:raise ValueError("Bad cached digest for "+name)
        with zipfile.ZipFile(file) as archive:
            if name==GODOT:
                with archive.open(GODOT[:-4]) as src,(out/"godot.exe").open("wb") as dst:shutil.copyfileobj(src,dst)
            else:
                dst=out/"python";dst.mkdir(exist_ok=True)
                for n in archive.namelist():
                    if Path(n).name!=n:raise ValueError("Unexpected embedded Python layout.")
                    with archive.open(n) as src,(dst/n).open("wb") as stream:shutil.copyfileobj(src,stream)

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--cache',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'bin/windows');p.add_argument('--offline',action='store_true')
    a=p.parse_args();provision(a.cache,a.out,a.offline)
