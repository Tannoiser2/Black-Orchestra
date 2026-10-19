extends SceneTree
## Partita guidata dall'interfaccia con tutti i moduli: scelte casuali, cerca errori di runtime.
var main
func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var rng := RandomNumberGenerator.new()
	for gnum in range(3):
		rng.seed = 100 + gnum
		var g := BOGame.new()
		var ids: Array = [[19, 20, 21], [17, 18], [22, 6, 3, 0]][gnum]
		g.new_game(ids, 1, {"mod_or": true, "mod_kk": true, "mod_ck": true}, 500 + gnum)
		for p in g.s.players:
			p.mot = clampi(3, g.mot_floor(g.s.players.find(p)), g.mot_cap(g.s.players.find(p)))
		main._launch(g)
		var gv = main.screen.get_child(0)
		gv._auto_events = true
		var steps := 0
		while not g.s.over and steps < 1500:
			steps += 1
			await process_frame
			var w: String = gv._waiting
			if w == "action":
				var acts: Array = gv._cur_actions
				var pick = acts[rng.randi_range(0, acts.size() - 1)]
				if pick.id == "end" and rng.randf() < 0.6:
					pick = acts[rng.randi_range(0, acts.size() - 1)]
				gv.answered.emit(pick)
			elif w == "choose":
				var nb: int = gv.btn_flow.get_child_count()
				gv.answered.emit(0 if rng.randf() < 0.5 else 0)
			elif w == "space":
				var hl: Array = gv.board.highlights
				gv.answered.emit(hl[rng.randi_range(0, hl.size() - 1)])
			elif w == "notify":
				gv.answered.emit(null)
		print("partita %d: turni %d, fine=%s %s" % [gnum, g.s.turn_no, g.s.over, g.s.reason])
	quit()
