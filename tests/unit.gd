extends SceneTree
## Test mirati di regole.
class FixedBot extends BOBotChooser:
	var plan: Array = []
	func choose(_p, prompt, options, _e = {}):
		if plan.size() > 0:
			return plan.pop_front()
		return 0
	func choose_action(_p, actions):
		for a in actions:
			if a.id == "plot":
				return a
		for a in actions:
			if a.id == "end":
				return a
		return actions[0]

var fails := 0
func check(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)

func _init() -> void:
	# 1. vittoria: complotto A con Hitler nella stessa casella, MS 2, molti dadi
	var won := 0
	for seed in range(40):
		var g := BOGame.new()
		var bot := FixedBot.new(seed)
		bot.plan = [1, 1]
		g.ch = bot
		g.new_game([6, 0], 0, {}, seed + 1)
		g.P(0).mot = 4
		g.P(0).susp = 0
		g.P(0).space = "CANCELLERIA"
		g.s.leaders.HITLER = "CANCELLERIA"
		g.P(0).dossier = ["plot_A"]
		g.P(0).items = ["ARMI", "CRED"]
		g.new_turn_flags()
		await g.attempt_plot(0, 0)
		if g.s.won:
			won += 1
	print("vittorie su 40 tentativi (3-4 dadi vs MS 2): ", won)
	check(won > 5 and won < 40, "il complotto A può riuscire")
	# 2. complotto scoperto -> arresto, Hitler in Cancelleria
	var g2 := BOGame.new()
	g2.ch = FixedBot.new(1)
	g2.new_game([0, 6], 2, {}, 5)
	g2.P(0).mot = 4
	g2.P(0).susp = 3
	g2.P(0).space = "MONACO"
	g2.s.leaders.HITLER = "MONACO"
	g2.P(0).dossier = ["plot_E"]
	g2.new_turn_flags()
	var arrested := false
	for k in range(30):
		g2.P(0).prison = false
		g2.P(0).space = "MONACO"
		g2.P(0).susp = 3
		g2.P(0).mot = 4
		g2.s.leaders.HITLER = "MONACO"
		g2.P(0).dossier = ["plot_E"]
		await g2.attempt_plot(0, 0)
		if g2.P(0).prison:
			arrested = true
			break
	check(arrested and g2.s.leaders.HITLER == "CANCELLERIA", "complotto scoperto: arresto e Hitler alla Cancelleria")
	# 3. evento importante ignorato se è visibile l'evento chiave
	var g3 := BOGame.new()
	g3.ch = FixedBot.new(2)
	g3.new_game([0, 6], 1, {}, 9)
	g3.new_turn_flags()
	g3.s.decks[3] = ["e17_07", "e17_03", "e17_05"]
	g3.s.decks[1] = []
	g3.s.decks[2] = []
	await g3.draw_event()
	check(g3.s.current == "e17_07" and g3.s.stage == 3, "evento chiave pescato e stadio 3")
	await g3.draw_event()
	check(g3.s.key == "e17_07" and g3.s.current == "e17_05", "evento importante ignorato, pescato il successivo")
	# 4. stadio 7: ricollocazione
	var g4 := BOGame.new()
	g4.ch = FixedBot.new(3)
	g4.new_game([0, 6], 1, {}, 11)
	g4.new_turn_flags()
	g4.s.stage = 6
	g4.P(0).space = "SMOLENSK"
	g4.s.leaders.HITLER = "WOLFSSCHANZE"
	for st in range(1, 7):
		g4.s.decks[st] = []
	g4.s.decks[7] = ["e18_11"]
	await g4.draw_event()
	check(g4.s.stage == 7 and not BOData.SPACES[g4.P(0).space].no7 and not BOData.SPACES[g4.hitler()].no7, "stadio 7: tutti spostati fuori dalle caselle (7) – ora %s / Hitler %s" % [g4.P(0).space, g4.hitler()])
	# 5. mazzi esauriti -> sconfitta
	await g4.draw_event()
	check(g4.s.over and not g4.s.won, "nessuna carta evento: sconfitta")
	# 6. raid arresta a Estremo, tutti in prigione = sconfitta
	var g5 := BOGame.new()
	g5.ch = FixedBot.new(4)
	g5.new_game([0, 6], 1, {}, 12)
	g5.new_turn_flags()
	g5.P(0).susp = 3
	g5.P(1).susp = 3
	await g5.gestapo_raid()
	check(g5.s.over and not g5.s.won, "raid con entrambi a Estremo: sconfitta")
	# 7. save/load
	var g6 := BOGame.new()
	g6.ch = FixedBot.new(5)
	g6.new_game([3, 9], 1, {}, 13)
	var txt := g6.save_text()
	var g7 := BOGame.new()
	check(g7.load_text(txt) and g7.s.decks[1].size() == g6.s.decks[1].size() and g7.P(1).cid == 9, "salvataggio e caricamento")
	# 8. MS non scende sotto il valore di partenza né sale oltre 7
	g6.add_ms(-5)
	var lo: int = g6.s.ms
	g6.add_ms(20)
	check(lo == 3 and g6.s.ms == 7, "limiti del Supporto Militare")
	# 9. Berlino tutta collegata, Stazione unico accesso
	var nb := g6.neighbors("CANCELLERIA")
	check("ZEUGHAUS" in nb and "STAZIONE" in nb and not ("HANNOVER" in nb), "collegamenti di Berlino")
	print("FALLITI: ", fails)
	quit()
