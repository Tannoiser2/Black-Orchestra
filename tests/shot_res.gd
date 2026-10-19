extends SceneTree
var main
var n := 0
func shot(name: String, frames: int = 10) -> void:
	for k in range(frames):
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/shres/%02d_%s.png" % [n, name])
	n += 1

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shres")
	root.size = Vector2i(1920, 1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.show_setup()
	main._toggle(19)
	main._toggle(17)
	main.variants.mod_or = true
	await shot("setup")
	var g := BOGame.new()
	g.new_game([19, 17, 21], 1, {"mod_or": true, "mod_kk": true, "mod_ck": true}, 31)
	g.s.stage = 3
	for st in [1, 2]:
		g.s.decks[st] = []
	g.kopkow_move_to("STAZIONE")
	g.s.orr.tok["GESTAPO"] = "A"
	g.s.orr.sup.A = 1
	g.s.orr.act.A = 0
	g.s.orr.tok["NORIMBERGA"] = "V"
	g.s.orr.tok["ZEUGHAUS"] = "R"
	g.s.orr.act.R = 9
	g.s.ck.circle = [{"a": 2, "used": false}, {"a": 7, "used": true}]
	g.P(0).space = "GESTAPO"
	g.P(0).mot = 2
	g.P(0).items = ["PROVE", "ARMI"]
	g.P(0).dossier = ["r04", "c03", "plot_A"]
	g.s.board_items["GESTAPO"][0].rev = true
	g.s.current = "x00"
	main._launch(g)
	var gv = main.screen.get_child(0)
	await shot("game", 40)
	g.s.orr.done = [3, 5]
	g.s.orr.prove = 1
	g.s.kk.pos = "GESTAPO"
	g.s.kk.edisc = [0, 4, 7]
	for k in ["or", "kk", "ck"]:
		gv._show_exp_panel(k)
		await shot("plancia_" + k, 10)
		for c in gv.modal_layer.get_children():
			c.queue_free()
	quit()
