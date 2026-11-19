#!/usr/bin/env python3
"""Explicit, local content preparation. Output files can be imported in Studio."""
import argparse
import json
import shutil
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise RuntimeError("Local media integrations require a direct loopback endpoint.")

def request(port,route,payload=None):
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    item=urllib.request.Request("http://127.0.0.1:%d%s"%(port,route),data=json.dumps(payload).encode() if payload is not None else None,headers={"Content-Type":"application/json"})
    with opener.open(item,timeout=180) as response:return response.read(64*1024**2)

def main():
    cli=argparse.ArgumentParser(description=__doc__)
    sub=cli.add_subparsers(dest="mode",required=True)
    o=sub.add_parser("ollama");o.add_argument("model");o.add_argument("prompt");o.add_argument("output",type=Path)
    c=sub.add_parser("comfy");c.add_argument("workflow",type=Path);c.add_argument("output",type=Path)
    t=sub.add_parser("speak");t.add_argument("model",type=Path);t.add_argument("text",type=Path);t.add_argument("output",type=Path)
    w=sub.add_parser("transcribe");w.add_argument("model",type=Path);w.add_argument("wav",type=Path);w.add_argument("output_prefix",type=Path)
    a=cli.parse_args()
    if a.mode=="ollama":
        result=json.loads(request(11434,"/api/generate",dict(model=a.model,prompt=a.prompt,stream=False)))
        a.output.write_text(result["response"],encoding="utf8")
    elif a.mode=="comfy":
        call=json.loads(request(8188,"/prompt",{"prompt":json.loads(a.workflow.read_text(encoding="utf8"))}))
        job=call["prompt_id"]
        for _ in range(600):
            entry=json.loads(request(8188,"/history/"+urllib.parse.quote(job,safe=""))).get(job)
            if entry:
                images=[image for node in entry.get("outputs",{}).values() for image in node.get("images",[])]
                if not images:raise RuntimeError("Workflow finished without an image output.")
                a.output.write_bytes(request(8188,"/view?"+urllib.parse.urlencode(images[0])))
                return
            time.sleep(1)
        raise TimeoutError("Local workflow exceeded ten minutes.")
    elif a.mode=="speak":
        tool=shutil.which("piper")
        if not tool:cli.error("Install Piper and a licensed voice model locally.")
        with a.text.open("rb") as f:subprocess.run([tool,"--model",str(a.model),"--output_file",str(a.output)],stdin=f,check=True)
    else:
        tool=shutil.which("whisper-cli")
        if not tool:cli.error("Install whisper.cpp and a compatible local model.")
        subprocess.run([tool,"-m",str(a.model),"-f",str(a.wav),"-otxt","-of",str(a.output_prefix)],check=True)
if __name__=="__main__":main()
