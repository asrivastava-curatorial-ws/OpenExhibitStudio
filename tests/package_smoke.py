import os,sys,subprocess,time,tempfile,zipfile,hashlib,json,shutil
from pathlib import Path
root=Path(sys.argv[1]).resolve()
def run(cmd,title):
 with tempfile.TemporaryFile('w+') as log:
  p=subprocess.Popen(cmd,cwd='/tmp',stdout=log,stderr=subprocess.STDOUT)
  try:
   end=time.monotonic()+18
   while time.monotonic()<end:
    if p.poll() is not None:raise RuntimeError('Process exited early')
    tree=subprocess.run(['xwininfo','-root','-tree'],capture_output=True,text=True).stdout
    if title in tree:
     print('PASS packaged entry point:',title,flush=True);break
    time.sleep(.25)
   else:raise RuntimeError('Window title missing: '+title)
   time.sleep(.65)
   log.seek(0);out=log.read()
   if 'SCRIPT ERROR:' in out or 'ERROR:' in out:raise RuntimeError(out)
  finally:
   p.terminate()
   try:p.wait(5)
   except subprocess.TimeoutExpired:p.kill();p.wait()
run(['bash',str(root/'studio.sh')],'Orbital atlas')
run(['bash',str(root/'player.sh'),str(root/'examples/13-shows/project.oes.json')],'Travelling waves')
with tempfile.TemporaryDirectory() as tmp:
 clean=Path(tmp);(clean/'bin').mkdir()
 for f in ['bin/godot','bin/player.pck','player.sh']:
  os.link(root/f,clean/f) if (root/f).stat().st_dev==clean.stat().st_dev else shutil.copy2(root/f,clean/f)
 src=root/'examples/06-digital-book';project=json.loads((src/'project.oes.json').read_text())
 files={'project.oes.json':(src/'project.oes.json').read_bytes(),**{a['path']:(src/a['path']).read_bytes() for a in project['assets'].values()}}
 with zipfile.ZipFile(clean/'book.oex','w',zipfile.ZIP_DEFLATED) as ar:
  for key,contents in files.items():ar.writestr(key,contents)
  ar.writestr('manifest.json',json.dumps({k:hashlib.sha256(v).hexdigest() for k,v in files.items()}))
 run(['bash',str(clean/'player.sh'),str(clean/'book.oex')],'A field guide to rocks')
 run(['bash',str(clean/'player.sh'),str(clean/'book.oex')],'A field guide to rocks')
 print('PASS player-only directory opened the exported book before and after process termination.')
