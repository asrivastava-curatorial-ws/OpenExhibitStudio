"""The block editor's sketch generator: validation, and generated C++ that actually compiles."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT/"firmware/blockly/generate.js"
ARDUINO_STUB = """
#include <cstdio>
#define F(s) s
#define INPUT 0
#define OUTPUT 1
#define INPUT_PULLUP 2
#define LOW 0
#define HIGH 1
#define A0 14
#define A1 15
struct SerialPort { void begin(long) {} void print(const char*) {} void println(long) {} } Serial;
void pinMode(int, int) {}
int digitalRead(int) { return HIGH; }
void digitalWrite(int, int) {}
int analogRead(int) { return 512; }
unsigned long millis() { static unsigned long t = 0; return t += 150; }
void delayMicroseconds(unsigned int) {}
unsigned long pulseIn(int, int, unsigned long) { return 580; }
"""


def generate(blocks, **options):
    script = "const m=require(process.argv[1]);process.stdout.write(m.generateExhibitSketch(JSON.parse(process.argv[2]),JSON.parse(process.argv[3])))"
    result = subprocess.run(["node", "-e", script, str(GENERATOR), json.dumps(blocks), json.dumps(options)], capture_output=True, text=True)
    if result.returncode:
        errors = [line for line in result.stderr.splitlines() if line.startswith("Error:")]
        raise ValueError(errors[0] if errors else "generator failed")
    return result.stdout


@unittest.skipUnless(shutil.which("node"), "Node.js is needed to run the browser generator")
class FirmwareBlockTests(unittest.TestCase):
    ALL = [
        {"type": "oes_analog", "pin": "A0", "channel": "dial"},
        {"type": "oes_button", "pin": "2", "channel": "button"},
        {"type": "oes_switch", "pin": "4", "channel": "presence"},
        {"type": "oes_distance", "pin": "7", "pin2": "8", "channel": "distance"},
    ]

    def test_rejects_reused_pins_channels_and_foreign_pins(self):
        with self.assertRaisesRegex(ValueError, "used twice"):
            generate([self.ALL[1], dict(self.ALL[2], pin="2")])
        with self.assertRaisesRegex(ValueError, "used twice"):
            generate([self.ALL[0], dict(self.ALL[1], channel="dial")])
        with self.assertRaisesRegex(ValueError, "not available"):
            generate([dict(self.ALL[0], pin="A9")], board="uno")
        self.assertIn("analogRead(A9)", generate([dict(self.ALL[0], pin="A9")], board="mega"))

    @unittest.skipUnless(shutil.which("g++"), "a C++ compiler is needed")
    def test_generated_sketch_compiles_and_prints_the_ascii_protocol(self):
        sketch = generate(self.ALL, board="uno", interval=100)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/"sketch.cpp"
            source.write_text(ARDUINO_STUB + sketch + "\nint main(){setup();for(int i=0;i<3;i++)loop();return 0;}\n")
            subprocess.run(["g++", "-std=c++17", "-Wall", "-Werror", "-o", str(Path(tmp)/"sketch"), str(source)], check=True)
        for channel in ("dial", "button", "presence", "distance"):
            self.assertIn('Serial.print(F("%s "))' % channel, sketch)


if __name__ == "__main__":
    unittest.main()
