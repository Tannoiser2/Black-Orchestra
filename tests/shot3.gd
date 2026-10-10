extends SceneTree
var main
var n := 0
func shot(name: String, frames: int = 8) -> void:
	for k in range(frames):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/shots3/%02d_%s.png" % [n, name])
	n += 1

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shots3")
	root.size = Vector2i(1920, 1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_setup()
	main._set_n(4)
	main._random_pick()
	await shot("setup4")
	var g := BOGame.new()
	g.new_game([6, 15, 10, 3, 0], 1, {}, 77)
	g.P(0).mot = 4
	g.P(1).mot = 1
	g.P(0).space = "CANCELLERIA"
	g.s.leaders.HITLER = "CANCELLERIA"
	g.P(0).dossier = ["plot_B", "c04", "plot_H"]
	g.P(0).items = ["ESPL", "CRED"]
	g.P(2).space = "CANCELLERIA"
	g.P(2).items = ["ESPL"]
	g.P(3).space = "ZEUGHAUS"
	g.P(1).dossier = ["c00", "plot_F", "c05"]
	g.s.board_items["CANCELLERIA"].rev = true
	g.s.current = "e15_00"
	g.s.key = "e15_09"
	g.P(3).items = ["ARMI", "MAPPA", "VELENO"]
	g.P(3).mot = 2
	g.P(3).dossier = ["c01", "c02", "plot_A", "c05"]
	main._launch(g)
	var gv = main.screen.get_child(0)
	await shot("five_plot", 30)
	# apri dettaglio carta complotto
	gv._card_clicked(0, 0)
	await shot("plot_zoom")
	for c in gv.modal_layer.get_children():
		if c != gv.overlay:
			c.queue_free()
	# movimento: scegli azione move verso Stazione via click
	for a in gv._cur_actions:
		if a.id == "move":
			gv._pending_space = "SPORTPALAST"
			gv.answered.emit(a)
			break
	await shot("moving", 6)
	await shot("moved", 30)
	gv._focus = 2
	gv._refresh()
	await shot("focus2")
	quit()
