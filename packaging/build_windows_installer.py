#!/usr/bin/env python3
r"""Build OpenExhibit-Studio-<version>-Windows-x64-Setup.exe with NSIS 3, on Linux or Windows.

The installer holds the official Godot 4.7.1 Windows engine, Studio and Player packs exported with
4.7.1, CPython 3.12 (python-build-standalone) with the serial and MQTT libraries for the
live-audience and hardware services, and the examples, firmware and documentation. It installs per
user without administrator rights into %LOCALAPPDATA%\Programs\OpenExhibit Studio, adds Start-menu
entries, optional desktop shortcuts and an optional .oex file association, and registers an
uninstaller that removes only what it installed.

    python3 packaging/build_windows_installer.py [--out FILE] [--offline] [--stage DIR] [--makensis PATH]

Needs NSIS 3 (Ubuntu: sudo apt install nsis).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path, PurePosixPath

import runtimes

HERE = Path(__file__).resolve().parent
APP = "OpenExhibit Studio"
KEY = "OpenExhibitStudio"
UNINSTALL_KEY = rf"Software\Microsoft\Windows\CurrentVersion\Uninstall\{KEY}"
FILE_CLASS = "OpenExhibit.Package"


def stage_payload(stage: Path, cache: Path, offline: bool) -> None:
    """Lay out exactly what gets installed: bin/ (engine, packs, Python), examples, services, docs."""
    windows_zip = runtimes.fetch("godot-windows", cache, offline)
    runtimes.extract_member(windows_zip, "Godot_v4.7.1-stable_win64.exe", stage / "bin" / "godot.exe", 0o644)
    with tempfile.TemporaryDirectory(prefix="openexhibit-engine-") as tmp:
        # Packs are exported with the Linux build of the same engine version.
        linux_zip = runtimes.fetch("godot-linux", cache, offline)
        engine = runtimes.extract_member(linux_zip, "Godot_v4.7.1-stable_linux.x86_64", Path(tmp) / "godot")
        runtimes.build_packs(engine, "windows", stage / "bin")
    runtimes.install_windows_python(stage / "bin" / "python", cache, offline)
    runtimes.copy_payload(stage, extra_files=("Studio.cmd", "Player.cmd"))
    shutil.copy2(HERE / "openexhibit.ico", stage / "openexhibit.ico")


def win(relative: PurePosixPath | str) -> str:
    return str(relative).replace("/", "\\")


def quoted(text: str) -> str:
    if any(c in text for c in '"$`\n'):
        raise ValueError(f"Unsupported character in installer path: {text!r}")
    return f'"{text}"'


def launch(role: str, project: str = "") -> tuple[str, str]:
    """Target and parameters that start Studio or the Player without a console window."""
    parameters = rf'--main-pack "$INSTDIR\bin\{role}.pck" -- --examples "$INSTDIR\examples"'
    if project:
        parameters += f' --project "{project}"'
    return r"$INSTDIR\bin\godot.exe", parameters


def nsis_script(stage: Path, out: Path) -> str:
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    size_kb = sum(path.stat().st_size for path in files) // 1024
    python = stage / "bin" / "python"
    app_files = [path for path in files if python not in path.parents]
    folders = sorted({PurePosixPath(path.relative_to(stage)).parent for path in files}, key=str)
    # Every directory the installer creates, including ones that only hold other directories.
    created = {ancestor for folder in folders for ancestor in (folder, *folder.parents)} - {
        PurePosixPath(".")
    }
    script_folders = sorted(
        {PurePosixPath(p.relative_to(stage)).parent for p in app_files if p.suffix == ".py"}, key=str
    )
    studio, studio_args = launch("studio")
    player, player_args = launch("player")

    lines = [
        "Unicode true",
        "ManifestDPIAware true",
        "RequestExecutionLevel user",
        "SetCompressor /SOLID lzma",
        "SetCompressorDictSize 64",
        '!include "MUI2.nsh"',
        f'Name "{APP} {runtimes.VERSION}"',
        f"OutFile {quoted(str(out))}",
        rf'InstallDir "$LOCALAPPDATA\Programs\{APP}"',
        rf'InstallDirRegKey HKCU "Software\{KEY}" "InstallDir"',
        f'BrandingText "{APP} {runtimes.VERSION}"',
        f'VIProductVersion "{runtimes.VERSION}.0"',
        f'VIAddVersionKey "ProductName" "{APP}"',
        f'VIAddVersionKey "ProductVersion" "{runtimes.VERSION}"',
        f'VIAddVersionKey "FileVersion" "{runtimes.VERSION}"',
        f'VIAddVersionKey "FileDescription" "{APP} setup"',
        'VIAddVersionKey "LegalCopyright" "MIT licence; bundled components keep their own licences"',
        f"!define MUI_ICON {quoted(str(HERE / 'openexhibit.ico'))}",
        f"!define MUI_UNICON {quoted(str(HERE / 'openexhibit.ico'))}",
        "!define MUI_ABORTWARNING",
        "!define MUI_COMPONENTSPAGE_SMALLDESC",
        "!define MUI_FINISHPAGE_RUN",
        '!define MUI_FINISHPAGE_RUN_TEXT "Start OpenExhibit Studio"',
        "!define MUI_FINISHPAGE_RUN_FUNCTION StartStudio",
        "!insertmacro MUI_PAGE_WELCOME",
        f"!insertmacro MUI_PAGE_LICENSE {quoted(str(runtimes.ROOT / 'LICENSE'))}",
        "!insertmacro MUI_PAGE_COMPONENTS",
        "!insertmacro MUI_PAGE_DIRECTORY",
        "!insertmacro MUI_PAGE_INSTFILES",
        "!insertmacro MUI_PAGE_FINISH",
        "!insertmacro MUI_UNPAGE_CONFIRM",
        "!insertmacro MUI_UNPAGE_INSTFILES",
        '!insertmacro MUI_LANGUAGE "English"',
        "",
        "Function StartStudio",
        'SetOutPath "$INSTDIR"',
        f"""Exec '"{studio}" {studio_args}'""",
        "FunctionEnd",
        "",
        'Section "!OpenExhibit Studio and Player" SecApp',
        "SectionIn RO",
    ]
    for folder in folders:
        lines.append(f'SetOutPath "$INSTDIR{"" if str(folder) == "." else chr(92) + win(folder)}"')
        for path in files:
            if PurePosixPath(path.relative_to(stage)).parent == folder:
                lines.append(f"File {quoted(str(path))}")
    menu = rf"$SMPROGRAMS\{APP}"
    lines += [
        'SetOutPath "$INSTDIR"',
        f'CreateDirectory "{menu}"',
        rf"""CreateShortcut "{menu}\OpenExhibit Studio.lnk" "{studio}" '{studio_args}' "$INSTDIR\openexhibit.ico" """,
        rf"""CreateShortcut "{menu}\OpenExhibit Player.lnk" "{player}" '{player_args}' "$INSTDIR\openexhibit.ico" """,
        rf'CreateShortcut "{menu}\Documentation.lnk" "$INSTDIR\docs"',
        rf'CreateShortcut "{menu}\Uninstall OpenExhibit Studio.lnk" "$INSTDIR\Uninstall.exe"',
        r'WriteUninstaller "$INSTDIR\Uninstall.exe"',
        rf'WriteRegStr HKCU "Software\{KEY}" "InstallDir" "$INSTDIR"',
        f'WriteRegStr HKCU "{UNINSTALL_KEY}" "DisplayName" "{APP}"',
        f'WriteRegStr HKCU "{UNINSTALL_KEY}" "DisplayVersion" "{runtimes.VERSION}"',
        f'WriteRegStr HKCU "{UNINSTALL_KEY}" "Publisher" "OpenExhibit Studio contributors"',
        rf'WriteRegStr HKCU "{UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\openexhibit.ico"',
        f'WriteRegStr HKCU "{UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"',
        rf"""WriteRegStr HKCU "{UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'""",
        rf"""WriteRegStr HKCU "{UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'""",
        f'WriteRegDWORD HKCU "{UNINSTALL_KEY}" "NoModify" 1',
        f'WriteRegDWORD HKCU "{UNINSTALL_KEY}" "NoRepair" 1',
        f'WriteRegDWORD HKCU "{UNINSTALL_KEY}" "EstimatedSize" {size_kb}',
        "SectionEnd",
        "",
        'Section "Desktop shortcuts" SecDesktop',
        'SetOutPath "$INSTDIR"',
        rf"""CreateShortcut "$DESKTOP\OpenExhibit Studio.lnk" "{studio}" '{studio_args}' "$INSTDIR\openexhibit.ico" """,
        rf"""CreateShortcut "$DESKTOP\OpenExhibit Player.lnk" "{player}" '{player_args}' "$INSTDIR\openexhibit.ico" """,
        "SectionEnd",
        "",
        'Section "Open .oex packages with the Player" SecAssociate',
    ]
    open_target, open_args = launch("player", "%1")
    edit_target, edit_args = launch("studio", "%1")
    classes = r"Software\Classes"
    lines += [
        f'WriteRegStr HKCU "{classes}\\.oex" "" "{FILE_CLASS}"',
        f'WriteRegStr HKCU "{classes}\\{FILE_CLASS}" "" "OpenExhibit exhibit package"',
        rf'WriteRegStr HKCU "{classes}\{FILE_CLASS}\DefaultIcon" "" "$INSTDIR\openexhibit.ico"',
        rf"""WriteRegStr HKCU "{classes}\{FILE_CLASS}\shell\open\command" "" '"{open_target}" {open_args}'""",
        rf'WriteRegStr HKCU "{classes}\{FILE_CLASS}\shell\edit" "" "Edit in OpenExhibit Studio"',
        rf"""WriteRegStr HKCU "{classes}\{FILE_CLASS}\shell\edit\command" "" '"{edit_target}" {edit_args}'""",
        "System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'",
        "SectionEnd",
        "",
        "!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN",
        '!insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "Studio, Player, examples, live-audience and hardware services, documentation."',
        '!insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "Studio and Player shortcuts on the desktop."',
        '!insertmacro MUI_DESCRIPTION_TEXT ${SecAssociate} "Double-click an .oex exhibit package to play it; right-click to edit it in Studio."',
        "!insertmacro MUI_FUNCTION_DESCRIPTION_END",
        "",
        'Section "Uninstall"',
        r'Delete "$DESKTOP\OpenExhibit Studio.lnk"',
        r'Delete "$DESKTOP\OpenExhibit Player.lnk"',
        f'RMDir /r "{menu}"',
        rf'ReadRegStr $0 HKCU "{classes}\.oex" ""',
        f'StrCmp $0 "{FILE_CLASS}" 0 +2',
        rf'DeleteRegKey HKCU "{classes}\.oex"',
        rf'DeleteRegKey HKCU "{classes}\{FILE_CLASS}"',
        "System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'",
        f'DeleteRegKey HKCU "{UNINSTALL_KEY}"',
        rf'DeleteRegKey HKCU "Software\{KEY}"',
    ]
    lines += [rf'Delete "$INSTDIR\{win(path.relative_to(stage))}"' for path in app_files]
    lines.append(r'RMDir /r "$INSTDIR\bin\python"')
    # Python writes byte-code caches next to the installed scripts; remove those caches too.
    lines += [
        rf'RMDir /r "$INSTDIR\{win(folder)}\__pycache__"' for folder in script_folders if str(folder) != "."
    ]
    for folder in sorted(created, key=lambda f: (-len(f.parts), str(f))):
        if python not in (stage / folder).parents and stage / folder != python:
            lines.append(rf'RMDir "$INSTDIR\{win(folder)}"')
    lines += [r'Delete "$INSTDIR\Uninstall.exe"', 'RMDir "$INSTDIR"', "SectionEnd", ""]
    return "\n".join(lines)


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default = runtimes.ROOT / "dist" / f"OpenExhibit-Studio-{runtimes.VERSION}-Windows-x64-Setup.exe"
    cli.add_argument("--out", type=Path, default=default)
    cli.add_argument("--makensis", default="makensis")
    cli.add_argument("--cache", type=Path, default=runtimes.CACHE)
    cli.add_argument("--offline", action="store_true")
    cli.add_argument("--stage", type=Path, help="keep the staged files here (must not exist)")
    options = cli.parse_args()
    if not shutil.which(options.makensis):
        cli.error("makensis not found: install NSIS 3 (Ubuntu: sudo apt install nsis)")
    out = options.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="openexhibit-windows-") as tmp:
        stage = options.stage.resolve() if options.stage else Path(tmp) / "stage"
        stage.mkdir(parents=True)
        stage_payload(stage, options.cache, options.offline)
        script = Path(tmp) / "installer.nsi"
        script.write_text(nsis_script(stage, out), encoding="utf-8-sig")
        subprocess.run([options.makensis, "-V2", str(script)], check=True)
    print(f"Built {out} ({out.stat().st_size / 1e6:.1f} MB)")
    print(f"  sha256 {runtimes.file_digest(out, 'sha256')}")


if __name__ == "__main__":
    main()
