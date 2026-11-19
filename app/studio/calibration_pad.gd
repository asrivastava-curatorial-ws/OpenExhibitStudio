extends Control
const StyleKit=preload("res://core/skin.gd")
signal changed(points)
var points=[]
var drag=-1
func _draw():
	var bounds=Rect2(Vector2(12,12),size-Vector2(24,24))
	draw_rect(bounds,Color("#0c1520"))
	for j in range(1,8):
		draw_line(bounds.position+Vector2(bounds.size.x*j/8,0),bounds.position+Vector2(bounds.size.x*j/8,bounds.size.y),StyleKit.LINE)
	for i in points.size():
		var a=bounds.position+Vector2(points[i][0],points[i][1])*bounds.size
		var links=[]
		if points.size()==4:links=[(i+1)%4]
		else:
			if i%3<2:links.append(i+1)
			if i<6:links.append(i+3)
		for j in links:
			var b=bounds.position+Vector2(points[j][0],points[j][1])*bounds.size
			draw_line(a,b,StyleKit.MINT,2,true)
		draw_circle(a,7,StyleKit.BLUE)
func _gui_input(ev):
	var bounds=Rect2(Vector2(12,12),size-Vector2(24,24))
	if ev is InputEventMouseButton and ev.button_index==MOUSE_BUTTON_LEFT:
		if ev.pressed:
			for i in points.size():
				var p=bounds.position+Vector2(points[i][0],points[i][1])*bounds.size
				if ev.position.distance_to(p)<18: drag=i;break
		elif drag>=0:
			drag=-1
			changed.emit(points.duplicate(true))
	if drag>=0 and ev is InputEventMouseMotion:
		var pos=((ev.position-bounds.position)/bounds.size).clamp(Vector2.ZERO,Vector2.ONE)
		points[drag]=[pos.x,pos.y]
		queue_redraw()
