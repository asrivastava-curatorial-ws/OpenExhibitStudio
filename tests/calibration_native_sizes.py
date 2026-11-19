"""Native-size optical fixture, generated independently of the production pattern writer."""
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import calibrate


def synthetic_capture(folder, projector, camera):
    width, height = projector
    cw, ch = camera
    surface = np.float32([[0, 0], [width-1, 0], [width-1, height-1], [0, height-1]])
    image = np.float32([[.10*cw,.09*ch], [.91*cw,.14*ch], [.88*cw,.91*ch], [.06*cw,.84*ch]])
    transform = cv2.getPerspectiveTransform(surface, image)
    reference = np.float32([[.06*width,.06*height], [.94*width,.07*height],
                            [.93*width,.93*height], [.07*width,.92*height]])
    corners = cv2.perspectiveTransform(reference[None], transform)[0]
    rng = np.random.default_rng(7405)
    yy = np.arange(ch, dtype=np.float32)[:,None] / ch
    xx = np.arange(cw, dtype=np.float32)[None,:] / cw
    gain = .66 + .10*xx + .05*yy
    dark = 16 + 4*xx + 3*yy

    def record(name, pattern):
        optical = cv2.warpPerspective(pattern, transform, camera, flags=cv2.INTER_LINEAR)
        noise = rng.integers(-3, 4, size=(ch,cw), dtype=np.int8)
        observed = np.clip(dark + gain * optical + noise, 0, 255).astype(np.uint8)
        if not cv2.imwrite(str(folder / (name + ".png")), observed, [cv2.IMWRITE_PNG_COMPRESSION, 1]):
            raise OSError(name)

    empty = np.zeros((height,width), np.uint8)
    record("black", empty)
    record("white", np.full_like(empty, 255))
    for axis, dimension in [("x", width), ("y", height)]:
        pixels = np.arange(dimension, dtype=np.int32)
        for bit in range((dimension - 1).bit_length()):
            # Reflected Gray bit b has flat runs of 2^(b+1), offset by half a run.
            stripe = (255 * (((pixels + 2**bit) // (2**(bit+1))) % 2)).astype(np.uint8)
            pattern = np.broadcast_to(stripe if axis == "x" else stripe[:,None], empty.shape)
            record(f"{axis}{bit:02}p", pattern)
            record(f"{axis}{bit:02}n", 255-pattern)

    radius = max(2, round(.009*min(width,height)))
    for row, v in enumerate([.12, .12+.76/3, .12+2*.76/3, .88]):
        for col, u in enumerate([.12, .31, .50, .69, .88]):
            dot = empty.copy()
            cv2.circle(dot, (round((width-1)*u), round((height-1)*v)), radius, 255, -1)
            record(f"verify-{row*5+col:02}", dot)
    return corners, reference


def run(projector, camera):
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        corners, reference = synthetic_capture(folder, projector, camera)
        report = calibrate.solve(calibrate.sequence(*projector), folder, corners)
        estimated = np.asarray(report["warp"]) * projector - .5
        maximum = float(np.linalg.norm(estimated-reference, axis=1).max())
        dots = report["independent_dots"]
        if dots["samples"] != 20 or dots["p95_px"] > .75 or maximum > .5:
            raise RuntimeError(f"Native-size optics check failed: marks={dots} corner_max={maximum}")
        print(f"PASS synthetic {projector[0]}x{projector[1]} projector, {camera[0]}x{camera[1]} camera, "
              f"corner_max={maximum:.4f}px spatial_p95={report['spatial_holdout']['p95_px']:.4f}px "
              f"independent_p95={dots['p95_px']:.4f}px twenty independent marks", flush=True)


if __name__ == "__main__":
    cv2.setNumThreads(2)
    run((1920,1080), (1920,1200))
    run((3840,2160), (1920,1080))
