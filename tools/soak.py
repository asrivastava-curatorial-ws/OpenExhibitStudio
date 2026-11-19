#!/usr/bin/env python3
"""Monitor a real player process and detect sustained resource growth after warmup."""
import argparse
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--seconds",type=int,default=28800)
    cli.add_argument("--report",type=Path,required=True)
    cli.add_argument("--godot",default="godot")
    cli.add_argument("--display",action="store_true")
    a=cli.parse_args()
    cmd=[a.godot,"--max-fps","30","--path",str(ROOT/"app"),"--script","res://qa/soak.gd"]
    if not a.display:cmd+=["--headless"]
    cmd+=["--","--examples",str(ROOT/"examples"),"--seconds",str(a.seconds)]
    with tempfile.TemporaryFile(mode="w+") as log:
        proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
        start=time.monotonic();samples=[]
        while proc.poll() is None:
            point={"elapsed":round(time.monotonic()-start,2)}
            try:
                if os.name=="posix" and Path("/proc").is_dir():
                    info=(Path("/proc")/str(proc.pid)/"status").read_text()
                    ln=next(l for l in info.splitlines() if l.startswith("VmRSS:"))
                    point["rss_kib"]=int(ln.split()[1]);point["descriptors"]=len(list((Path("/proc")/str(proc.pid)/"fd").iterdir()))
                else:
                    import psutil
                    child=psutil.Process(proc.pid);point["rss_kib"]=child.memory_info().rss//1024
                    point["descriptors"]=child.num_handles() if os.name=="nt" else child.num_fds()
            except (StopIteration,FileNotFoundError,ProcessLookupError):
                pass
            samples.append(point)
            if point["elapsed"]>a.seconds+60:proc.kill();proc.wait();break
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:pass
        log.seek(0);output=log.read()
    stable=[s for s in samples if s["elapsed"]>=min(60,a.seconds/3) and "rss_kib" in s]
    if len(stable)<2:raise SystemExit("Insufficient post-warmup readings.")
    resource_delta={k:stable[-1][k]-stable[0][k] for k in ["rss_kib","descriptors"]}
    counters=[json.loads(l[7:]) for l in output.splitlines() if l.startswith("SAMPLE ")]
    passed=proc.returncode==0 and "SOAK_FINISHED" in output and "ERROR:" not in output and resource_delta["rss_kib"]<32768 and resource_delta["descriptors"]<8
    result={"passed":passed,"elapsed_seconds":round(time.monotonic()-start,2),"mode":"display" if a.display else "headless","sampling_seconds":5,"after_warmup_delta":resource_delta,"host_samples":samples,"engine_counters":counters}
    a.report.parent.mkdir(parents=True,exist_ok=True)
    a.report.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({k:v for k,v in result.items() if k not in ("host_samples","engine_counters")}))
    raise SystemExit(0 if passed else 1)
