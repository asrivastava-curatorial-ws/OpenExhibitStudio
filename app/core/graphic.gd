extends Control
const StyleKit=preload("res://core/skin.gd")
var data={}
var session
var clock=0.0
const PLANETS=["Mercury","Venus","Earth","Mars","Jupiter","Saturn","Uranus","Neptune"]
const YEARS=[0.24085,0.6152,1.0,1.8808,11.862,29.46,84.01,164.8]
const TINTS=["#aaa392","#efbd75","#64baf1","#ea8b72","#dfb490","#e8d3a2","#86d6ce","#769df4"]
func _process(dt):
	if data.get("kind","") in ["orbit","particles"] and not data.get("static",false):
		clock+=dt
		queue_redraw()
func _draw():
	if not session or size.x<2 or size.y<2: return
	var accent=Color.from_string(str(data.get("color","#6adcca")),StyleKit.MINT)
	var value=session.vars.get(str(data.get("bind","value")),0)
	match data.get("kind",""):
		"orbit":
			var center=size*Vector2(0.50,0.52)
			var scale_r=minf(size.x*0.48,size.y*0.70)
			for i in 76:
				var pos=Vector2(fposmod(i*173.21+20,size.x),fposmod(i*i*7.31+18,size.y))
				draw_circle(pos,1.1 if i%6 else 2.0,Color(0.55,0.72,0.91,0.22+i%4*0.12))
			for i in 8:
				var r=scale_r*(0.15+0.105*i)
				var oval=PackedVector2Array()
				for j in 121:
					var a=TAU*j/120.0
					oval.append(center+Vector2(cos(a)*r,sin(a)*r*0.54))
				draw_polyline(oval,Color("#2d435b"),1.5,true)
				var phase=i*1.89+0.7+clock*0.12/maxf(YEARS[i],0.2)
				var planet=center+Vector2(cos(phase)*r,sin(phase)*r*0.54)
				var radius=[3,6,7,5,13,10,8,8][i]*scale_r/320.0+2
				draw_circle(planet,radius,Color(TINTS[i]),true,-1,true)
				draw_circle(planet+Vector2(-radius*0.28,-radius*0.27),radius*0.32,Color(1,1,1,0.22))
				if i==5: draw_line(planet-Vector2(radius*1.6,radius*0.35),planet+Vector2(radius*1.6,radius*0.35),Color("#c9af88"),3,true)
			for j in range(5,0,-1): draw_circle(center,8+j*5,Color(1,0.69,0.25,0.035))
			draw_circle(center,13,Color("#ffca74"),true,-1,true)
		"grid":
			var step=maxf(size.x/24.0,12)
			for x in range(0,int(size.x)+1,int(step)): draw_line(Vector2(x,0),Vector2(x,size.y),accent.darkened(0.45),1)
			for y in range(0,int(size.y)+1,int(step)): draw_line(Vector2(0,y),Vector2(size.x,y),accent.darkened(0.45),1)
			draw_line(Vector2.ZERO,size,accent,2,true)
			draw_line(Vector2(size.x,0),Vector2(0,size.y),accent,2,true)
			draw_arc(size/2,minf(size.x,size.y)*0.33,0,TAU,96,accent,2,true)
		"gauge","plot":
			var low=float(data.get("min",0))
			var high=maxf(low+0.001,float(data.get("max",100)))
			draw_rect(Rect2(Vector2.ZERO,size),Color("#101f2d"))
			for i in 6:
				var y=(size.y-1)*i/5.0
				draw_line(Vector2(0,y),Vector2(size.x,y),Color("#27394c"))
			if data.kind=="gauge":
				var v=float(value) if value is float or value is int else 0.0
				draw_rect(Rect2(0,size.y*0.3,size.x*clampf((v-low)/(high-low),0,1),size.y*0.4),accent)
			else:
				var arr=session.history.get(str(data.get("channel","dial")),[])
				var pts=PackedVector2Array()
				for i in arr.size():
					if arr[i] is float or arr[i] is int: pts.append(Vector2(i*size.x/maxf(arr.size()-1,1),size.y*(1-clampf((float(arr[i])-low)/(high-low),0,1))))
				if pts.size()>1: draw_polyline(pts,accent,3,true)
		"drawing":
			draw_rect(Rect2(Vector2.ZERO,size),Color.from_string(data.get("background","#122334"),Color.BLACK))
			if value is Array:
				var last=null
				for v in value:
					if v is Array and v.size()==2:
						var next=Vector2(v[0]*size.x,v[1]*size.y)
						if last!=null: draw_line(last,next,accent,4,true)
						else: draw_circle(next,2,accent)
						last=next
					else: last=null
		"particles":
			var center=size*Vector2(clampf(float(session.vars.get("motion_x",0.5)),0,1),clampf(float(session.vars.get("motion_y",0.5)),0,1))
			for i in 75:
				var magnitude=fposmod(clock*34+i*17,minf(size.x,size.y)*0.7)
				var pos=center+Vector2.from_angle(i*2.39996)*magnitude
				draw_circle(pos,2+i%5,Color(accent,1.0-magnitude/maxf(minf(size.x,size.y),1)))
		"fractal":
			var pts=PackedVector2Array([Vector2(size.x/2,2),Vector2(2,size.y-2),size-Vector2(2,2)])
			triangle(pts[0],pts[1],pts[2],clampi(int(value),0,7),accent)

func triangle(a:Vector2,b:Vector2,c:Vector2,depth:int,color:Color):
	if depth<=0:
		draw_colored_polygon(PackedVector2Array([a,b,c]),color)
		return
	var ab=(a+b)/2
	var ac=(a+c)/2
	var bc=(b+c)/2
	triangle(a,ab,ac,depth-1,color)
	triangle(ab,b,bc,depth-1,color)
	triangle(ac,bc,c,depth-1,color)
