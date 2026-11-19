"""Start a GUI command, wait for a window whose title contains TEXT, and fail on Godot errors.

    python3 tests/window_smoke.py "Orbital atlas" -- path/to/AppRun [args ...]

Needs an X11 display, for example inside tests/dual_display.sh.
"""

import subprocess
import sys
import tempfile
import time


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[2] != "--":
        print(__doc__, file=sys.stderr)
        return 2
    title, command = argv[1], argv[3:]
    with tempfile.TemporaryFile("w+") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 40
            while True:
                if process.poll() is not None:
                    log.seek(0)
                    print(log.read(), file=sys.stderr)
                    print(f"FAIL {title}: exited early with status {process.returncode}", file=sys.stderr)
                    return 1
                tree = subprocess.run(["xwininfo", "-root", "-tree"], capture_output=True, text=True).stdout
                if title in tree:
                    break
                if time.monotonic() > deadline:
                    print(f"FAIL no window titled {title!r} within 40 s", file=sys.stderr)
                    return 1
                time.sleep(0.3)
            time.sleep(2)  # let the first frames render and any script errors surface
            log.seek(0)
            output = log.read()
            errors = [
                line for line in output.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR:")
            ]
            if errors:
                print(output, file=sys.stderr)
                print(f"FAIL {title}: {len(errors)} engine error line(s)", file=sys.stderr)
                return 1
            print(f"PASS window {title!r} from {' '.join(command[:2])}")
            return 0
        finally:
            process.terminate()
            try:
                process.wait(5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
