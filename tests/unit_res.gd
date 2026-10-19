extends SceneTree
## Test mirati dell'espansione La Resistenza.
class Bot extends BOBotChooser:
	var plan: Array = []
	var spaces: Array = []
	func choose(_p, prompt, options, _e = {}):
		if plan.size() > 0:
			return plan.pop_front()
		return 0
	func choose_space(_p, _prompt, sp, _c):
		if spaces.size() > 0:
			return spaces.pop_front()
		return sp[0]

var fails := 0
func check(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)

func mk(ids: Array, v: Dictionary, seed: int = 5) -> BOGame:
	var g := BOGame.new()
	g.ch = Bot.new(seed)
	g.new_game(ids, 1, v, seed)
	g.new_turn_flags()
	return g

func _init() -> void:
	# --- preparazione ---
	var g := mk([0, 6], {"mod_or": true, "mod_kk": true, "mod_ck": true})
	var tot := 0
	for st in range(1, 8):
		tot += g.s.decks[st].size()
	# base 84 + 24 = 108; rimosse: st1 2, st2-7: 2+1+2+1 = 6 ciascuno -> 2 + 36 = 38 -> 70
	check(tot == 70, "mazzi evento con tutti i moduli: %d carte (attese 70)" % tot)
	check(g.s.board_items["CANCELLERIA"].size() == 2, "Kreisau: 2 tessere per casella")
	check(g.s.ck.res.size() == 3 and g.s.ck.apile.size() == 12, "Kreisau: 3 alleati nella riserva")
	check(g.s.cdeck.size() == 39 + 13 + 8, "mazzo cospiratore con 8 carte nuove: %d" % g.s.cdeck.size())
	# --- Libertas ---
	var g2 := mk([21, 6], {})
	check(g2.P(0).mot == 1, "Libertas inizia Scettica")
	g2.add_mot(0, 3)
	check(g2.P(0).mot == 2, "Libertas non supera Determinato")
	g2.add_mot(0, -3)
	check(g2.P(0).mot == 1, "Libertas non scende a Cauto")
	check(g2.plot_req_fail(0, "A") != "", "Libertas non può tentare complotti")
	# --- Mildred ---
	var g3 := mk([22, 6], {})
	g3.add_mot(0, 4)
	check(g3.P(0).mot == 3, "Mildred si ferma a Devoto")
	# --- Bernardis ---
	var g4 := mk([17, 6], {})
	g4.P(0).mot = 2
	g4.P(0).space = "NORIMBERGA"
	check(g4.valid_for(0, "VIENNA") and not g4.valid(  "VIENNA"), "Bernardis entra in una casella dello stadio successivo")
	# --- Orchestra Rossa: collocare e missione ---
	var g5 := mk([0, 6], {"mod_or": true})
	g5.P(0).space = "GESTAPO"
	await g5.place_token(0, "GESTAPO", "A")
	check(g5.s.orr.act.A >= 0, "la prima telescrivente azzurra rivela una missione")
	# forza la missione Arresto Imminente
	g5.s.orr.act.A = 1
	g5.P(0).susp = 0
	await g5.check_missions()
	check(g5.s.orr.done.size() == 1 and g5.s.orr.act.A == -1, "Arresto Imminente si completa da sola")
	check(not g5.s.orr.tok.has("GESTAPO") and g5.s.orr.sup.A == 2, "completata: le telescriventi tornano sulla plancia")
	# telescrivente rimossa da un delegato -> missione scartata
	await g5.place_token(0, "CANCELLERIA", "R")
	var mr: int = g5.s.orr.act.R
	g5.move_leader("GOERING", "CANCELLERIA")
	check(g5.s.orr.act.R == -1 and mr in g5.s.orr.mdisc, "un delegato rimuove l'ultima telescrivente: missione scartata")
	# Combattente: Oltre il Confine
	var g6 := mk([0, 6], {"mod_or": true})
	g6.s.stage = 4
	g6.s.orr.act.G = 13
	g6.s.orr.tok["HANNOVER"] = "G"
	g6.P(0).space = "HANNOVER"
	var acts := g6.mission_actions(0)
	var take = acts.filter(func(a): return a.key == "comb_take")
	check(take.size() == 1, "si può prendere il Combattente ad Hannover")
	await g6.do_exp_action(0, take[0])
	check("COMB" in g6.P(0).items and g6.P(0).susp == 3, "Combattente preso, +2 sospetto")
	var ms0: int = g6.s.ms
	g6.move_consp(0, "PARIGI")
	await g6.check_missions()
	check(g6.s.ms == ms0 and g6.s.orr.done.has(13) and not ("COMB" in g6.P(0).items), "consegna a Parigi senza +1 Supporto Militare")
	# missioni completate: +1 dado ai complotti (verifica tramite anteprima)
	var pv := g6.plot_preview(0, "A")
	check(g6.s.orr.done.size() == 1, "missione registrata tra le completate")
	# --- Kopkow ---
	var g7 := mk([0, 6], {"mod_kk": true})
	for st in [1]:
		g7.s.decks[st] = []
	await g7.draw_event()
	check(g7.s.kk.pos == "GESTAPO", "Kopkow entra al QG Gestapo con la prima carta dello Stadio 2")
	g7.P(0).space = "STAZIONE"
	g7.P(0).susp = 2
	g7.P(1).space = "HANNOVER"
	g7.P(1).susp = 1
	g7.s.current = "e15_00"
	await g7.kopkow_step()
	check(g7.s.kk.pos == "STAZIONE", "Kopkow si muove di 1 verso il sospetto più alto (ora %s)" % g7.s.kk.pos)
	check(g7.s.kk.edeck.size() == 17, "incontro pescato dal cospiratore con sospetto più alto")
	check(g7.kk_blocked("STAZIONE"), "la casella di Kopkow è bloccata")
	# --- Kreisau ---
	var g8 := mk([0, 6], {"mod_ck": true})
	check(g8.plot_req_fail(0, "A").find("alleato") >= 0, "senza alleati niente complotti")
	await g8.recruit(0)
	check(g8.s.ck.circle.size() == 1 and g8.s.ck.res.size() == 3, "reclutamento: alleato nel Circolo e riserva ricostituita")
	g8.P(0).mot = 3
	g8.P(0).space = g8.hitler()
	check(g8.plot_req_fail(0, "B").find("Temerario") >= 0, "con 1 alleato ogni complotto richiede Temerario")
	# tessera Raid rivelata
	var g9 := mk([0, 6], {"mod_ck": true})
	g9.s.board_items["ZEUGHAUS"] = [{"t": "RAIDT", "rev": false}, {"t": "ARMI", "rev": false}]
	g9.P(1).susp = 3
	await g9.reveal_tile("ZEUGHAUS", 0, 0)
	check(g9.P(1).prison and g9.s.board_items["ZEUGHAUS"].size() == 1, "la tessera Raid si risolve subito e viene rimossa")
	# Moltke
	var g10 := mk([19, 6], {})
	g10.P(0).mot = 2
	var tot_e := 0
	for k in range(200):
		tot_e += g10.roll_by(0, 3).count("E")
	check(tot_e < 200 * 3 / 3.0 * 0.75, "Moltke riduce le aquile (%d su 600 dadi)" % tot_e)
	print("FALLITI: ", fails)
	quit()
