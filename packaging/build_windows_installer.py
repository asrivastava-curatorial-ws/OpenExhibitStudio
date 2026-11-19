#!/usr/bin/env python3
"""Build a native per-user Windows installer with NSIS 3 on Windows or Linux."""
import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path,PureWindowsPath
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from release import files


def build(out,compiler):
    if not (ROOT/'bin/windows/python/python.exe').is_file() or not (ROOT/'bin/windows/godot.exe').is_file():raise ValueError("Provision the Windows runtime first.")
    out=out.resolve();out.parent.mkdir(parents=True,exist_ok=True)
    name="OpenExhibit Studio"
    content=['Unicode true','RequestExecutionLevel user','ManifestDPIAware true','SetCompressor zlib',
             'Name "OpenExhibit Studio 0.3.0"',f'OutFile "{out}"',f'InstallDir "$LOCALAPPDATA\\Programs\\{name}"',
             'Page license','Page directory','Page instfiles','UninstPage uninstConfirm','UninstPage instfiles',
             f'LicenseData "{ROOT/"LICENSE"}"','ShowInstDetails show','Section "OpenExhibit Studio and Player"']
    entries=list(files("windows"));dirs=set()
    for src,relative in entries:
        rel=PureWindowsPath(relative);parent='' if str(rel.parent)=='.' else '\\'+str(rel.parent)
        dirs.add(parent)
        content+=['SetOutPath "$INSTDIR'+parent+'"',f'File "/oname={rel.name}" "{src}"']
    content += [f'CreateDirectory "$SMPROGRAMS\\{name}"',
                f'CreateShortcut "$SMPROGRAMS\\{name}\\Studio.lnk" "$INSTDIR\\Studio.cmd"',
                f'CreateShortcut "$SMPROGRAMS\\{name}\\Player.lnk" "$INSTDIR\\Player.cmd"',
                'WriteUninstaller "$INSTDIR\\Uninstall.exe"','SetRegView 64',
                'WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenExhibitStudio" "DisplayName" "OpenExhibit Studio"',
                'WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenExhibitStudio" "DisplayVersion" "0.3.0"',
                '''WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenExhibitStudio" "UninstallString" '"$INSTDIR\\Uninstall.exe"' ''',
                'SectionEnd','Section "Uninstall"','SetRegView 64','DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OpenExhibitStudio"']
    content += [f'Delete "$INSTDIR\\{PureWindowsPath(rel)}"' for _,rel in entries]
    for d in list(dirs):
        d=PureWindowsPath(d)
        for ancestor in d.parents:
            if str(ancestor) not in ('.','\\'):dirs.add(str(ancestor))
    content += [f'RMDir "$INSTDIR{d}"' for d in sorted(dirs,key=len,reverse=True) if d]
    content += ['Delete "$INSTDIR\\Uninstall.exe"','RMDir "$INSTDIR"',f'Delete "$SMPROGRAMS\\{name}\\Studio.lnk"',f'Delete "$SMPROGRAMS\\{name}\\Player.lnk"',f'RMDir "$SMPROGRAMS\\{name}"','SectionEnd']
    with tempfile.TemporaryDirectory() as tmp:
        script=Path(tmp)/'installer.nsi';script.write_text('\n'.join(content),encoding='utf-8-sig')
        subprocess.run([compiler,'/V2' if os.name=='nt' else '-V2',str(script)],check=True)
    print(out.name,out.stat().st_size,flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--makensis',default='makensis');p.add_argument('--out',type=Path,default=ROOT/'dist/OpenExhibit-Studio-0.3.0-Windows-x64-Setup.exe')
    a=p.parse_args();build(a.out,a.makensis)
