#!/usr/bin/env python3
"""Check an installed physical planar screen using separately surveyed, projected targets."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from calibrate import CalibrationError, camera_quad, cvlib, transform, write_json


def check(v):
    cv=cvlib()
    for key in ['site','projector_serial','camera_id','operator','capture_time']:
        if not isinstance(v.get(key),str) or not v[key].strip():raise CalibrationError("Supply "+key+".")
    size=np.asarray(v['physical_size_mm'],float)
    if size.shape!=(2,) or not np.isfinite(size).all() or np.any(size<=0):raise CalibrationError("Supply measured physical width and height in mm.")
    cam=v['camera_size']
    corners=camera_quad(v['screen_corners'],*cam)
    C=cv.getPerspectiveTransform(corners,np.float32([[0,0],[size[0],0],size,[0,size[1]]]))
    points=np.asarray(v['observed_camera_px'],float)
    expected=np.asarray(v['requested_uv'],float)
    if points.ndim!=2 or points.shape[1]!=2 or points.shape!=expected.shape or len(points)<9 or not np.isfinite(points).all() or not np.isfinite(expected).all() or np.any(expected<=0) or np.any(expected>=1) or np.any(points<0) or np.any(points>=np.asarray(cam)):
        raise CalibrationError("Supply at least nine independent in-frame observations and their requested UV positions.")
    if len(set((min(2,int(x*3)),min(2,int(y*3))) for x,y in expected))!=9:
        raise CalibrationError("Inspect all nine screen regions.")
    measured=transform(points,C)
    error=np.linalg.norm(measured-expected*size,axis=1)
    tolerance=float(v["limit_mm"])
    if not np.isfinite(tolerance) or tolerance<=0:raise CalibrationError("Set the site's allowed error in mm.")
    return dict(format="oes-site-check",version=1,site=v["site"],projector_serial=v["projector_serial"],camera_id=v["camera_id"],
                operator=v["operator"],capture_time=v["capture_time"],status="within-site-limit" if error.max()<=tolerance else "outside-site-limit",
                targets=len(error),p95_mm=float(np.quantile(error,.95)),maximum_mm=float(error.max()),limit_mm=tolerance,
                measurements_mm=error.tolist())


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('observations',type=Path);p.add_argument('--photo',type=Path,required=True);p.add_argument('--profile',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    try:
        v=json.loads(a.observations.read_text());r=check(v)
        from PIL import Image
        with Image.open(a.photo) as im:
            if list(im.size)!=list(v['camera_size']):raise CalibrationError("Evidence image dimensions differ from observations.")
            im.verify()
        for key,path in [('photo',a.photo),('profile',a.profile),('observations',a.observations)]:
            r[key+'_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        write_json(a.out,r);print(r['status'],round(r['maximum_mm'],3),'mm maximum residual')
        raise SystemExit(0 if r['status']=='within-site-limit' else 1)
    except (ValueError,OSError,KeyError,TypeError) as exc:p.exit(2,str(exc)+'\n')
