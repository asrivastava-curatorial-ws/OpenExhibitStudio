#!/usr/bin/env python3
"""Verify a local exhibit update, atomically activate it, or roll back."""
import argparse
import hashlib
import json
import os
import shutil
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

def digest(path):
    with path.open("rb") as stream:
        h=hashlib.sha256()
        for part in iter(lambda:stream.read(1024*1024),b""):h.update(part)
        return h.hexdigest()

def verify(path):
    with zipfile.ZipFile(path) as z:
        names=z.namelist()
        if len(names)>2048 or len({n.casefold() for n in names})!=len(names) or set(["project.oes.json","manifest.json"])-set(names):
            raise ValueError("Invalid package members.")
        if sum(i.file_size for i in z.infolist())>512*1024**2 or any(i.file_size>256*1024**2 for i in z.infolist()):
            raise ValueError("Oversized package.")
        for n in names:
            if n not in ("project.oes.json","manifest.json") and (not n.startswith("assets/") or any(c in n for c in "\\:") or any(k in ("",".","..") for k in n.split("/"))):
                raise ValueError("Unexpected package path.")
        manifest=json.loads(z.read("manifest.json"))
        if set(manifest)!=set(names)-{"manifest.json"}:raise ValueError("Incomplete manifest.")
        for n,expected in manifest.items():
            if hashlib.sha256(z.read(n)).hexdigest()!=expected:raise ValueError("Checksum mismatch: "+n)
        project=json.loads(z.read("project.oes.json"))
        if project.get("format")!="openexhibit" or project.get("version")!=1:raise ValueError("Unsupported exhibit.")
        for a in project["assets"].values():
            if manifest.get(a["path"])!=a["sha256"]:raise ValueError("Manifest disagrees with project.")
        return project["title"]

def deploy(root,action,package=None):
    root.mkdir(parents=True,exist_ok=True)
    meta=root/"current.json"
    lock=root/".update.lock"
    with lock.open("a+b") as guard:
        if os.name=="nt":
            import msvcrt
            guard.seek(0);guard.write(b"0");guard.flush();guard.seek(0);msvcrt.locking(guard.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
        state=json.loads(meta.read_text()) if meta.exists() else {}
        if action=="status":return state
        if action=="rollback":
            previous=state.get("previous","")
            if not previous or Path(previous).name!=previous:raise ValueError("No previous update available.")
            verify(root/previous)
            state["active"],state["previous"]=previous,state["active"]
        elif action=="install":
            if package is None:raise ValueError("Supply the package to install.")
            fd,name=tempfile.mkstemp(dir=root,suffix=".incoming");os.close(fd)
            tmp=Path(name)
            try:
                shutil.copyfile(package,tmp)
                title=verify(tmp)
                local=digest(tmp)+".oex"
                if state.get("active")==local:return state
                os.replace(tmp,root/local)
                state={"active":local,"previous":state.get("active",""),"title":title}
            finally:tmp.unlink(missing_ok=True)
        fd,tmp=tempfile.mkstemp(dir=root)
        try:
            with os.fdopen(fd,"w",encoding="utf8") as f:
                json.dump(state,f,indent=2);f.flush();os.fsync(f.fileno())
            os.replace(tmp,meta)
        finally:Path(tmp).unlink(missing_ok=True)
        return state

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("action",choices=["install","rollback","status","verify"]);p.add_argument("path",type=Path);p.add_argument("package",type=Path,nargs="?")
    a=p.parse_args()
    result=verify(a.path) if a.action=="verify" else deploy(a.path,a.action,a.package)
    print(json.dumps(result,indent=2,ensure_ascii=False))
