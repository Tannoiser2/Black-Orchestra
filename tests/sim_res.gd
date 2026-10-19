extends SceneTree
## Simulazione con l'espansione La Resistenza: godot --headless -s res://tests/sim_res.gd -- N
func _init() -> void:
	var n := 150
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var wins := 0
	var reasons := {}
	var counts := {}
	for g in range(n):
		var game := BOGame.new()
		game.ch = BOBotChooser.new(g + 11)
		var r := RandomNumberGenerator.new()
		r.seed = g * 17 + 3
		var ids: Array = []
		var np := 2 + g % 4
		while ids.size() < np:
			var c := r.randi_range(0, 22)
			if not (c in ids):
				ids.append(c)
		var v := {"mod_or": g % 2 == 0 or g % 7 == 0, "mod_kk": g % 3 != 1, "mod_ck": g % 4 < 2}
		game.new_game(ids, g % 3, v, g + 77)
		if g % 2 == 0:
			for p in game.s.players:
				p.mot = clampi(3, game.mot_floor(game.s.players.find(p)), game.mot_cap(game.s.players.find(p)))
		game.logged.connect(func(t: String):
			for key in ["MISSIONE COMPLETATA", "Nuova missione", "Incontro con Horst", "entra nel Circolo", "Alleato usato", "Horst Kopkow si sposta", "colloca", "scartata (", "tessera Raid", "Moltke", "Erika", "Mildred", "Libertas", "von Oven", "Poelchau", "nascondiglio", "Combattente", "SCONFITTA", "VITTORIA"]:
				if key in t:
					counts[key] = counts.get(key, 0) + 1
		)
		await game.run()
		if not game.s.over:
			print("NON TERMINATA ", g)
		if game.s.won:
			wins += 1
		var key: String = game.s.reason.substr(0, 45)
		reasons[key] = reasons.get(key, 0) + 1
		var g2 := BOGame.new()
		if not g2.load_text(game.save_text()):
			print("ERRORE caricamento")
	print("Partite: %d  vittorie: %d" % [n, wins])
	for k in reasons:
		print("  ", reasons[k], "  ", k)
	var ks := counts.keys()
	ks.sort()
	for k in ks:
		print("%6d  %s" % [counts[k], k])
	quit()
