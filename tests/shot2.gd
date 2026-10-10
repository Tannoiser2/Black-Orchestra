extends SceneTree
var main
var n := 0
func shot(name: String) -> void:
	for k in range(8):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/shots2/%02d_%s.png" % [n, name])
	n += 1

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shots2")
	root.size = Vector2i(1920, 1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var g := BOGame.new()
	g.new_game([6, 15], 1, {}, 77)
	g.P(0).mot = 4
	g.P(0).susp = 0
	g.P(0).space = "CANCELLERIA"
	g.s.leaders.HITLER = "CANCELLERIA"
	g.P(0).dossier = ["plot_B", "c04", "c20", "c34"]
	g.P(0).items = ["ARMI", "CRED", "ESPL"]
	g.P(1).prison = true
	g.P(1).space = "PRISON"
	g.P(1).dossier = ["c00", "plot_F"]
	g.P(1).mot = 2
	main._launch(g)
	var gv = main.screen.get_child(0)
	await shot("plot_ready")
	var step := 0
	while step < 40:
		await process_frame
		var w: String = gv._waiting
		if w == "":
			continue
		step += 1
		await shot("s%d_%s" % [step, w])
		if w == "action":
			var pick = null
			for a in gv._cur_actions:
				if a.id == "plot":
					pick = a
			if pick == null:
				for a in gv._cur_actions:
					if a.id == "end":
						pick = a
			gv.answered.emit(pick)
		elif w == "choose":
			gv.answered.emit(1 if step < 4 else 0)
		elif w == "space":
			gv.answered.emit(gv.board.highlights[0])
		elif w == "notify":
			gv.answered.emit(null)
		if g.s.over:
			await shot("end")
			break
	quit()
