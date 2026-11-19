#!/usr/bin/env python3
"""Rebuild the sample projects. Preserves the supplied raster and movie masters."""
import copy
import hashlib
import json
import math
import random
import shutil
import sys
import wave
from pathlib import Path
from struct import pack

ROOT = Path(__file__).resolve().parents[1]
CAT = json.loads((ROOT/"tools/data/layouts.json").read_text(encoding="utf8"))
MINT, INK, PAPER, MUTED = "#75e2cb", "#101e2e", "#eaf2f9", "#a2b8ca"
W, H = 1280, 720


def scene(id, name, bg=INK, transition="fade"):
    return dict(id=id, name=name, background=bg, transition=transition, objects=[])


def component(s, id, kind, rect, **props):
    s["objects"].append(dict(id=id, name=props.pop("name", id.replace("_"," ").title()), kind=kind, rect=rect, **props))


def label(s, id, msg, rect, size=26, color=PAPER, **extra):
    component(s, id, "text", rect, text=msg, font=size, color=color, **extra)


def panel(s, id, rect, fill="#172b3c", **extra):
    component(s, id, "panel", rect, color=fill, **extra)


def button(s, id, text, x, y, w, ev="", **extra):
    component(s, id, "button", [x,y,w,62], text=text, font=23, event=ev or "tap."+id, color=MINT, **extra)


def header(s, topic, title, sub):
    label(s,"eyebrow",topic,[48,27,1160,35],17,MINT)
    label(s,"title",title,[46,68,1190,78],54)
    label(s,"subtitle",sub,[49,151,1175,60],23,MUTED)


def action(op, target="", value=1):
    return dict(op=op, target=target, value=value)


def rule(p, ev, acts, cond=None):
    d=dict(id="rule_"+str(len(p["rules"])+1),event=ev,actions=acts)
    if cond:
        d["if"]=cond
    p["rules"].append(d)


def eq(rhs, left="$value"):
    return {"op":"==","left":left,"right":rhs}


class Exhibit:
    def __init__(self, slug, title, layout="Kiosk", dims=(W,H)):
        self.dir=ROOT/"examples"/slug
        self.dir.mkdir(exist_ok=True)
        (self.dir/"assets").mkdir(exist_ok=True)
        self.p=copy.deepcopy(CAT["project"])
        self.p.update(title=title,canvas=list(dims),scenes=[],start="main",assets={})
        self.p["installation"]=copy.deepcopy(CAT["layouts"][layout])
        self.p["settings"]={"idle_seconds":120,"autoplay":""}

    def new(self,id,name,bg=INK,transition="fade"):
        sc=scene(id,name,bg,transition)
        self.p["scenes"].append(sc)
        return sc

    def asset(self,name,data=None):
        dest=self.dir/"assets"/name
        if data is not None:
            if isinstance(data,str):
                dest.write_text(data,encoding="utf8")
            else:
                dest.write_bytes(data)
        key=name.split(".")[0].replace("-","_")
        self.p["assets"][key]={"path":"assets/"+name,"sha256":hashlib.sha256(dest.read_bytes()).hexdigest()}
        return key

    def decorate(self,s):
        stroke='<path d="M2 12H94m0 0 13-8m-13 8 13 8" stroke="#6ddac1" stroke-width="2" fill="none"/>'
        self.asset("direction.svg",'<svg xmlns="http://www.w3.org/2000/svg" width="115" height="24">'+stroke+'</svg>')
        component(s,"direction","image",[1125,37,108,23],asset="direction")

    def devices(self,profile,inputs,outputs=()):
        self.p["devices"]=[dict(id=profile,channels=[dict(id=c,direction="input") for c in inputs]+[dict(id=c,direction="output") for c in outputs])]

    def finish(self,action_text,hardware="Touchscreen or mouse.",physical="",source=""):
        (self.dir/"project.oes.json").write_text(json.dumps(self.p,indent=2,ensure_ascii=False)+"\n",encoding="utf8")
        (self.dir/"README.md").write_text("# "+self.p["title"]+"\n\nOpen project.oes.json in Studio and choose **Test exhibit**, or open it in the standalone Player.\n\n"+action_text+"\n\n**Installation.** "+hardware+"\n\n"+physical+"\n\n"+source+"\n",encoding="utf8")


def solar():
    e=Exhibit("01-solar","Orbital atlas")
    p=e.p; s=e.new("main","Orbital atlas","#0b1b2a")
    header(s,"ASTRONOMY   /   INTERACTIVE ATLAS","A year around the Sun","Choose a planet. Compare the time it takes to complete one orbit.")
    component(s,"orbit_diagram","orbit",[30,201,784,417])
    panel(s,"fact_panel",[837,228,391,310],"#162c3b",border="#2c4b59")
    label(s,"focus_label","SELECTED PLANET",[862,250,325,35],16,MINT)
    label(s,"planet","{planet}",[858,303,344,66],50)
    label(s,"period","{days} Earth days",[861,393,346,62],28,"#f2c789")
    label(s,"period_label","Mean orbital period",[864,467,325,46],20,MUTED)
    p["variables"]={"planet":"Earth","days":365.26}
    for i,(planet,days) in enumerate([("Mercury",87.97),("Earth",365.26),("Mars",686.98),("Jupiter",4332.59)]):
        button(s,planet.lower(),planet,47+i*194,626,180)
        rule(p,"tap."+planet.lower(),[action("set","planet",planet),action("set","days",days)])
    label(s,"scale_note","Sizes and distances simplified.",[846,587,380,75],18,MUTED)
    e.decorate(s)
    e.finish("Select Mars to read 686.98 Earth days. The rings are schematic. Relative orbital rates use sidereal years.","Single 16:9 touchscreen. No hardware gateway.","","Planet data: https://nssdc.gsfc.nasa.gov/planetary/factsheet/")

def history():
    e=Exhibit("02-panorama","Electricity across time","Linear panorama",(2880,720))
    p=e.p;s=e.new("main","Three epochs")
    for i,(date,name,body) in enumerate([("1800","Volta’s pile","Stacked metals and an electrolyte produced a continuing electric current."),("1831","Faraday’s coil","Changing magnetic flux through a coil induced an electromotive force."),("1882","Power for a city","The Pearl Street station began supplying electricity in lower Manhattan.")]):
        x=i*960
        panel(s,"board"+str(i),[x,0,960,720],["#112536","#162b37","#142337"][i],radius=0)
        label(s,"epoch"+str(i),"HISTORY OF ELECTRICITY",[x+64,72,790,50],23,MINT)
        label(s,"date"+str(i),date,[x+53,154,790,194],122,"#f1c984")
        label(s,"name"+str(i),name,[x+63,345,822,88],54)
        label(s,"body"+str(i),body,[x+67,445,800,154],32,MUTED)
    e.decorate(s)
    e.finish("In the Mapping workspace, select each of the three feeds. Adjacent feeds include a shared strip with complementary linear blend ramps.","Three projectors covering a horizontal screen. Assign the OS display indices in Output settings.","F2 reveals alignment grids on all outputs. A real overlap needs optical alignment and photometric tuning.","Historical background: https://www.nps.gov/articles/5-the-origins-of-hydroelectric-power.htm")
def earth():
    e=Exhibit("03-earth","Earth in longitude","Earth sphere",(1440,720))
    p=e.p;s=e.new("main","Geographic layer")
    key=e.asset("earth.png")
    component(s,"earth","image",[0,0,1440,720],asset=key,stretch=True)
    p["variables"]={"longitude":0}
    rule(p,"input.encoder",[action("set","longitude","$value")])
    e.devices("uno",["encoder"])
    e.finish("In Hardware inject encoder = 45. The Mapping preview (Exhibit content) shifts longitude by 45°. Input is an absolute angle in degrees; the supplied encoder sketch reports one degree per accepted tick.","Four projectors around a matte sphere. Projector distance, aim and throw must be measured. Example radius 2 m.","Use the Uno sketch with encoder A on D3, B on D4 and common ground. Four equatorial projectors leave polar caps outside their illumination. The coverage tool quantifies the gaps from the configured geometry.","Coastline texture from public-domain Natural Earth data, processed by QGIS. No political boundary overlay. https://www.naturalearthdata.com/about/terms-of-use/")
def cylinder():
    e=Exhibit("04-cyclorama","Waves in three languages","Cyclorama",(2160,720))
    p=e.p;s=e.new("main","Wave field")
    for i,(title,sub) in enumerate([("Waves","A wave transfers energy."),("তরঙ্গ","তরঙ্গ শক্তি সঞ্চালন করে।"),("तरंगें","तरंग ऊर्जा का संचार करती है।")]):
        x=i*720
        label(s,"name"+str(i),title,[x+42,94,635,110],67)
        label(s,"sub"+str(i),sub,[x+45,233,636,112],36,MINT)
    wave_art='<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="220" viewBox="0 0 2160 220">'
    for j in range(5):
        pts=" ".join("%d,%.2f"%(x,105+math.sin(x/2160*math.tau*6+j*.26)*(67-j*7)) for x in range(0,2161,5))
        wave_art+='<polyline fill="none" stroke="%s" stroke-width="3" points="%s"/>'%(["#67dec6","#62b9c8","#518fab","#4c729c","#426182"][j],pts)
    key=e.asset("waves.svg",wave_art+"</svg>")
    component(s,"wave","image",[0,388,2160,220],asset=key,stretch=True)
    e.finish("Compare the three scripts across a 180° cylinder. Open Installation to change radius or height and rebuild a layout. Try the 360° ring preset with the same wave texture.","Three projectors in a cylinder. Physical screen height and arc remain common to all feeds.","Bengali and Devanagari fallback fonts are included.")
def room():
    e=Exhibit("05-room","Inside a wave","Immersive room")
    p=e.p
    for i,(name,heading,sub,col) in enumerate([("main","Source","A disturbance starts here.","#132b3b"),("right","Propagation","Follow the disturbance across the room.","#163447"),("back","Reflection","A boundary returns part of the wave.","#203144"),("left","Interference","Overlapping waves add together.","#203445"),("floor","Particle motion","Touch the surface to change the field.","#102e32"),("ceiling","Wavefront","A wavefront joins points at the same phase.","#232639")]):
        s=e.new(name,heading,col)
        header(s,"WAVE ROOM   /   "+["FRONT","RIGHT","BACK","LEFT","FLOOR","CEILING"][i],heading,sub)
        component(s,"field","particles",[80,236,1120,415],color=["#8ddadc","#a2c3eb","#e1b597","#d6b0dc","#88e4b1","#c1b1f1"][i])
        e.decorate(s)
        p["installation"]["outputs"][i].update(scene=name,view=[0,0,1,1])
    e.finish("Start the Player to open six independent surface feeds. In Mapping choose each output. To use continuous shared artwork, reapply the Immersive room preset and author a 4 × 3 cube-cross atlas.","Six outputs for front, right, back, left, floor and ceiling. This preset uses independent scenes. Test all adjacency and orientation on site.")
def rock_art(e,kind):
    rng=random.Random(14)
    shapes=[]
    if kind==0:
        for _ in range(74):
            x,y=rng.randrange(500),rng.randrange(340); r=rng.randrange(4,16)
            shapes.append('<polygon points="%d,%d %d,%d %d,%d %d,%d" fill="%s"/>'%(x,y-r,x+r,y,x+3,y+r,x-r,y+3,rng.choice(["#a9bcc4","#7797a8","#d8c5ac","#4e6d7e"])))
    elif kind==1:
        for j in range(17):
            pts=" ".join("%d,%.1f"%(x,j*23+9*math.sin(x/64+j*.4)) for x in range(-10,541,10))
            shapes.append('<polyline points="'+pts+'" fill="none" stroke="'+["#d29e78","#bf815e","#e6c394","#96785e"][j%4]+'" stroke-width="18"/>')
    else:
        for j in range(23):
            pts=" ".join("%d,%.1f"%(x,j*17+27*math.sin(x/57+j*.18)) for x in range(-10,541,8))
            shapes.append('<polyline points="'+pts+'" fill="none" stroke="'+["#9fd1bd","#68998e","#bbb79f","#63828b"][j%4]+'" stroke-width="10"/>')
    return e.asset(["igneous.svg","sedimentary.svg","metamorphic.svg"][kind],'<svg xmlns="http://www.w3.org/2000/svg" width="520" height="340"><rect width="100%" height="100%" fill="#28404c"/>'+"".join(shapes)+'</svg>')
def books(physical):
    e=Exhibit("07-physical-book" if physical else "06-digital-book","Rock pages under projection" if physical else "A field guide to rocks","Physical book" if physical else "Digital book")
    p=e.p
    ids=["main","layers","pressure"]
    for j,(title,sub,detail) in enumerate([("Igneous","Cooling creates crystals.","Magma or lava solidifies. Slow cooling can give crystals more time to grow."),("Sedimentary","Sediments become rock.","Layers of sediment can be compacted and cemented together."),("Metamorphic","Heat and pressure transform.","Minerals and rock textures change while the rock remains predominantly solid.")]):
        s=e.new(ids[j],title,"#162631","slide")
        label(s,"series","FIELD NOTES   /   GEOLOGY",[50,34,850,46],20,MINT)
        label(s,"heading",title,[48,107,620,82],53)
        label(s,"sub",sub,[50,214,572,93],30,"#f0cb9c")
        label(s,"detail",detail,[50,325,550,167],27)
        key=rock_art(e,j)
        component(s,"specimen","image",[655,150,570,390],asset=key)
        label(s,"caption","Schematic rock texture",[665,550,550,42],20,MUTED)
        button(s,"previous","‹  Previous",52,625,220,"book.prev")
        button(s,"next","Next  ›",1000,625,222,"book.next")
        label(s,"page","%02d / 03"%(j+1),[552,622,190,65],23,MINT,align=1)
        rule(p,"enter."+ids[j],[action("set","page",j+1)])
        for d in [-1,1]:
            rule(p,"book."+("next" if d>0 else "prev"),[action("goto",ids[min(2,max(0,j+d))])],eq(j+1,"$page"))
        rule(p,"input.page",[action("goto",ids[j])],eq(j+1))
    p["variables"]={"page":1}
    e.devices("book",["page"])
    if physical:
        e.finish("Two independently corner-pinned outputs show the left and right parts of one logical spread. Inject page = 2 to open Sedimentary. Keyboard arrows and on-screen buttons are manual fallbacks.","Two outputs, a physical book, overhead webcam and printed markers 1–3, or an input adapter reporting page numbers.","Print print-markers.svg and run tools/vision.py book with a local gateway. For ArUco, generate PNGs with markers and select book --family aruco. Optical alignment and actual camera detection require bench testing.")
    else:
        e.finish("Turn through three illustrated pages using the buttons or keyboard arrows. Test mode supports horizontal swipes. The reader uses slide transitions and real page-specific content.")
def electricity():
    e=Exhibit("08-arduino","Build a signal","Kiosk")
    p=e.p;s=e.new("main","Signal bench")
    header(s,"PHYSICAL COMPUTING   /   ELECTRICITY","Build a signal","Move the dial. Press the switch to change the indicator.")
    label(s,"dial_read","Input level    {level} %",[54,227,735,55],29)
    component(s,"gauge","gauge",[58,308,706,80],bind="level",max=100,color=MINT)
    component(s,"dial","slider",[61,440,700,72],bind="level",channel="dial")
    component(s,"wave","plot",[810,234,395,279],channel="dial",max=100,color="#e8c084")
    button(s,"switch","Toggle indicator",58,589,380)
    label(s,"state","Indicator request   {lamp}",[485,591,735,66],27,MUTED)
    p["variables"]={"level":0,"lamp":0}
    rule(p,"input.dial",[action("set","level","$value")])
    rule(p,"input.button",[action("emit","tap.switch")],eq(1))
    rule(p,"tap.switch",[action("add","lamp",1),action("emit","lamp.check")])
    rule(p,"lamp.check",[action("set","lamp",0)],eq(2,"$lamp"))
    rule(p,"lamp.check",[action("output","lamp","$lamp")])
    e.decorate(s);e.devices("uno",["dial","button"],["lamp"])
    e.finish("Move the on-screen slider or inject dial = 75. Press Toggle indicator. In Hardware arm virtual outputs, then inject button = 1 to inspect the lamp request.","Classic Arduino Uno, Nano or Mega, potentiometer wiper on A0, momentary button from D2 to GND, built-in LED.","Use firmware/ExhibitUno and gateway/profiles/uno.json. Outputs require operator arming.")
def esp():
    e=Exhibit("09-esp32","Light and motion","Kiosk");p=e.p;s=e.new("main","Light and motion")
    header(s,"PHYSICAL COMPUTING   /   LOCAL MQTT","Light and motion","Choose a position. The same cue requests an indicator and a bounded servo angle.")
    label(s,"angle","{angle}°",[50,235,600,150],100,"#ecc58a")
    component(s,"gauge","gauge",[55,438,1150,64],bind="angle",min=30,max=150)
    for j,val in enumerate([30,90,150]):
        button(s,"pos"+str(j),str(val)+"°",56+j*250,594,220)
        rule(p,"tap.pos"+str(j),[action("set","angle",val),action("output","servo",val),action("output","light",int(j!=0))])
    rule(p,"input.button",[action("emit","tap.pos2")],eq(1))
    p["variables"]={"angle":90}
    e.decorate(s);e.devices("esp32",["button"],["light","servo"])
    e.finish("Use the three angle buttons in Test. In Hardware arm virtual outputs and pulse the button to see both output requests.","Classic ESP32 DevKit, WPA-protected isolated LAN, local Mosquitto, resistor-limited indicator and externally supplied low-torque hobby servo.","Use firmware/ExhibitESP32 and gateway/profiles/esp32.json. Flashing, output polarity and physical limits require bench commissioning.")
def floor():
    e=Exhibit("10-floor","Wake the floor","Interactive table");p=e.p;s=e.new("main","Ripple field")
    header(s,"INTERACTIVE FLOOR   /   MOTION","Wake the floor","Move through the field or use the horizontal control.")
    component(s,"particles","particles",[45,211,1190,360],color="#72e0c5")
    component(s,"horizontal","slider",[70,603,1130,70],min=0,max=1,step=.01,channel="motion_x",bind="motion_x")
    p["variables"]={"motion_x":.5,"motion_y":.5}
    for k in ["motion_x","motion_y"]:rule(p,"input."+k,[action("set",k,"$value")])
    e.decorate(s);e.devices("vision",["motion_x","motion_y"])
    e.finish("Move the slider or inject motion_x = 0.2 and motion_y = 0.7 to reposition the origin. An optional overhead webcam sends the centroid of frame differences.","Overhead projector and ordinary webcam, or just a monitor for testing.","Run tools/vision.py motion with the local gateway. Camera coordinates start at top left; the planar homography option aligns them to the floor.")
def mixed():
    e=Exhibit("11-mixed","Reef finder","Mixed installation");p=e.p
    for j,(id,title) in enumerate([("main","Find the reef"),("projection","Beneath the surface")]):
        s=e.new(id,title)
        header(s,"GEOLOGY   /   MODEL SCANNER",title,"Slide the scanner across the model." if j==0 else "The model’s position selects this geological layer.")
        label(s,"layer","{rock}",[52,261,739,114],61,"#eec795")
        component(s,"core","image",[820,244,370,260],asset=rock_art(e,j))
        if j==0: component(s,"scan","slider",[57,464,700,65],bind="dial",channel="dial")
        label(s,"pos","Scan position   {dial} %",[60,593,900,74],28,MINT)
    p["installation"]["outputs"][1].update(scene="projection",size=[1024,768])
    p["variables"]={"dial":0,"rock":"Granite"}
    rule(p,"input.dial",[action("set","dial","$value")])
    for op,name,lamp,light in [("<","Granite",0,0),(">=","Sandstone",1,1)]:
        rule(p,"input.dial",[action("set","rock",name),action("output","lamp",lamp),action("output","light",light)],{"op":op,"right":50})
    e.devices("model",["dial"],["lamp","light"])
    e.finish("In Hardware arm virtual outputs and inject dial = 70. Both output scenes show Sandstone and both indicator requests become 1. The standalone player opens the kiosk at 1280 × 720 and projector at 1024 × 768.","Touch display, projector and optional wired slider. For both real indicator channels configure the Uno and ESP32 profiles in one gateway.","Assign screen indices locally. The two indicators go through independent device endpoints.")
def draw():
    e=Exhibit("12-postcards","Visitor drawing wall","Touchscreen + projection");p=e.p
    p["variables"]={"ink":[],"caption":"","posted":[],"posted_caption":"Your drawing will appear here"}
    s=e.new("main","Drawing kiosk")
    header(s,"VISITOR STUDIO   /   DRAWING WALL","Send a shape to the wall","Draw in the box, type a caption and press Send.")
    component(s,"pad","drawing",[55,222,1170,281],bind="ink")
    component(s,"caption","entry",[55,524,1160,64],bind="caption",text="Write a short caption")
    button(s,"post","Send to projection",55,622,420);button(s,"clear","Clear pad",520,622,245)
    t=e.new("projection","Projection wall")
    label(t,"tag","VISITOR DRAWING WALL",[50,33,1100,50],23,MINT)
    component(t,"wall","drawing",[50,115,1175,447],bind="posted",readonly=True)
    label(t,"caption","{posted_caption}",[55,589,1160,90],34)
    p["installation"]["outputs"][1]["scene"]="projection"
    rule(p,"change.caption",[action("set","caption","$value")])
    rule(p,"tap.post",[action("set","posted","$ink"),action("set","posted_caption","$caption")])
    rule(p,"tap.clear",[action("clear","ink"),action("set","caption","")])
    e.decorate(s)
    e.finish("Launch the standalone player. Draw and type on output 1, then press Send to projection. Output 2 displays a snapshot. Clear the input without erasing the submitted drawing. A fresh visitor session clears both.","Two displays on one computer. The second may be a projector. This is the local projection delivery option.")
def movies():
    e=Exhibit("13-shows","Travelling waves","Kiosk");p=e.p
    for j,(id,name) in enumerate([("main","A travelling wave"),("standing","A standing wave")]):
        s=e.new(id,name,INK,"slide" if j else "fade")
        label(s,"kicker","WAVE LAB   /   FILM "+str(j+1),[42,28,1170,40],18,MINT)
        label(s,"title",name,[42,77,1190,82],48)
        component(s,"film","video",[44,186,780,440],asset=e.asset(["travelling.ogv","standing.ogv"][j]))
        label(s,"description",["Follow one crest as the wave moves across the screen.","Two equal waves travelling in opposite directions form stationary nodes."][j],[865,207,352,292],29)
        button(s,"next","Next film  ›",858,545,340)
        rule(p,"tap.next"+str(j),[action("goto",["standing","main"][j])])
        s["objects"][-1]["event"]="tap.next"+str(j)
        e.decorate(s)
    p["timelines"]=[dict(id="sequence",name="Two films",duration=12,loop=True,cues=[dict(at=0,action=action("goto","main")),dict(at=6,action=action("goto","standing"))],keys=[])]
    p["settings"]["autoplay"]="sequence"
    e.finish("Start Test exhibit or Player. Two real local Theora movies play, with a scene transition at six seconds. The twelve-second timeline loops. Next film advances manually.","Single display. FFmpeg is only needed to encode new video assets.")
if __name__=="__main__":
    for fn in [solar,history,earth,cylinder,room,lambda:books(False),lambda:books(True),electricity,esp,floor,mixed,draw,movies]:fn()
