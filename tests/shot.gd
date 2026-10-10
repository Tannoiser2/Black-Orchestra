extends SceneTree
var main
var n := 0
func shot(name: String) -> void:
	for k in range(6):
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/shots/%02d_%s.png" % [n, name])
	n += 1

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	root.size = Vector2i(1920, 1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await shot("menu")
	main.show_setup()
	main._toggle(6)
	main._toggle(7)
	await shot("setup")
	main._start_new()
	await shot("game_start")
	var gv = main.screen.get_child(0)
	# gioca qualche azione automaticamente
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for step in range(60):
		await process_frame
		var w: String = gv._waiting
		if w == "action":
			var acts: Array = gv._cur_actions
			var pick = acts[rng.randi_range(0, acts.size() - 1)]
			if step < 3:
				for a in acts:
					if a.id == "move":
						pick = a
			gv.answered.emit(pick)
		elif w == "choose":
			if gv.overlay:
				await shot("modal_%d" % step)
			gv.answered.emit(0)
		elif w == "space":
			await shot("space_%d" % step)
			gv.answered.emit(gv.board.highlights[0])
		elif w == "notify":
			if step % 5 == 0:
				await shot("notify_%d" % step)
			gv.answered.emit(null)
		if step == 30:
			await shot("mid")
	await shot("after")
	quit()
