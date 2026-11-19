#!/usr/bin/env python3
"""Compare actual GPU-rendered feeds with an independent numerical reference."""
import argparse
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path
import numpy as np
from PIL import Image
import cv2
ROOT=Path(__file__).resolve().parents[1]
CORNERS=np.float32([[0,0],[1,0],[1,1],[0,1]])
FACES=np.array([[231,48,51],[35,202,89],[61,95,229],[238,204,39],[203,77,212],[27,187,202]],dtype=np.uint8)
TILES=[(1,1),(2,1),(3,1),(0,1),(1,0),(1,2)]

def make(dir):
    (dir/'assets').mkdir()
    sy,sx=192,320
    X,Y=np.meshgrid((np.arange(sx)+.5)/sx,(np.arange(sy)+.5)/sy)
    source=np.dstack((X,Y,.18+.50*X+.24*Y))
    Image.fromarray(np.rint(255*source).astype('uint8')).save(dir/'uv.png')
    Image.new('RGB',(64,64),'white').save(dir/'white.png')
    mask=np.zeros((91,167),np.uint8);mask[:,84:]=255
    Image.fromarray(mask).save(dir/'assets/mask.png')
    cross=np.zeros((150,200,3),np.uint8)
    for col,(x,y) in zip(FACES,TILES):cross[50*y:50*y+50,50*x:50*x+50]=col
    Image.fromarray(cross).save(dir/'cross.png')
    cases=[]
    def add(name,kind='plane',source='uv.png',geo=None,longitude=0,**kw):
        o=dict(id='test',surface='surface',size=[167,91],screen=0,warp=CORNERS.tolist(),view=[0,0,1,1],blend=[0,0,0,0],
               gain=[1,1,1],black=0,gamma=1,throw=1,position=[0,0,4],aim=[0,0,0],shift=[0,0]);o.update(kw)
        s=dict(id='surface',kind=kind,radius=2,height=2.4,arc=360);s.update(geo or {})
        cases.append(dict(name=name,source=source,surface=s,output=o,longitude=longitude))
    add('plain');add('corner',warp=[[.11,.05],[.93,.15],[.82,.94],[.03,.82]],view=[.14,.07,.72,.87])
    add('maskgain',mask='mask',gamma=1.65,gain=[.8,.65,.92],black=.12)
    add('left',source='white.png',blend=[0,.6,0,0],blend_power=2.4)
    add('right',source='white.png',blend=[.6,0,0,0],blend_power=2.4)
    add('mesh',mesh=[[0,0],[.5,0],[1,0],[0,.5],[.42,.59],[1,.5],[0,1],[.5,1],[1,1]])
    add('sphere','sphere',longitude=17,position=[0,0,4.8],throw=.72)
    add('rotated_sphere','sphere',longitude=-29,geo={'position':[1,.3,-.7],'rotation':[0,42,0]},position=[1,.3,4.1],aim=[1,.3,-.7],shift=[.08,-.06],throw=.7)
    add('cylinder','cylinder',geo={'height':1.15,'arc':160},position=[0,0,0],aim=[.25,.06,1],throw=.46)
    add('seam','cylinder',geo={'height':2.5,'arc':360},position=[0,0,0],aim=[.02,0,-1],throw=.6)
    add('fulldome','dome',longitude=42)
    for j,eye in enumerate(([0,0,4.8],[4.8,0,0],[0,0,-4.8],[-4.8,0,0],[0,4.8,0],[0,-4.8,0])):
        add('cube'+str(j),'sphere',source='cross.png',geo={'source_layout':'cubemap_cross'},position=eye,throw=.9)
    (dir/'cases.json').write_text(json.dumps(cases));return cases

def oracle(c,x,y):
    o,s=c['output'],c['surface'];w,h=o['size']
    p=np.array([(x+.5)/w,(y+.5)/h]);H=cv2.getPerspectiveTransform(np.float32(o['warp']),CORNERS)
    uv=cv2.perspectiveTransform(p.reshape(1,1,2),H)[0,0]
    if np.min(np.abs(np.r_[uv,1-uv]))<.007:return None
    if np.any(uv<0) or np.any(uv>1):return np.zeros(3)
    if 'mesh' in o:
        g=np.array(o['mesh']);regular=np.array([[x/2,y/2] for y in range(3) for x in range(3)])
        for i in (0,1,3,4):
            for face in ([i,i+1,i+4],[i,i+4,i+3]):
                a,b,d=g[face];bar=np.linalg.solve(np.column_stack((b-a,d-a)),uv-a)
                if np.min(bar)>=-1e-8 and sum(bar)<=1+1e-8:
                    vv=np.array([1-sum(bar),*bar])@regular[face];break
            else:continue
            break
        uv=vv
    kind=s['kind'];u,v=uv;visible=True
    coord=o['view'][:2]+uv*np.array(o['view'][2:])
    if kind in ('cylinder','sphere'):
        eye=np.array(o['position'],dtype=float);f=np.array(o['aim'])-eye;f/=np.linalg.norm(f)
        right=np.cross(f,[0,1,0] if abs(f[1])<.999999 else [1,0,0]);right/=np.linalg.norm(right)
        up=np.cross(right,f);off=(uv-.5+o['shift'])/o['throw']
        ray=f+right*off[0]*(-1 if kind=='cylinder' else 1)-up*off[1]*h/w;ray/=np.linalg.norm(ray)
        # Rotate both the ray and its origin into the surface frame.
        origin=eye-np.array(s.get('position',[0,0,0]));yaw=-math.radians(s.get('rotation',[0,0,0])[1])
        R=np.array([[math.cos(yaw),0,math.sin(yaw)],[0,1,0],[-math.sin(yaw),0,math.cos(yaw)]])
        origin=R@origin;ray=R@ray
        axes=[0,2] if kind=='cylinder' else [0,1,2];a=ray[axes];b=origin[axes]
        roots=np.roots([a@a,2*a@b,b@b-s['radius']**2]);pos=[float(z.real) for z in roots if abs(z.imag)<1e-7 and z.real>0]
        if not pos:return np.zeros(3)
        hit=origin+min(pos)*ray;lng=np.arctan2(hit[0],hit[2])
        if kind=='sphere':coord=np.array([(.5+lng/(2*np.pi)+c['longitude']/360)%1,.5-np.arcsin(np.clip(hit[1]/s['radius'],-1,1))/np.pi])
        else:
            coord=np.array([.5+lng/np.deg2rad(s['arc']),.5-hit[1]/s['height']])
            if s['arc']==360:coord[0]%=1
    elif kind=='dome':
        z=(uv-.5)*2
        if abs(np.linalg.norm(z)-1)<.02:return None
        if np.linalg.norm(z)>1:return np.zeros(3)
        coord=np.array([(.5+np.arctan2(z[0],-z[1])/(2*np.pi)+c['longitude']/360)%1,np.linalg.norm(z)*.5])
    if np.any(coord<0) or np.any(coord>1):return np.zeros(3)
    if c['source']=='white.png':rgb=np.ones(3)
    elif c['source']=='cross.png':
        a=(coord[0]-.5)*2*np.pi;b=(.5-coord[1])*np.pi
        d=[np.sin(a)*np.cos(b),np.sin(b),np.cos(a)*np.cos(b)];ax=int(np.argmax(abs(np.array(d))))
        idx=({0:(1,3),1:(4,5),2:(0,2)}[ax])[0 if d[ax]>0 else 1];rgb=FACES[idx]/255
    else:rgb=np.array([*coord,.18+.5*coord[0]+.24*coord[1]])
    rgb=o['black']+(1-o['black'])*np.power(np.maximum(0,rgb*o['gain']),1/o['gamma'])
    for d,edge in zip([u,1-u,v,1-v],o['blend']):
        if edge:
            t=np.clip(d/edge,0,1);power=o['blend_power'];rgb*=t**power/(t**power+(1-t)**power)
    if 'mask' in o and x<84:rgb*=0
    return np.clip(rgb*255,0,255)

def run(engine):
    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp);cases=make(root)
        result=subprocess.run([engine,'--audio-driver','Dummy','--path',str(ROOT/'app'),'--script','res://qa/render_calibration.gd','--','--fixture',str(root)],capture_output=True,text=True,timeout=100)
        if result.returncode or 'ERROR:' in result.stderr:raise RuntimeError(result.stdout+result.stderr)
        total=0;highest=0
        for case in cases:
            img=np.asarray(Image.open(root/(case['name']+'.png')).convert('RGB'),float)
            deviations=[]
            for y in range(2,img.shape[0]-1,5):
                for x in range(2,img.shape[1]-1,6):
                    expected=oracle(case,x,y)
                    if expected is not None:deviations.append(float(np.max(np.abs(img[y,x]-expected))))
            a=np.array(deviations);worst=float(a.max());p99=float(np.quantile(a,.99));total+=len(a);highest=max(highest,worst)
            print(f"{case['name']:18s} samples={len(a):4d} p99={p99:.2f} max={worst:.2f}",flush=True)
            if p99>2.6 or worst>4.5:raise AssertionError(case['name']+' exceeded RGB code tolerance')
        left=np.array(Image.open(root/'left.png'),float)[45,:,0];right=np.array(Image.open(root/'right.png'),float)[45,:,0]
        # Two images overlapped by 60%, sampled at the same location in physical space.
        xs=np.linspace(.005,.595,100);centers=(np.arange(len(left))+.5)/len(left)
        energy=np.interp(xs+.4,centers,left)+np.interp(xs,centers,right)
        if np.abs(energy-255).max()>1.8:raise AssertionError('Overlap brightness dip')
        print(f"PASS {len(cases)} real rendered rasters, {total} RGB probes, largest deviation {highest:.2f}/255; overlap sum max error {np.abs(energy-255).max():.2f}/255.")
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--godot',default='godot');run(p.parse_args().godot)
