extends SceneTree
## Simulazione headless: godot --headless -s res://tests/sim.gd -- N

func _init() -> void:
	var n := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var wins := 0
	var reasons := {}
	var turns := 0
	for g in range(n):
		var game := BOGame.new()
		game.ch = BOBotChooser.new(g + 7)
		var ids: Array = []
		var r := RandomNumberGenerator.new()
		r.seed = g * 31 + 5
		while ids.size() < 2 + g % 4:
			var c := r.randi_range(0, 16)
			if not (c in ids):
				ids.append(c)
		game.new_game(ids, g % 3, {"urgency": g % 5 == 0, "no_docs": g % 7 == 0}, g + 1000)
		# salvataggio / caricamento a metà
		await game.run()
		if not game.s.over:
			print("PARTITA NON TERMINATA ", g)
		if game.s.won:
			wins += 1
		var key: String = game.s.reason.substr(0, 40)
		reasons[key] = reasons.get(key, 0) + 1
		turns += game.s.turn_no
		# test salvataggio
		var t := game.save_text()
		var g2 := BOGame.new()
		if not g2.load_text(t):
			print("ERRORE caricamento")
	print("Partite: %d  vittorie: %d  turni medi: %.1f" % [n, wins, float(turns) / n])
	for k in reasons:
		print("  ", reasons[k], "  ", k)
	quit()
