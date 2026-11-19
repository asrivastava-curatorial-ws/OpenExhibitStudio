extends SceneTree
const Player = preload("res://player/player.tscn")
const Session = preload("res://core/session.gd")
const Model = preload("res://core/project.gd")
const Paths = preload("res://core/paths.gd")


func _initialize():
	call_deferred("run")


func run():
	var p = Player.instantiate()
	p.session = Session.new(Model.fresh())
	root.add_child(p)
	p.load_path(Paths.examples().path_join("14-live-quiz/project.oes.json"))
	var board = p.feeds[0].stage.nodes.scoreboard
	var phases = []
	for tick in 180:
		await create_timer(.13).timeout
		if board.snapshot.is_empty():
			continue
		var phase = board.snapshot.phase
		if phase == "lobby" and board.qr_texture == null:
			continue
		if phase not in phases:
			print("BOARD ", phase)
			phases.append(phase)
		if phase == "standings":
			assert(board.snapshot.leaders[0].name == "Gallery visitor")
			await RenderingServer.frame_post_draw
			var im = p.feeds[0].get_viewport().get_texture().get_image()
			var range_ = 0.0
			for y in range(0, im.get_height(), 9):
				for x in range(0, im.get_width(), 7):
					range_ = maxf(range_, im.get_pixel(x, y).g)
			if range_ > .5 and "lobby" in phases and "open" in phases and "reveal" in phases:
				print("PASS native contest layer and rendered scoreboard")
				quit(0)
				return
			quit(1)
			return
	quit(1)
