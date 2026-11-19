#!/usr/bin/env python3
"""Gray-code projector calibration with spatial holdouts and separate optical check frames."""

import argparse
import json
import math
import os
from pathlib import Path
import tempfile
import time

import numpy as np
from PIL import Image, ImageDraw


class CalibrationError(ValueError):
    pass


def cvlib():
    try:
        import cv2
    except ImportError as exc:
        raise CalibrationError("Install numpy, Pillow and opencv-python for calibration.") from exc
    return cv2


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, encoding="utf-8", delete=False) as f:
        tmp = Path(f.name)
        json.dump(data, f, indent=2, allow_nan=False)
        f.write("\n")
    try:
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def sequence(w, h):
    if any(type(v) is not int or not 32 <= v <= 8192 for v in (w, h)):
        raise CalibrationError("Projector dimensions must be 32–8192 native pixels.")
    frames = [{"file": "black.png", "kind": "black"}, {"file": "white.png", "kind": "white"}]
    for axis, size in [("x", w), ("y", h)]:
        for bit in reversed(range((size - 1).bit_length())):
            for inverse in [False, True]:
                frames.append(
                    dict(
                        file=f"{axis}{bit:02d}{'n' if inverse else 'p'}.png",
                        kind="bit",
                        axis=axis,
                        bit=bit,
                        inverse=inverse,
                    )
                )
    # Spatially distinct images are independently observed after all Gray frames.
    for j, y in enumerate(np.linspace(0.12, 0.88, 4)):
        for i, x in enumerate(np.linspace(0.12, 0.88, 5)):
            frames.append(
                dict(
                    file=f"verify-{5 * j + i:02d}.png",
                    kind="verify",
                    center=[round((w - 1) * x), round((h - 1) * y)],
                )
            )
    return dict(format="oes-graycode", version=1, size=[w, h], frames=frames)


def pattern(frame, w, h):
    kind = frame["kind"]
    if kind in {"black", "white"}:
        return Image.new("L", (w, h), 255 if kind == "white" else 0)
    if kind == "verify":
        im = Image.new("L", (w, h), 0)
        x, y = frame["center"]
        r = max(2, round(min(w, h) * 0.009))
        ImageDraw.Draw(im).ellipse((x - r, y - r, x + r, y + r), fill=255)
        return im
    ax = frame["axis"]
    k = np.arange(w if ax == "x" else h, dtype=np.uint16)
    bits = (((k ^ (k >> 1)) >> frame["bit"]) & 1) ^ int(frame["inverse"])
    a = np.tile(bits, (h, 1)) if ax == "x" else np.tile(bits[:, None], (1, w))
    return Image.fromarray((a * 255).astype(np.uint8))


def generate(directory, w, h):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    seq = sequence(w, h)
    for f in seq["frames"]:
        pattern(f, w, h).save(directory / f["file"])
    write_json(directory / "patterns.json", seq)
    return seq


def manifest(path):
    obj = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(obj, dict) or not isinstance(obj.get("size"), list) or len(obj["size"]) != 2:
        raise CalibrationError("Invalid calibration manifest.")
    expected = sequence(*obj["size"])
    if obj != expected:
        raise CalibrationError("Unexpected capture order or manifest version.")
    return obj


def frame_reader(root):
    shape = None

    def read(name):
        nonlocal shape
        with Image.open(root / name) as im:
            if im.width > 10000 or im.height > 10000 or im.width * im.height > 32_000_000:
                raise CalibrationError("Camera image exceeds the resolution limit.")
            a = np.asarray(im.convert("L"), dtype=np.int16)
        if shape is None:
            shape = a.shape
        if shape != a.shape:
            raise CalibrationError("Camera resolution changed during acquisition.")
        return a

    return read


def decode(seq, read, contrast, bit_contrast):
    black, white = read("black.png"), read("white.png")
    span = white - black
    valid = span >= contrast
    loc = []
    for axis, lim in zip(("x", "y"), seq["size"]):
        gray = np.zeros(black.shape, dtype=np.uint16)
        for bit in reversed(range((lim - 1).bit_length())):
            a, b = read(f"{axis}{bit:02d}p.png"), read(f"{axis}{bit:02d}n.png")
            valid &= np.abs(a - b) >= np.maximum(bit_contrast, span * 0.20)
            valid &= np.abs(a + b - white - black) <= np.maximum(22, span * 0.48)
            gray |= (a > b).astype(np.uint16) << bit
        val = gray.copy()
        shift = 1
        while shift < (lim - 1).bit_length():
            val ^= val >> shift
            shift *= 2
        valid &= val < lim
        loc.append(val)
    return black, span, valid, loc


def transform(points, matrix):
    p = np.atleast_2d(np.asarray(points, dtype=float))
    h = np.column_stack((p, np.ones(len(p)))) @ np.asarray(matrix).T
    if np.any(np.abs(h[:, 2]) < 1e-9):
        raise CalibrationError("Projection crosses the camera horizon.")
    return h[:, :2] / h[:, 2:3]


def errors(values):
    a = np.asarray(values, dtype=float)
    return dict(
        samples=int(len(a)),
        rms_px=float(np.sqrt(np.mean(a * a))),
        p95_px=float(np.quantile(a, 0.95)),
        max_px=float(a.max()),
    )


def camera_quad(corners, width, height):
    cv = cvlib()
    c = np.asarray(corners, dtype=np.float32)
    if (
        c.shape != (4, 2)
        or not np.isfinite(c).all()
        or np.any(c < 0)
        or np.any(c[:, 0] >= width)
        or np.any(c[:, 1] >= height)
    ):
        raise CalibrationError("Specify four camera pixel centres inside the captured frame.")
    if not cv.isContourConvex(c) or cv.contourArea(c, oriented=True) < width * height * 0.015:
        raise CalibrationError("Mark a substantial, convex screen region in TL, TR, BR, BL order.")
    return c


def verify_dots(seq, read, roi, black, span, fit, screen_uv):
    cv = cvlib()
    dist = []
    quadrants = set()
    observations = []
    for frame in seq["frames"]:
        if frame["kind"] != "verify":
            continue
        a = read(frame["file"])
        fg = ((a - black) > np.maximum(18, span * 0.50)) & roi & (span >= 20)
        n, _, stats, centers = cv.connectedComponentsWithStats(fg.astype(np.uint8), 8)
        ids = sorted(range(1, n), key=lambda i: stats[i, cv.CC_STAT_AREA], reverse=True)
        if not ids or stats[ids[0], cv.CC_STAT_AREA] < 4:
            continue
        if len(ids) > 1 and stats[ids[1], cv.CC_STAT_AREA] > 0.35 * stats[ids[0], cv.CC_STAT_AREA]:
            continue
        point = centers[ids[0]]
        actual = transform([point], fit)[0]
        pos = transform([point], screen_uv)[0]
        quadrants.add((int(pos[0] > 0.5), int(pos[1] > 0.5)))
        error = float(np.linalg.norm(actual - frame["center"]))
        observations.append(
            {
                "file": frame["file"],
                "camera_px": point.tolist(),
                "projector_px": frame["center"],
                "error_px": error,
            }
        )
        dist.append(error)
    if len(dist) < 6 or len(quadrants) < 4:
        raise CalibrationError(
            "Independent dot frames need at least six visible marks spanning all four screen quadrants."
        )
    return errors(dist), observations


def solve(seq, captures, corners, *, contrast=32, bit_contrast=12, tolerance=1.5, min_coverage=0.60):
    cv = cvlib()
    if (
        not 0 < tolerance <= 10
        or not 0.1 <= min_coverage <= 1
        or not 0 < contrast <= 255
        or not 0 < bit_contrast <= 255
    ):
        raise CalibrationError("Invalid acceptance limits.")
    read = frame_reader(Path(captures))
    black, span, valid, location = decode(seq, read, contrast, bit_contrast)
    h, w = black.shape
    c = camera_quad(corners, w, h)
    roi = np.zeros((h, w), np.uint8)
    cv.fillConvexPoly(roi, np.rint(c).astype(np.int32), 1)
    roi = roi.astype(bool)
    valid &= roi
    coverage = float(valid.sum() / max(1, roi.sum()))
    if coverage < min_coverage:
        raise CalibrationError(f"Only {coverage:.1%} of the marked screen decoded.")
    ys, xs = np.nonzero(valid)
    if len(xs) < 150:
        raise CalibrationError("Too few decoded camera pixels.")
    # Disjoint spatial tiles guard against a good fit limited to one corner.
    tiles = ((xs // max(4, w // 16)) + 3 * (ys // max(4, h // 14))) % 5
    training = np.flatnonzero(tiles != 0)
    holdout = np.flatnonzero(tiles == 0)
    if min(len(training), len(holdout)) < 32:
        raise CalibrationError("Insufficient independent spatial support.")
    rng = np.random.default_rng(427)

    def sample(ids, limit):
        ids = rng.choice(ids, min(len(ids), limit), replace=False)
        return np.column_stack((xs[ids], ys[ids])).astype(float), np.column_stack(
            [a[ys[ids], xs[ids]] for a in location]
        ).astype(float)

    a, b = sample(training, 12000)
    fit, inliers = cv.findHomography(a, b, cv.RANSAC, tolerance, maxIters=4000, confidence=0.999)
    if fit is None or not np.isfinite(fit).all() or inliers.mean() < 0.75:
        raise CalibrationError("A stable planar fit could not be established.")
    uv = cv.getPerspectiveTransform(c, np.float32([[0, 0], [1, 0], [1, 1], [0, 1]]))
    screen_positions = transform(a, uv)
    for y in range(3):
        for x in range(3):
            region = (
                (screen_positions[:, 0] >= x / 3)
                & (screen_positions[:, 0] <= (x + 1) / 3)
                & (screen_positions[:, 1] >= y / 3)
                & (screen_positions[:, 1] <= (y + 1) / 3)
            )
            if region.sum() < 8:
                raise CalibrationError("Decoded correspondences leave a screen region unsupported.")
    for corner in [[0, 0], [1, 0], [1, 1], [0, 1]]:
        if np.min(np.linalg.norm(screen_positions - corner, axis=1)) > 0.10:
            raise CalibrationError("A screen corner would need excessive extrapolation.")
    ha, hb = sample(holdout, 10000)
    spatial = errors(np.linalg.norm(transform(ha, fit) - hb, axis=1))
    optical, dots = verify_dots(seq, read, roi, black, span, fit, uv)
    if any(r["p95_px"] > tolerance or r["max_px"] > 3 * tolerance for r in (spatial, optical)):
        raise CalibrationError(
            f"Independent residuals exceed limits. Spatial p95 {spatial['p95_px']:.3f} px, optical p95 {optical['p95_px']:.3f} px."
        )
    size = np.array(seq["size"])
    # Camera / Gray code coordinates index pixel centres. Godot UV uses raster edges.
    warp = (transform(c, fit) + 0.5) / size
    if np.any(warp < 0) or np.any(warp > 1) or not cv.isContourConvex(warp.astype(np.float32)):
        raise CalibrationError("The marked screen does not fit inside the projector raster.")
    return dict(
        format="oes-measured-warp",
        version=1,
        geometry="plane",
        size=size.tolist(),
        warp=warp.tolist(),
        status="capture-validated",
        method="complementary-graycode-planar",
        camera_size=[w, h],
        camera_corners=c.tolist(),
        camera_to_projector=fit.tolist(),
        valid_fraction=coverage,
        inlier_fraction=float(inliers.mean()),
        limits=dict(p95_px=tolerance, max_px=3 * tolerance, min_coverage=min_coverage),
        spatial_holdout=spatial,
        independent_dots=optical,
        observations=dots,
    )


def capture(seq, directory, camera, x, y, delay, windowed=False):
    cv = cvlib()
    w, h = seq["size"]
    if delay < 0.10:
        raise CalibrationError("Settle time must be at least 0.1 seconds.")
    dest = Path(directory)
    dest.mkdir(parents=True, exist_ok=True)
    if any(dest.glob("*.png")):
        raise CalibrationError("Choose an empty capture directory.")
    cam = cv.VideoCapture(camera)
    if not cam.isOpened():
        raise CalibrationError("Cannot open the selected camera.")
    name = "OpenExhibit · unwarped native patterns"
    try:
        cv.namedWindow(name, cv.WINDOW_NORMAL)
        cv.moveWindow(name, x, y)
        cv.resizeWindow(name, w, h)
        if not windowed:
            cv.setWindowProperty(name, cv.WND_PROP_FULLSCREEN, cv.WINDOW_FULLSCREEN)
        for f in seq["frames"]:
            img = np.asarray(pattern(f, w, h))
            cv.imshow(name, img)
            cv.waitKey(60)
            if not windowed:
                _, _, rw, rh = cv.getWindowImageRect(name)
                if (rw, rh) != (w, h):
                    raise CalibrationError(
                        f"Projection raster is {rw}×{rh}, expected {w}×{h}. Check scaling and display position."
                    )
            until = time.monotonic() + delay
            frame = None
            while time.monotonic() < until or frame is None:
                ok, frame = cam.read()
                if not ok:
                    raise CalibrationError("Camera disconnected during acquisition.")
                if cv.waitKey(1) == 27:
                    raise CalibrationError("Capture cancelled.")
            if not cv.imwrite(str(dest / f["file"]), frame):
                raise CalibrationError("Could not save camera frame.")
        write_json(dest / "patterns.json", seq)
    finally:
        cam.release()
        cv.destroyAllWindows()


def pose(data, tolerance):
    """Estimate metric camera-to-projector pose from known 3D survey targets."""
    cv = cvlib()
    obj = np.asarray(data["points_m"], float)
    img = np.asarray(data["pixels"], float)
    test_obj = np.asarray(data["check_points_m"], float)
    test_img = np.asarray(data["check_pixels"], float)
    K = np.asarray(data["intrinsics"], float)
    dist = np.asarray(data.get("distortion", [0] * 5), float)
    if (
        K.shape != (3, 3)
        or K[0, 0] <= 0
        or K[1, 1] <= 0
        or not np.isfinite(K).all()
        or not np.allclose(K[2], [0, 0, 1])
        or dist.size not in (4, 5, 8, 12, 14)
    ):
        raise CalibrationError("Invalid projector intrinsics or distortion coefficients.")
    for a, b, minimum in [(obj, img, 8), (test_obj, test_img, 4)]:
        if (
            a.ndim != 2
            or a.shape[1] != 3
            or b.shape != (len(a), 2)
            or len(a) < minimum
            or not np.isfinite(a).all()
            or not np.isfinite(b).all()
            or np.linalg.matrix_rank(a - a.mean(0)) < 3
        ):
            raise CalibrationError("Use surveyed, non-coplanar 3D points and matched projector pixels.")
    if np.min(np.linalg.norm(obj[:, None] - test_obj, axis=2)) < 1e-8:
        raise CalibrationError("Pose check targets must be independent.")
    ok, r, t, mask = cv.solvePnPRansac(
        obj, img, K, dist, reprojectionError=tolerance, iterationsCount=200, confidence=0.999
    )
    if not ok or mask is None or len(mask) < max(6, len(obj) * 0.75):
        raise CalibrationError("Pose solve rejected.")
    selected = mask.reshape(-1)
    r, t = cv.solvePnPRefineLM(obj[selected], img[selected], K, dist, r, t)
    rot = cv.Rodrigues(r)[0]
    if np.any((np.vstack([obj, test_obj]) @ rot.T + t.ravel())[:, 2] <= 0):
        raise CalibrationError("Survey points lie behind the projector.")
    projected = cv.projectPoints(test_obj, r, t, K, dist)[0].reshape(-1, 2)
    quality = errors(np.linalg.norm(projected - test_img, axis=1))
    if quality["p95_px"] > tolerance or quality["max_px"] > 3 * tolerance:
        raise CalibrationError("Independent pose targets exceed the residual limit.")
    eye = (-rot.T @ t).ravel()
    out = {
        "format": "oes-survey-pose",
        "version": 1,
        "position": eye.tolist(),
        "aim": (eye + rot[2]).tolist(),
        "up": (-rot[1]).tolist(),
        "world_to_projector_rotation": rot.tolist(),
        "translation_m": t.ravel().tolist(),
        "holdout": quality,
    }
    if "size" in data:
        size = data["size"]
        if (
            not isinstance(size, list)
            or len(size) != 2
            or any(type(x) is not int or not 32 <= x <= 8192 for x in size)
        ):
            raise CalibrationError("Invalid projector size.")
        if abs(K[0, 0] / K[1, 1] - 1) > 0.005 or abs(K[0, 1]) > 0.01 or np.max(np.abs(dist)) > 1e-5:
            raise CalibrationError(
                "Studio pose import requires square pixels, zero skew and lens-distortion correction upstream."
            )
        out.update(
            size=size,
            throw=float(K[0, 0] / size[0]),
            shift=[float(0.5 - (K[i, 2] + 0.5) / size[i]) for i in (0, 1)],
        )
    return out


def photometry(data, tolerance=0.035):
    """Fit the measured display transfer curve and test withheld drive levels."""
    if not 0 < tolerance <= 0.2:
        raise CalibrationError("Invalid luminance residual limit.")

    def series(key, n):
        a = np.asarray(data.get(key), float)
        if (
            a.ndim != 2
            or a.shape[1] != 2
            or len(a) < n
            or not np.isfinite(a).all()
            or np.any(a[:, 0] < 0)
            or np.any(a[:, 0] > 1)
            or len(set(a[:, 0])) != len(a)
            or np.any(a[:, 1] < 0)
        ):
            raise CalibrationError("Use distinct drive levels with measured nonnegative luminance.")
        return a[a[:, 0].argsort()]

    train = series("fit", 5)
    test = series("check", 3)
    if (
        train[0, 0] != 0
        or train[-1, 0] != 1
        or np.any(np.diff(train[:, 1]) <= 0)
        or set(test[:, 0]) & set(train[:, 0])
        or test[:, 0].min() > 0.32
        or test[:, 0].max() < 0.68
    ):
        raise CalibrationError(
            "Include dark and white reference levels with separate low, mid and high check levels."
        )
    dark, white = train[0, 1], train[-1, 1]
    span = white - dark
    x = np.log(train[1:-1, 0])
    y = np.log((train[1:-1, 1] - dark) / span)
    gamma = float(x @ y / (x @ x))
    if not 0.2 <= gamma <= 5:
        raise CalibrationError("Measured response is outside the supported gamma range.")
    residual = np.abs(dark + span * test[:, 0] ** gamma - test[:, 1]) / span
    if residual.max() > tolerance:
        raise CalibrationError("Independent luminance levels exceed the configured tolerance.")
    target = float(data.get("target_white", white))
    if not math.isfinite(target) or not dark < target <= white:
        raise CalibrationError("The target white must lie inside the measured optical range.")
    # Shader applies gain in linear content before the inverse-gamma transfer.
    gain = (target - dark) / span
    return dict(
        format="oes-photometry",
        version=1,
        gamma=gamma,
        gain=[gain] * 3,
        black=0,
        measured_black=dark,
        measured_white=white,
        target_white=target,
        check_samples=len(test),
        max_fractional_error=float(residual.max()),
        limit=tolerance,
    )


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="cmd", required=True)
    for name in ["patterns", "capture"]:
        p = commands.add_parser(name)
        p.add_argument("out", type=Path)
        p.add_argument("--size", type=int, nargs=2, required=True, metavar=("WIDTH", "HEIGHT"))
        if name == "capture":
            p.add_argument("--camera", type=int, default=0)
            p.add_argument("--origin", type=int, nargs=2, default=(0, 0))
            p.add_argument("--settle", type=float, default=0.55)
    p = commands.add_parser("solve")
    p.add_argument("captures", type=Path)
    p.add_argument(
        "--corners", type=Path, required=True, help="JSON array of TL,TR,BR,BL camera pixel centres."
    )
    p.add_argument("--contrast", type=int, default=32)
    p.add_argument("--bit-contrast", type=int, default=12)
    p.add_argument("--min-coverage", type=float, default=0.6)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--tolerance", type=float, default=1.5)
    p = commands.add_parser("pose")
    p.add_argument("survey", type=Path)
    p.add_argument("--out", required=True, type=Path)
    p.add_argument("--tolerance", type=float, default=1.5)
    p = commands.add_parser("photometry")
    p.add_argument("readings", type=Path)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--tolerance", type=float, default=0.035)
    args = cli.parse_args()
    try:
        if args.cmd == "patterns":
            generate(args.out, *args.size)
        elif args.cmd == "capture":
            capture(sequence(*args.size), args.out, args.camera, *args.origin, args.settle)
        elif args.cmd == "solve":
            report = solve(
                manifest(args.captures / "patterns.json"),
                args.captures,
                json.loads(args.corners.read_text()),
                contrast=args.contrast,
                bit_contrast=args.bit_contrast,
                tolerance=args.tolerance,
                min_coverage=args.min_coverage,
            )
            write_json(args.out, report)
            print(dump_report(report))
        elif args.cmd == "photometry":
            write_json(args.out, photometry(json.loads(args.readings.read_text()), args.tolerance))
        elif args.cmd == "pose":
            if not 0 < args.tolerance <= 10:
                raise CalibrationError("Invalid tolerance.")
            write_json(args.out, pose(json.loads(args.survey.read_text()), args.tolerance))
    except (ValueError, OSError, KeyError, IndexError) as exc:
        cli.exit(2, f"Calibration failed: {exc}\n")


def dump_report(report):
    return f"Coverage {report['valid_fraction']:.1%}; spatial p95 {report['spatial_holdout']['p95_px']:.3f} px; independent dots p95 {report['independent_dots']['p95_px']:.3f} px."


if __name__ == "__main__":
    main()
