#!/usr/bin/env python3
"""Optional, local-only camera input, book marker printing and planar calibration."""
import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path
from page_marks import markers as page_markers


def send(stream, msg):
    stream.write((json.dumps(msg,separators=(",",":"))+"\n").encode())
    stream.flush()


def coordinates(matrix, x, y, cv, np):
    if matrix is None:
        return x, y
    point = np.array([[[x, y]]], dtype=np.float32)
    return tuple(float(v) for v in cv.perspectiveTransform(point, matrix)[0, 0])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode", choices=["markers","book","motion","presence","face","calibrate"])
    p.add_argument("--family",choices=["openexhibit","aruco"],default="openexhibit")
    p.add_argument("--camera", type=int, default=0)
    p.add_argument("--out", type=Path, default=Path("markers"))
    p.add_argument("--pairs", type=Path, help="JSON with camera and content arrays of normalized 2D points.")
    p.add_argument("--homography", type=Path, help="Saved camera-to-content matrix.")
    p.add_argument("--port", type=int, default=18440)
    p.add_argument("--zone",type=float,nargs=4,default=[0,0,1,1],metavar=("X0","Y0","X1","Y1"))
    p.add_argument("--count",type=int,default=3)
    p.add_argument("--preview", action="store_true")
    args=p.parse_args()
    try:
        import cv2 as cv
        import numpy as np
    except ImportError:
        p.error("Install the optional opencv-contrib-python and numpy packages in a local Python environment.")
    if args.mode=="calibrate":
        if args.pairs is None: p.error("--pairs is required.")
        data=json.loads(args.pairs.read_text())
        a,b=[np.array(data[k],dtype=np.float64).reshape(-1,2) for k in ["camera","content"]]
        if len(a)<4 or a.shape!=b.shape:p.error("Supply four or more normalized point correspondences.")
        mat,mask=cv.findHomography(a,b,cv.RANSAC,0.01)
        if mat is None or int(mask.sum())<4:p.error("Correspondences are degenerate.")
        error=np.linalg.norm(cv.perspectiveTransform(a[None],mat)[0]-b,axis=1)
        args.out.write_text(json.dumps({"matrix":mat.tolist(),"inliers":int(mask.sum()),"max_normalized_error":float(error.max())},indent=2))
        return
    dictionary=cv.aruco.getPredefinedDictionary(cv.aruco.DICT_4X4_50) if args.mode=="markers" or (args.mode=="book" and args.family=="aruco") else None
    if args.mode=="markers":
        args.out.mkdir(parents=True,exist_ok=True)
        for i in range(1,min(49,max(1,args.count))+1):
            bits=cv.aruco.generateImageMarker(dictionary,i,480)
            canvas=cv.copyMakeBorder(bits,64,64,64,64,cv.BORDER_CONSTANT,value=255)
            if not cv.imwrite(str(args.out/("page-%02d.png"%i)),canvas):p.error("Could not save marker.")
        return
    cap=cv.VideoCapture(args.camera)
    if not cap.isOpened():p.error("Cannot open the selected webcam.")
    token=os.getenv("OPENEXHIBIT_TOKEN","")
    if len(token)<16:p.error("Set the local gateway token in OPENEXHIBIT_TOKEN.")
    mat=np.array(json.loads(args.homography.read_text())["matrix"]) if args.homography else None
    previous=None; candidate=None; stable=0; last_page=None
    detector=cv.aruco.ArucoDetector(dictionary) if dictionary is not None else None
    cascade=cv.CascadeClassifier(cv.data.haarcascades+"haarcascade_frontalface_default.xml") if args.mode=="face" else None
    try:
        with socket.create_connection(("127.0.0.1",args.port),timeout=3) as sock, sock.makefile("rwb") as stream:
            send(stream,{"op":"hello","v":1,"token":token})
            if json.loads(stream.readline()).get("op")!="hello":raise RuntimeError("Gateway authentication failed.")
            last_heartbeat=0
            def acknowledged():
                while True:
                    message=json.loads(stream.readline())
                    if message.get("op")=="error":raise RuntimeError(message.get("message","Gateway error."))
                    if message.get("op")=="state":return
            def emit(channel,value):
                send(stream,dict(op="inject",channel=channel,value=value))
                acknowledged()
            while cap.isOpened():
                ok,frame=cap.read()
                if not ok:raise RuntimeError("Camera disconnected.")
                gray=cv.cvtColor(frame,cv.COLOR_BGR2GRAY)
                if args.mode=="book":
                    if detector is None:
                        page=page_markers(gray,cv,np)
                    else:
                        _,ids,_=detector.detectMarkers(gray)
                        page=int(ids[0,0]) if ids is not None and len(ids)==1 else None
                    stable=stable+1 if page==candidate else 1
                    candidate=page
                    if stable>=3 and page and page!=last_page:
                        emit("page",page);last_page=page
                elif args.mode=="face":
                    emit("presence",int(len(cascade.detectMultiScale(gray,1.2,5))>0))
                else:
                    blur=cv.GaussianBlur(gray,(17,17),0)
                    if previous is not None:
                        delta=cv.threshold(cv.absdiff(previous,blur),20,255,cv.THRESH_BINARY)[1]
                        moments=cv.moments(delta,binaryImage=True)
                        found=moments["m00"]>gray.size*.002
                        if found:
                            x=moments["m10"]/moments["m00"]/gray.shape[1];y=moments["m01"]/moments["m00"]/gray.shape[0]
                            x,y=coordinates(mat,x,y,cv,np)
                            x0,y0,x1,y1=args.zone
                            found=x0<=x<=x1 and y0<=y<=y1
                            if found and args.mode=="motion":emit("motion_x",x);emit("motion_y",y)
                        if args.mode=="presence":emit("presence",int(found))
                    previous=blur
                if time.monotonic()-last_heartbeat>.5:
                    send(stream,{"op":"heartbeat"});acknowledged();last_heartbeat=time.monotonic()
                if args.preview:
                    cv.imshow("OpenExhibit camera preview",frame)
                    if cv.waitKey(1)==27:break
                time.sleep(.06)
    except KeyboardInterrupt:
        pass
    finally:
        cap.release()
        if args.preview:cv.destroyAllWindows()
if __name__=="__main__":main()
