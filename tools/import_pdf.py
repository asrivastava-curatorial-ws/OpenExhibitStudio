#!/usr/bin/env python3
"""Create a navigable, offline flipbook using the external Poppler pdftoppm utility."""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from make_examples import CAT, action, button, eq, rule, scene


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("pdf", type=Path)
    cli.add_argument("destination", type=Path)
    args = cli.parse_args()
    if args.destination.exists():
        cli.error("Choose a new destination directory.")
    if not shutil.which("pdftoppm"):
        cli.error("Install Poppler or place pdftoppm on PATH.")
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.destination.parent) as stage:
        root = Path(stage) / "book"
        art = root / "assets"
        art.mkdir(parents=True)
        subprocess.run(
            ["pdftoppm", "-png", "-scale-to", "1400", str(args.pdf.resolve()), str(art / "page")], check=True
        )
        images = sorted(art.glob("page-*.png"), key=lambda p: int(p.stem.split("-")[-1]))
        if not images:
            raise SystemExit("PDF has no rendered pages.")
        p = dict(CAT["project"])
        p.update(title=args.pdf.stem, scenes=[], start="p1", assets={}, rules=[], variables={"page": 1})
        for index, image in enumerate(images, 1):
            id = "p" + str(index)
            s = scene(id, "Page " + str(index), transition="slide")
            p["assets"][id] = {
                "path": "assets/" + image.name,
                "sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
            }
            s["objects"].append(dict(id="page_art", kind="image", rect=[0, 0, 1280, 630], asset=id))
            button(s, "prev", "Previous", 35, 647, 280, "book.prev")
            button(s, "next", "Next", 965, 647, 280, "book.next")
            for d in [-1, 1]:
                rule(
                    p,
                    "book." + ("next" if d > 0 else "prev"),
                    [action("goto", "p" + str(max(1, min(len(images), index + d))))],
                    eq(index, "$page"),
                )
            rule(p, "enter." + id, [action("set", "page", index)])
            rule(p, "input.page", [action("goto", id)], eq(index))
            p["scenes"].append(s)
        (root / "project.oes.json").write_text(json.dumps(p, indent=2, ensure_ascii=False), encoding="utf8")
        root.rename(args.destination)


if __name__ == "__main__":
    main()
