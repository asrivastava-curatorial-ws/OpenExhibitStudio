"""Translate local Office slide text and images or PDF pages into quiz content rounds."""
import base64
import io
import os
import posixpath
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from .deck import Invalid, validate

A='{http://schemas.openxmlformats.org/drawingml/2006/main}'
P='{http://schemas.openxmlformats.org/presentationml/2006/main}'
R='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'


def rels(z, directory, name):
    doc=ET.fromstring(z.read(posixpath.join(directory,'_rels',name+'.rels')))
    return {r.get('Id'):posixpath.normpath(posixpath.join(directory,r.get('Target',''))) for r in doc if r.get('TargetMode','Internal')=='Internal'}


def image_url(data, suffix):
    if suffix in ('.png','.jpg','.jpeg') and len(data)<=524288:
        return 'data:image/'+('png' if suffix=='.png' else 'jpeg')+';base64,'+base64.b64encode(data).decode()
    return None


def content(text,picture=None):
    s=dict(type='slide',prompt=(text.strip() or 'Untitled slide')[:500],seconds=45,points=0)
    if picture:s['image']=picture
    return s


def convert(data,name):
    suffix=Path(name).suffix.lower()
    slides=[]
    if suffix=='.pptx':
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            if len(z.infolist())>5000 or sum(i.file_size for i in z.infolist())>64*1024*1024:raise Invalid("Slide package exceeds import limits.")
            rel=rels(z,'ppt','presentation.xml')
            present=ET.fromstring(z.read('ppt/presentation.xml'))
            for item in present.findall('.//'+P+'sldId')[:150]:
                name_=rel[item.get(R+'id')]
                if not name_.startswith('ppt/slides/'):raise Invalid("Unexpected presentation part.")
                doc=ET.fromstring(z.read(name_))
                words=[t.text for t in doc.iter(A+'t') if t.text];pic=None
                for blip in doc.iter(A+'blip'):
                    link=rels(z,posixpath.dirname(name_),posixpath.basename(name_)).get(blip.get(R+'embed'),'')
                    if link.startswith('ppt/media/') and link in z.namelist():
                        pic=image_url(z.read(link),Path(link).suffix.lower())
                        if pic:break
                slides.append(content(' '.join(words),pic))
    elif suffix=='.pdf':
        program=shutil.which('pdftoppm');inspector=shutil.which('pdfinfo')
        if not program or not inspector:raise Invalid("Install Poppler for PDF slide import.")
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp)/'slides.pdf';f.write_bytes(data)
            env=dict(os.environ,LC_ALL='C')
            info=subprocess.run([inspector,str(f)],capture_output=True,text=True,env=env,timeout=20)
            pages=next((int(line.split(':',1)[1]) for line in info.stdout.splitlines() if line.startswith('Pages:')),0)
            if not 1<=pages<=60:raise Invalid("Choose a readable PDF with at most 60 pages.")
            proc=subprocess.run([program,'-jpeg','-scale-to','950','-jpegopt','quality=72',str(f),str(Path(tmp)/'page')],capture_output=True,timeout=80)
            if proc.returncode:raise Invalid("Poppler could not render these slides.")
            for i,p in enumerate(sorted(Path(tmp).glob('page-*.jpg')),1):
                pic=image_url(p.read_bytes(),'.jpg')
                if not pic:raise Invalid("A rendered PDF page exceeded the image limit.")
                slides.append(content(f"Page {i}",pic))
    else:raise Invalid("Select a PPTX or PDF file.")
    if sum(len(s.get('image','')) for s in slides)>6_000_000:raise Invalid("Imported images exceed the deck limit. Import fewer slides.")
    return validate(dict(format='oes-quiz',version=1,title=Path(name).stem[:100] or 'Imported slides',teams=[],questions=slides))
