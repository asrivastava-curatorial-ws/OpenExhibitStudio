#!/usr/bin/env python3
"""Optional art rebuild with Pillow and FFmpeg. Pass a WGS84 Natural Earth polygons GeoJSON to rebuild the Earth layer."""
import argparse
import json
import math
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]/"examples"


def earth(path):
    width,height=1440,720
    img=Image.new("RGB",(width,height),"#102d43")
    draw=ImageDraw.Draw(img)
    def ring(coords):
        return [((pt[0]+180)/360*width,(90-pt[1])/180*height) for pt in coords]
    for feature in json.loads(Path(path).read_text())["features"]:
        geom=feature["geometry"]
        polygons=geom["coordinates"] if geom["type"]=="MultiPolygon" else [geom["coordinates"]]
        for poly in polygons:
            draw.polygon(ring(poly[0]),fill="#84c6ab")
            for hole in poly[1:]:
                draw.polygon(ring(hole),fill="#102d43")
    for lon in range(-180,181,30):
        x=(lon+180)*width/360
        for y in range(0,height,9):
            draw.line((x,y,x,y+2),fill="#578287",width=1)
    for lat in range(-60,61,30):
        y=(90-lat)*height/180
        for x in range(0,width,9):
            draw.line((x,y,x+2,y),fill="#578287",width=1)
    dest=ROOT/"03-earth/assets/earth.png"
    dest.parent.mkdir(parents=True,exist_ok=True)
    img.save(dest,optimize=True)


def movie(standing):
    dest=ROOT/"13-shows/assets"/("standing.ogv" if standing else "travelling.ogv")
    dest.parent.mkdir(parents=True,exist_ok=True)
    proc=subprocess.Popen(["ffmpeg","-v","error","-y","-f","rawvideo","-pix_fmt","rgb24","-s","640x360","-r","24","-i","-","-an","-c:v","libtheora","-q:v","7","-pix_fmt","yuv420p",str(dest)],stdin=subprocess.PIPE)
    for i in range(144):
        img=Image.new("RGB",(640,360),"#102739")
        d=ImageDraw.Draw(img)
        for x in range(0,641,40):d.line((x,0,x,360),fill="#1b3648")
        for y in range(20,360,40):d.line((0,y,640,y),fill="#1b3648")
        d.line((0,180,640,180),fill="#486374",width=2)
        theta=math.tau*i/72
        def y(x):
            phi=math.tau*x/320
            return 180+95*(math.sin(phi)*math.cos(theta) if standing else math.sin(phi-theta))
        d.line([(x,y(x)) for x in range(640)],fill="#79e6c9",width=4)
        for x in range(0,641,32):
            h=y(x);d.ellipse((x-4,h-4,x+4,h+4),fill="#f5cc87")
        proc.stdin.write(img.tobytes())
    proc.stdin.close()
    if proc.wait():raise RuntimeError("FFmpeg encoding failed.")
if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("--coastlines")
    cli.add_argument("--movies",action="store_true")
    args=cli.parse_args()
    if args.coastlines:earth(args.coastlines)
    if args.movies:
        movie(False);movie(True)
