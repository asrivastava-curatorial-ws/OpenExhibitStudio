extends Control
const Stage=preload("res://core/stage.gd")
const StyleKit=preload("res://core/skin.gd")
const Model=preload("res://core/project.gd")
signal picked(id)
signal transformed(id,rect)
var host
var stage
var overlay:Control
var fit=1.0
var origin=Vector2.ZERO
var zoom=1.0
var active=""
var start=Vector2.ZERO
var original=[]
var proposed=[]
var resize_drag=false
var snap=true
var session
var current=""
var directory=""
var testing=false

class Guide extends Control:
	var owner_canvas
	func _draw(): owner_canvas.guides(self)
	func _gui_input(e): owner_canvas.input_on_canvas(e)

func _ready():
	clip_contents=true
	resized.connect(layout_view)
	mouse_filter=Control.MOUSE_FILTER_STOP

func configure(s,dir: String,id: String,selection: String,play_mode=false):
	session=s
	current=id
	directory=dir
	testing=play_mode
	active=selection
	StyleKit.clear(self)
	stage=Stage.new()
	add_child(stage)
	stage.configure(s,dir,"@live" if testing else id,not testing)
	overlay=Guide.new()
	overlay.owner_canvas=self
	add_child(overlay)
	StyleKit.fill(overlay)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE if testing else Control.MOUSE_FILTER_STOP
	layout_view()
	queue_redraw()

func layout_view():
	if not is_instance_valid(stage) or not session: return
	var dims=Vector2(session.project.canvas[0],session.project.canvas[1])
	fit=maxf(0.05,minf((size.x-48)/dims.x,(size.y-48)/dims.y))*zoom
	origin=(size-dims*fit)/2
	stage.scale=Vector2.ONE*fit
	stage.position=origin
	if is_instance_valid(overlay): overlay.queue_redraw()
	queue_redraw()

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("#0b1016"))
	for x in range(12,int(size.x),20):
		for y in range(12,int(size.y),20): draw_circle(Vector2(x,y),1.0,Color("#25303b"))

func guides(g:Control):
	if not is_instance_valid(stage) or testing: return
	g.draw_rect(Rect2(origin-Vector2.ONE,stage.size*fit+Vector2(2,2)),Color("#384757"),false,1)
	if active=="" or not stage.nodes.has(active): return
	var n=stage.nodes[active]
	var rect=Rect2(origin+n.position*fit,n.size*fit)
	g.draw_rect(rect,StyleKit.MINT,false,1.5)
	for v in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		g.draw_rect(Rect2(v-Vector2(3,3),Vector2(6,6)),StyleKit.MINT)
	if not original.is_empty():
		g.draw_line(Vector2(rect.position.x,origin.y),Vector2(rect.position.x,origin.y+stage.size.y*fit),Color(StyleKit.BLUE,0.48),1)
		g.draw_line(Vector2(origin.x,rect.position.y),Vector2(origin.x+stage.size.x*fit,rect.position.y),Color(StyleKit.BLUE,0.48),1)

func input_on_canvas(e):
	if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT:
		var p=(e.position-origin)/fit
		if e.pressed:
			start=p
			var objs=stage.current().objects
			resize_drag=false
			if active and stage.nodes.has(active):
				var n=stage.nodes[active]
				resize_drag=p.distance_to(n.position+n.size)*fit<12
			if not resize_drag:
				active=""
				for j in range(objs.size()-1,-1,-1):
					var item=objs[j]
					if item.get("hidden",false) or item.get("locked",false): continue
					if Rect2(item.rect[0],item.rect[1],item.rect[2],item.rect[3]).has_point(p):
						active=item.id
						break
			original=[]
			proposed=[]
			if active: original=Model.lookup(objs,active).rect.duplicate()
			picked.emit(active)
		elif not original.is_empty():
			var result=proposed.duplicate()
			original=[]
			proposed=[]
			if not result.is_empty(): transformed.emit(active,result)
		overlay.queue_redraw()
	elif e is InputEventMouseMotion and not original.is_empty() and e.button_mask&MOUSE_BUTTON_MASK_LEFT:
		var delta=(e.position-origin)/fit-start
		var grid=8.0 if snap and not e.alt_pressed else 1.0
		proposed=original.duplicate()
		var i=2 if resize_drag else 0
		proposed[i]=snappedf(original[i]+delta.x,grid)
		proposed[i+1]=snappedf(original[i+1]+delta.y,grid)
		if resize_drag:
			proposed[2]=maxf(8,proposed[2])
			proposed[3]=maxf(8,proposed[3])
		var n=stage.nodes[active]
		n.position=Vector2(proposed[0],proposed[1])
		n.size=Vector2(proposed[2],proposed[3])
		overlay.queue_redraw()
