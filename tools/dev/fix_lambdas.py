"""Re-attach multi-line lambdas to their call line after gdformat.

gdformat moves a lambda argument onto its own line, which Godot cannot parse because a
lambda body must dedent back to the line the lambda starts on:

    before (gdformat output)          after (valid GDScript)
    x.connect(                        x.connect(func() -> void:
        func() -> void:                   body()
            body()                    )
    )

Usage: python3 tools/dev/fix_lambdas.py app/studio/main.gd [more.gd ...]
Prints how many lambdas were re-attached and any own-line lambda it could not fix.
"""

import re
import sys

HEADER = re.compile(r"^\t+.*func\([^()]*\)(\s*->\s*[\w\[\]]+)?\s*:\s*$")


def indent(line: str) -> int:
    return len(line) - len(line.lstrip("\t"))


def fix_one(lines: list[str]) -> bool:
    """Re-attach the first fixable lambda in place. Returns False when none is left."""
    for i, line in enumerate(lines):
        if not HEADER.match(line):
            continue
        level = indent(line)
        opener = i - 1
        while opener >= 0 and (not lines[opener].strip() or indent(lines[opener]) == level):
            opener -= 1
        if opener < 0 or indent(lines[opener]) != level - 1 or not lines[opener].rstrip().endswith("("):
            continue
        leading_args = [text.strip() for text in lines[opener + 1 : i]]
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or indent(lines[end]) > level):
            end += 1
        body = lines[i + 1 : end]
        while body and not body[-1].strip():
            body.pop()
        trailing_comma = bool(body) and body[-1].rstrip().endswith(",")
        if trailing_comma:
            body[-1] = body[-1].rstrip()[:-1]
        rest = []
        close = end
        while close < len(lines) and indent(lines[close]) == level and lines[close].strip():
            rest.append(lines[close].strip())
            close += 1
        if (
            close >= len(lines)
            or indent(lines[close]) != level - 1
            or not lines[close].strip().startswith(")")
        ):
            continue
        head = lines[opener].rstrip() + " ".join(leading_args) + (" " if leading_args else "") + line.strip()
        new_body = ["\t" * (indent(text) - 1) + text.lstrip("\t") if text.strip() else text for text in body]
        tail = ("," if trailing_comma else "") + " ".join(rest) + " " + lines[close].strip()
        tail = re.sub(r"\s+\)", ")", tail)
        tail = re.sub(r",\s*", ", ", tail).rstrip()
        lines[opener : close + 1] = [head, *new_body, "\t" * (level - 1) + tail]
        return True
    return False


def leftovers(lines: list[str]) -> list[int]:
    """Line numbers of lambdas that still start on their own line after an open bracket."""
    found = []
    for i, line in enumerate(lines):
        if HEADER.match(line) and i and lines[i - 1].rstrip().endswith(("(", ",")):
            found.append(i + 1)
    return found


def main(paths: list[str]) -> int:
    status = 0
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        count = 0
        while fix_one(lines):
            count += 1
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines))
        print(f"{path}: {count} lambda(s) re-attached")
        for number in leftovers(lines):
            print(f"{path}:{number}: lambda still on its own line; fix by hand")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
