extends SceneTree
## Copertura: conta i messaggi chiave del log su molte partite casuali.
func _init() -> void:
	var n := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 200
	var counts := {}
	var heroes := {}
	for g in range(n):
		var game := BOGame.new()
		var bot := BOBotChooser.new(g + 99)
		game.ch = bot
		var ids: Array = [g % 17, (g * 7 + 3) % 17]
		if ids[0] == ids[1]:
			ids[1] = (ids[1] + 1) % 17
		game.new_game(ids, g % 3, {}, g + 5000)
		# metà delle partite: motivazione alta per esercitare complotti e capacità
		if g % 2 == 0:
			for p in game.s.players:
				p.mot = 3
		game.logged.connect(func(t: String):
			for key in ["tenta il complotto", "SCOPERTO", "non vengono scoperti", "VITTORIA", "carta interrogatorio", "sceglie:", "prova a resistere", "gioca ", "Capacità", "Kordt riordina", "Oster aggiunge", "Freytag", "Dohnanyi", "Canaris", "Tresckow", "Goerdeler", "Scholl", "Stauffenberg", "Rallentare", "Reazione Rapida", "Sotto Copertura", "Informatore", "Comunicato", "Niente di Nuovo", "Dissenso è pieno", "RAID", "rilasciato", "consegna", "Inizia lo STADIO 7", "Sorveglianza", "Difettoso", "bloccata", "Zittita"]:
				if key in t:
					counts[key] = counts.get(key, 0) + 1
			if t.begins_with("Evento: "):
				counts["ev:" + t] = counts.get("ev:" + t, 0) + 1
			if " sceglie: " in t:
				counts["int:" + t.split(" sceglie: ")[1]] = counts.get("int:" + t.split(" sceglie: ")[1], 0) + 1
		)
		await game.run()
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("%5d  %s" % [counts[k], k])
	quit()
