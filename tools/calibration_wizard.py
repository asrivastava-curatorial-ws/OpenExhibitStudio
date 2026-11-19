#!/usr/bin/env python3
"""Operator workflow for independent camera captures and four screen corners."""

import argparse
from pathlib import Path
import threading
import subprocess
import sys
import queue
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk
from calibrate import manifest, solve, write_json, sequence, dump_report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, nargs=2, default=(1280, 720))
    a = parser.parse_args()
    root = tk.Tk()
    root.title("OpenExhibit · Camera calibration")
    box = ttk.Frame(root, padding=14)
    box.pack(fill="both", expand=True)
    text = tk.StringVar(value="Capture the raw patterns, or open an existing capture directory.")
    status = ttk.Label(box, textvariable=text, wraplength=780)
    status.pack(fill="x")
    toolbar = ttk.Frame(box)
    toolbar.pack(fill="x", pady=8)
    variables = []
    for name, value in zip(["Output width", "Height", "Desktop X", "Y", "Camera index"], [*a.size, 0, 0, 0]):
        ttk.Label(toolbar, text=name).pack(side="left")
        v = tk.StringVar(value=str(value))
        variables.append(v)
        ttk.Entry(toolbar, width=6, textvariable=v).pack(side="left", padx=3)
    canvas = tk.Canvas(box, width=760, height=410, background="#151b23")
    canvas.pack()
    state = {"folder": None, "scale": 1, "corners": [], "image": None, "xy": (0, 0), "active": False}
    done = queue.Queue()

    def load(path):
        seq = manifest(path / "patterns.json")
        im = Image.open(path / "white.png").convert("RGB")
        w, h = im.size
        scale = min(760 / w, 410 / h)
        rw, rh = max(1, round(w * scale)), max(1, round(h * scale))
        xy = ((760 - rw) / 2, (410 - rh) / 2)
        canvas.delete("all")
        image = ImageTk.PhotoImage(im.resize((rw, rh)))
        state.update(folder=path, scale=(rw / w, rh / h), image=image, corners=[], xy=xy, size=(w, h))
        canvas.create_image(*xy, image=image, anchor="nw")
        text.set(
            f"{seq['size'][0]} × {seq['size'][1]} output. Click the top-left, top-right, bottom-right and bottom-left corners of the physical screen."
        )

    def select():
        f = filedialog.askdirectory()
        if f:
            try:
                load(Path(f))
            except (OSError, ValueError) as e:
                messagebox.showerror("Open captures", str(e))

    def point(e):
        if not state["folder"] or state["active"] or len(state["corners"]) >= 4:
            return
        x, y = state["xy"]
        sx, sy = state["scale"]
        px = (e.x - x + 0.5) / sx - 0.5
        py = (e.y - y + 0.5) / sy - 0.5
        if not (0 <= px < state["size"][0] and 0 <= py < state["size"][1]):
            return
        state["corners"].append([px, py])
        canvas.create_oval(e.x - 4, e.y - 4, e.x + 4, e.y + 4, outline="#42e4af", width=2)
        if len(state["corners"]) == 4:
            text.set("Four corners selected. Solve and export the measured warp.")

    canvas.bind("<Button-1>", point)

    def work(callback):
        if state["active"]:
            return
        state["active"] = True
        text.set("Processing. Keep the camera and projector fixed.")

        def run():
            try:
                done.put((True, callback()))
            except Exception as err:
                done.put((False, str(err)))

        threading.Thread(target=run, daemon=True).start()

    def poll():
        try:
            ok, result = done.get_nowait()
        except queue.Empty:
            pass
        else:
            state["active"] = False
            if not ok:
                text.set("Calibration failed. " + result)
                messagebox.showerror("Calibration", result)
            elif isinstance(result, Path):
                load(result)
            else:
                text.set(result)
        root.after(100, poll)

    def acquire():
        if state["active"]:
            return
        try:
            w, h, x, y, camera = map(lambda v: int(v.get()), variables)
            sequence(w, h)  # raises ValueError for an unusable raster size
        except ValueError as exc:
            messagebox.showerror("Output settings", str(exc))
            return
        dest = filedialog.askdirectory(title="Choose an empty capture folder")
        if not dest:
            return

        def take():
            result = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).with_name("calibrate.py")),
                    "capture",
                    dest,
                    "--size",
                    str(w),
                    str(h),
                    "--camera",
                    str(camera),
                    "--origin",
                    str(x),
                    str(y),
                ],
                capture_output=True,
                text=True,
            )
            if result.returncode:
                raise ValueError(result.stderr.strip()[-300:] or "Capture did not complete.")
            return Path(dest)

        work(take)

    def export():
        if state["active"]:
            return
        if len(state["corners"]) != 4:
            messagebox.showerror("Corners", "Select all four screen corners.")
            return
        out = filedialog.asksaveasfilename(defaultextension=".json", initialfile="measured-warp.json")
        if not out:
            return
        folder = state["folder"]
        corners = list(state["corners"])

        def fit():
            report = solve(manifest(folder / "patterns.json"), folder, corners)
            write_json(out, report)
            return "Saved " + Path(out).name + ". " + dump_report(report)

        work(fit)

    actions = ttk.Frame(box)
    actions.pack(fill="x", pady=8)
    for label, fn in [
        ("Capture patterns", acquire),
        ("Open captures", select),
        ("Reset corners", lambda: load(state["folder"]) if state["folder"] and not state["active"] else None),
        ("Solve and export", export),
    ]:
        ttk.Button(actions, text=label, command=fn).pack(side="left", padx=4)
    poll()
    root.mainloop()


if __name__ == "__main__":
    main()
