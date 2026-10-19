extends RefCounted
class_name BOGame
## Motore di regole di Black Orchestra (solitario / cooperativo).
## Tutto lo stato è in `s` (Dictionary serializzabile). Le scelte passano dal `ch` (chooser):
##   choose(pidx, prompt, options, extra) -> int
##   choose_space(pidx, prompt, spaces, cancel) -> String
##   choose_action(pidx, actions) -> Dictionary
##   notify(text, extra) -> void

signal changed
signal logged(text: String)
signal finished(won: bool, reason: String)
signal turn_started
signal moved(token: String, from: String, to: String)

const FACES := ["1", "2", "3", "T", "E", "T"]
const FACE_RANK := {"E": 0, "1": 1, "2": 2, "3": 3, "T": 4}
const FACE_TXT := {"1": "1", "2": "2", "3": "3", "T": "⊕", "E": "Aquila"}

var ch
var s: Dictionary = {}
var rng := RandomNumberGenerator.new()
var adj := {}
var berlin: Array = []
## Tutte le carte evento (base + espansione).
var EV := {}

func _init() -> void:
	EV = BOData.EVENTS.duplicate()
	EV.merge(BOData.XEVENTS)
	for k in BOData.SPACES:
		adj[k] = []
		if BOData.SPACES[k].stage == 0:
			berlin.append(k)
	for e in BOData.EDGES:
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])

# =====================================================================
# Preparazione
# =====================================================================
func new_game(cids: Array, diff: int, variants: Dictionary, seed_val: int = 0) -> void:
	if seed_val == 0:
		rng.randomize()
	else:
		rng.seed = seed_val
	s = {
		"stage": 1, "diff": diff, "ms_start": 2 + diff, "ms": 2 + diff,
		"decks": {}, "current": "", "key": "", "ev_discard": [], "ev_removed": [],
		"cdeck": [], "cdiscard": [], "ideck": [], "iremoved": [],
		"board_items": {}, "item_discard": [],
		"dissent": 0, "dissent_off": false,
		"leaders": BOData.LEADER_START.duplicate(),
		"players": [], "active": 0, "turn_no": 1, "turn": {},
		"faulty": -1, "surveil": -1, "blocked": [], "anzio": false,
		"hitler_moved": false, "over": false, "won": false, "reason": "",
		"dohnanyi_stage": 0, "log": [], "variants": variants, "phase": "",
		"oven_pending": [], "ev_ignored": false,
		"mods": {"or": variants.get("mod_or", false), "kk": variants.get("mod_kk", false), "ck": variants.get("mod_ck", false)},
	}
	# mazzi evento
	for st in range(1, 8):
		var d: Array = []
		for id in EV:
			if EV[id].stage == st:
				var mr: String = EV[id].get("mod_req", "")
				if mr == "" or s.mods[mr]:
					d.append(id)
		shuffle(d)
		var remove_n := 3 if variants.get("urgency", false) else 2
		if st >= 2:
			remove_n += (1 if s.mods.or else 0) + (2 if s.mods.kk else 0) + (1 if s.mods.ck else 0)
		if st == 7 and variants.get("no_docs", false):
			d.erase("e18_05")
			s.ev_removed.append("e18_05")
			remove_n -= 1
		for k in range(remove_n):
			s.ev_removed.append(d.pop_front())
		s.decks[st] = d
	# mazzo cospiratore
	var cd: Array = []
	for k in range(BOData.CDECK_SHEET.size()):
		cd.append("c%02d" % k)
	for l in ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M"]:
		cd.append("plot_" + l)
	if variants.get("promo_plot", true):
		cd.append("plot_P")
	if s.mods.or:
		cd.append_array(BOData.RCARDS_OR)
	if s.mods.kk:
		cd.append_array(BOData.RCARDS_KK)
	shuffle(cd)
	s.cdeck = cd
	# interrogatorio
	var idk: Array = []
	for k in range(BOData.INTERR.size()):
		idk.append(k)
	shuffle(idk)
	s.ideck = idk
	# oggetti
	var items: Array = []
	for t in BOData.BASE_ITEMS:
		for k in range(3):
			items.append(t)
	if s.mods.ck:
		for k in range(15):
			items.append("ALLEATO")
		for t in ["RAIDT", "MOTMS", "QUALSIASI"]:
			for k in range(3):
				items.append(t)
	shuffle(items)
	var per_space := 2 if s.mods.ck else 1
	for sp in BOData.SPACES:
		if BOData.SPACES[sp].deliver.size() > 0:
			var stack: Array = []
			for k in range(per_space):
				stack.append({"t": items.pop_front(), "rev": false})
			s.board_items[sp] = stack
	for cid in cids:
		var cd0 = BOData.CONSPIRATORS[cid]
		s.players.append({"cid": cid, "space": "STAZIONE", "mot": cd0.get("mot_start", 0), "susp": 1, "items": [], "dossier": [], "prison": false})
	exp_setup()
	log_msg("Nuova partita – difficoltà %s, Supporto Militare di Hitler iniziale %d." % [["Facile", "Normale", "Difficile"][diff], s.ms])

func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func save_text() -> String:
	return var_to_str({"s": s, "rng": rng.state, "seed": rng.seed})

func load_text(t: String) -> bool:
	var v = str_to_var(t)
	if typeof(v) != TYPE_DICTIONARY or not v.has("s"):
		return false
	s = v.s
	for sp in s.board_items.keys():
		if typeof(s.board_items[sp]) == TYPE_DICTIONARY:
			s.board_items[sp] = [s.board_items[sp]]
	if not s.has("mods"):
		s.mods = {"or": false, "kk": false, "ck": false}
	if not s.has("oven_pending"):
		s.oven_pending = []
		s.ev_ignored = false
	if not s.has("orr"):
		exp_setup()
	rng.seed = v.get("seed", 0)
	rng.state = v.get("rng", 0)
	return true

# =====================================================================
# Utilità
# =====================================================================
func P(i: int) -> Dictionary:
	return s.players[i]

func np() -> int:
	return s.players.size()

func cname(i: int) -> String:
	return BOData.CONSPIRATORS[P(i).cid].name

func aff(i: int) -> String:
	return BOData.CONSPIRATORS[P(i).cid].aff

func free_list() -> Array:
	var r: Array = []
	for i in range(np()):
		if not P(i).prison:
			r.append(i)
	return r

func prisoners() -> Array:
	var r: Array = []
	for i in range(np()):
		if P(i).prison:
			r.append(i)
	return r

func log_msg(t: String) -> void:
	s.log.append(t)
	if s.log.size() > 400:
		s.log.pop_front()
	logged.emit(t)

func upd() -> void:
	changed.emit()

func spname(sp: String) -> String:
	if sp == "PRISON":
		return "Prigione"
	if sp == "":
		return "—"
	return BOData.SPACES[sp].name

func sp_stage(sp: String) -> int:
	return BOData.SPACES[sp].stage

func is_berlin(sp: String) -> bool:
	return sp in berlin

func neighbors(sp: String) -> Array:
	if not adj.has(sp):
		return []
	var r: Array = adj[sp].duplicate()
	if is_berlin(sp):
		for b in berlin:
			if b != sp and not (b in r):
				r.append(b)
	return r

func valid(sp: String, st: int = -1) -> bool:
	if not BOData.SPACES.has(sp):
		return false
	if st < 0:
		st = s.stage
	var d = BOData.SPACES[sp]
	if st >= 7 and d.no7:
		return false
	return d.stage <= st

## Validità di una casella per il movimento di un cospiratore (Bernardis può andare uno stadio oltre).
func valid_for(i: int, sp: String) -> bool:
	if i >= 0 and ab_on(i, "bernardis") and BOData.SPACES.has(sp):
		if s.stage >= 7:
			return true
		return BOData.SPACES[sp].stage <= s.stage + 1
	return valid(sp)

func dists_from(sp: String, only_valid: bool = false) -> Dictionary:
	var dd := {sp: 0}
	var q: Array = [sp]
	while q.size() > 0:
		var c = q.pop_front()
		for n in neighbors(c):
			if dd.has(n):
				continue
			if only_valid and not valid(n):
				continue
			dd[n] = dd[c] + 1
			q.append(n)
	return dd

func spaces_within(sp: String, n: int, who: int = -1) -> Array:
	var dd := dists_from(sp, true) if who < 0 or not ab_on(who, "bernardis") else dists_from(sp, false)
	var r: Array = []
	for k in dd:
		if k != sp and dd[k] <= n and (who < 0 or valid_for(who, k)):
			r.append(k)
	return r

func players_in(sp: String) -> Array:
	var r: Array = []
	for i in free_list():
		if P(i).space == sp:
			r.append(i)
	return r

func leaders_in(sp: String) -> Array:
	var r: Array = []
	for l in BOData.LEADERS:
		if s.leaders[l] == sp:
			r.append(l)
	return r

func hitler() -> String:
	return s.leaders.HITLER

# --- capacità e limiti ---
func ab_on(i: int, key: String) -> bool:
	var p := P(i)
	if p.prison or BOData.CONSPIRATORS[p.cid].ability != key:
		return false
	if p.mot < 2 or i in s.blocked:
		return false
	if s.anzio and aff(i) == "Abwehr":
		return false
	if i == s.active and s.turn.get("no_ability", false):
		return false
	return true

func dossier_limit(i: int) -> int:
	if P(i).mot == 0:
		return 2
	var base := 6 if np() <= 2 else (5 if np() <= 4 else 4)
	if s.mods.or:
		base += s.orr.dossier_bonus
	return base + (2 if ab_on(i, "goerdeler") else 0)

func item_limit(i: int) -> int:
	return (4 if np() <= 2 else 3) + (1 if ab_on(i, "tresckow") else 0)

func mot_floor(i: int) -> int:
	return maxi(2 if ab_on(i, "gersdorff") else 0, BOData.CONSPIRATORS[P(i).cid].get("mot_min", 0))

func mot_cap(i: int) -> int:
	return BOData.CONSPIRATORS[P(i).cid].get("mot_max", 4)

func susp_floor(i: int) -> int:
	return 1 if ab_on(i, "gersdorff") else 0

func add_mot(i: int, d: int) -> void:
	var p := P(i)
	if p.prison or d == 0:
		return
	if d > 0 and ab_on(i, "oven") and p.mot < mot_cap(i):
		for k in range(d):
			s.oven_pending.append(i)
		return
	var v := clampi(p.mot + d, 0, mot_cap(i))
	if d > 0 and ab_on(i, "scholl"):
		v = mini(v, maxi(3, p.mot))
	if d < 0:
		v = maxi(v, mini(mot_floor(i), p.mot))
	if v != p.mot:
		log_msg("%s: motivazione %s → %s." % [cname(i), BOData.MOT_NAMES[p.mot], BOData.MOT_NAMES[v]])
		p.mot = v

func set_mot(i: int, v: int) -> void:
	add_mot(i, v - P(i).mot)

func add_susp(i: int, d: int) -> void:
	var p := P(i)
	if p.prison or d == 0:
		return
	var v := clampi(p.susp + d, 0, 3)
	if d < 0:
		v = maxi(v, mini(susp_floor(i), p.susp))
	if v != p.susp:
		log_msg("%s: sospetto %s → %s." % [cname(i), BOData.SUSP_NAMES[p.susp], BOData.SUSP_NAMES[v]])
		p.susp = v

func set_susp(i: int, v: int) -> void:
	add_susp(i, v - P(i).susp)

func add_ms(d: int) -> void:
	var v := clampi(s.ms + d, s.ms_start, 7)
	if v != s.ms:
		log_msg("Supporto Militare di Hitler: %d → %d." % [s.ms, v])
		s.ms = v

func set_ms_start() -> void:
	if s.ms != s.ms_start:
		log_msg("Supporto Militare di Hitler riportato al valore di partenza (%d)." % s.ms_start)
		s.ms = s.ms_start

func dice_available() -> int:
	return 10 - s.dissent - (1 if s.faulty >= 0 else 0) - (1 if s.surveil >= 0 else 0) - s.blocked.size()

func roll(n: int) -> Array:
	var r: Array = []
	for k in range(n):
		r.append(FACES[rng.randi_range(0, 5)])
	return r

## Tiro di dadi di un cospiratore: applica Moltke (−1 aquila). Restituisce i risultati.
func roll_by(i: int, n: int) -> Array:
	var r := roll(n)
	if i >= 0 and ab_on(i, "moltke") and "E" in r:
		r.erase("E")
		log_msg("Moltke sottrae un'aquila dal tiro.")
	return r

## Tiro di un solo dado: restituisce la faccia, oppure "" se Moltke ha annullato l'aquila (nessun effetto).
func roll1_by(i: int) -> String:
	var r := roll(1)
	if r[0] == "E" and i >= 0 and ab_on(i, "moltke"):
		log_msg("Moltke annulla l'aquila: nessun effetto.")
		return ""
	return r[0]

func dice_txt(r: Array) -> String:
	var t: Array = []
	for f in r:
		t.append(FACE_TXT[f])
	return ", ".join(t)

# --- carte cospiratore ---
func ctype(cid: String) -> String:
	if cid.begins_with("plot_"):
		return "PLOT"
	if cid.begins_with("r"):
		return BOData.RCARDS[cid]
	return BOData.CDECK_SHEET[int(cid.substr(1))]

func is_plot(cid: String) -> bool:
	return cid.begins_with("plot_")

func plot_letter(cid: String) -> String:
	return cid.substr(5)

func cardname(cid: String) -> String:
	if is_plot(cid):
		return "Complotto %s – %s" % [plot_letter(cid), BOData.PLOTS[plot_letter(cid)].name]
	return BOData.CCARDS[ctype(cid)].name

func is_illegal(cid: String) -> bool:
	return not is_plot(cid) and BOData.CCARDS[ctype(cid)].illegal

## Illegale ai fini dei Raid (il nascondiglio dell'Orchestra Rossa protegge una carta).
func is_illegal_raid(cid: String) -> bool:
	if s.mods.or and s.orr.hideout == cid:
		return false
	return is_illegal(cid)

func card_trig(cid: String) -> String:
	if is_plot(cid):
		return "plot"
	return BOData.CCARDS[ctype(cid)].trig

func cimg(cid: String) -> String:
	if cid.begins_with("r"):
		return "res://assets/res/consp/%s.jpg" % cid
	return "res://assets/cards/consp/%s.jpg" % cid

func eimg(eid: String) -> String:
	if eid.begins_with("x"):
		return "res://assets/res/events/%s.jpg" % eid
	return "res://assets/cards/event/%s.jpg" % eid

func card_opts(cards: Array) -> Array:
	var r: Array = []
	for c in cards:
		r.append({"label": cardname(c), "img": cimg(c)})
	return r

func draw_ccard() -> String:
	if s.cdeck.is_empty():
		if s.cdiscard.is_empty():
			return ""
		s.cdeck = s.cdiscard.duplicate()
		s.cdiscard.clear()
		shuffle(s.cdeck)
		log_msg("Il mazzo cospiratore viene rimescolato dagli scarti.")
	return s.cdeck.pop_front()

func gain_cards(i: int, n: int) -> void:
	for k in range(n):
		var c := draw_ccard()
		if c == "":
			log_msg("Il mazzo cospiratore è esaurito.")
			return
		P(i).dossier.append(c)
		log_msg("%s aggiunge al dossier: %s." % [cname(i), cardname(c)])

func discard_card(i: int, idx: int) -> void:
	var c = P(i).dossier[idx]
	P(i).dossier.remove_at(idx)
	s.cdiscard.append(c)
	log_msg("%s scarta: %s." % [cname(i), cardname(c)])

func find_card(i: int, t: String) -> int:
	var d: Array = P(i).dossier
	for k in range(d.size()):
		if not is_plot(d[k]) and ctype(d[k]) == t:
			return k
	return -1

func discard_item(i: int, idx: int) -> void:
	var t = P(i).items[idx]
	P(i).items.remove_at(idx)
	log_msg("%s scarta l'oggetto %s." % [cname(i), BOData.ITEM_NAMES[t]])
	if t == "PROVE":
		s.orr.prove += 1
	elif t == "COMB":
		comb_lost(i)
	else:
		s.item_discard.append(t)

func item_opts(items: Array) -> Array:
	var r: Array = []
	for t in items:
		r.append({"label": BOData.ITEM_NAMES[t], "img": item_img(t)})
	return r

func item_img(t: String) -> String:
	return "res://assets/items/%s.png" % t

## Sorgenti di un oggetto di tipo t (oppure "ANY"): oggetti e Pistola Nascosta (conta come Armi).
func item_sources(i: int, t: String, others_here: bool, wild: bool = true, allow_comb: bool = false) -> Array:
	var who: Array = [i]
	if others_here:
		for j in players_in(P(i).space):
			if j != i:
				who.append(j)
	var r: Array = []
	for j in who:
		var it: Array = P(j).items
		for k in range(it.size()):
			var ok: bool = it[k] == t or (t == "ANY" and (it[k] != "COMB" or allow_comb)) or (wild and t != "ANY" and it[k] in BOData.WILD_ITEMS)
			if ok:
				var lbl: String = BOData.ITEM_NAMES[it[k]] + ("" if j == i else " (di %s)" % cname(j))
				r.append({"who": j, "kind": "item", "idx": k, "t": it[k], "label": lbl, "img": "res://assets/items/%s.png" % it[k]})
		if t == "ANY" or t == "ARMI":
			var pk := find_card(j, "PISTOLA")
			if pk >= 0:
				r.append({"who": j, "kind": "card", "idx": pk, "t": "ARMI", "label": "Pistola Nascosta (Armi)" + ("" if j == i else " (di %s)" % cname(j)), "img": cimg(P(j).dossier[pk])})
	return r

func use_source(src: Dictionary) -> void:
	if src.kind == "item":
		discard_item(src.who, src.idx)
	else:
		discard_card(src.who, src.idx)

# --- arresto / rilascio / fine partita ---
func arrest(i: int) -> void:
	var p := P(i)
	if p.prison:
		return
	if s.mods.ck and prisoners().size() > 0 and ally_ready("poelchau"):
		use_ally("poelchau")
		log_msg("Harald Poelchau impedisce l'arresto di %s." % cname(i))
		return
	if s.mods.or:
		or_on_arrest(i)
	for c in p.dossier.duplicate():
		if is_illegal(c):
			p.dossier.erase(c)
			s.cdiscard.append(c)
			log_msg("%s scarta la carta illegale %s." % [cname(i), cardname(c)])
	p.prison = true
	moved.emit("P%d" % i, p.space, "PRISON")
	p.space = "PRISON"
	log_msg("⛓ %s viene ARRESTATO e portato in prigione." % cname(i))
	if free_list().is_empty():
		lose("Tutti i cospiratori sono in prigione.")

func release(i: int, susp: int = 2) -> void:
	var p := P(i)
	if not p.prison:
		return
	p.prison = false
	p.space = "GESTAPO"
	moved.emit("P%d" % i, "PRISON", "GESTAPO")
	p.susp = susp
	log_msg("🔓 %s viene rilasciato (sospetto %s) e si trova al QG Gestapo." % [cname(i), BOData.SUSP_NAMES[susp]])
	if s.mods.or:
		or_on_release(i)

func lose(reason: String) -> void:
	if s.over:
		return
	s.over = true
	s.won = false
	s.reason = reason
	log_msg("✖ SCONFITTA: " + reason)
	upd()
	finished.emit(false, reason)

func win(reason: String) -> void:
	if s.over:
		return
	s.over = true
	s.won = true
	s.reason = reason
	log_msg("★ VITTORIA: " + reason)
	upd()
	finished.emit(true, reason)

# --- movimento ---
func move_consp(i: int, sp: String) -> void:
	var p := P(i)
	if p.prison or p.space == sp:
		return
	var from: String = p.space
	p.space = sp
	moved.emit("P%d" % i, from, sp)
	log_msg("%s si muove a %s." % [cname(i), spname(sp)])
	var en = BOData.SPACES[sp].get("enter", {})
	if en.has("susp"):
		add_susp(i, en.susp)
	if en.has("mot"):
		add_mot(i, en.mot)
	if en.has("ms"):
		if not (sp == "PARIGI" and s.mods.or and comb_carrier_for("confine") == i):
			add_ms(en.ms)
		else:
			log_msg("Oltre il Confine: il Supporto Militare non aumenta.")
	if sp == "NORIMBERGA" and s.current == "e16_03":
		set_susp(i, 0)

func move_leader(l: String, sp: String) -> void:
	if s.leaders[l] == "" or s.leaders[l] == sp:
		return
	var from: String = s.leaders[l]
	s.leaders[l] = sp
	moved.emit(l, from, sp)
	log_msg("%s si sposta a %s." % [BOData.LEADER_NAMES[l], spname(sp)])
	leader_entered(sp)

## Movimento di Hitler causato da una carta evento (può essere annullato da Rallentare Hitler).
func ev_move_hitler(sp: String) -> bool:
	if hitler() == sp:
		return false
	var used: int = await offer_bolt("RALLENTARE", "Un evento sta per muovere Hitler a %s." % spname(sp))
	if used >= 0:
		log_msg("Rallentare Hitler: Hitler resta a %s." % spname(hitler()))
		return false
	move_leader("HITLER", sp)
	s.hitler_moved = true
	return true

func ev_move_leaders(ls: Array, sp: String) -> void:
	for l in ls:
		if l == "HITLER":
			await ev_move_hitler(sp)
		else:
			move_leader(l, sp)

func all_deputies() -> Array:
	var r: Array = []
	for l in BOData.DEPUTIES:
		if s.leaders[l] != "":
			r.append(l)
	return r

## Spazi del/i cospiratore/i più vicino/i alla casella from.
func nearest_consp_spaces(from: String, exclude_same: bool) -> Array:
	var dd := dists_from(from)
	var best := 999
	var r: Array = []
	for i in free_list():
		var sp: String = P(i).space
		if exclude_same and sp == from:
			continue
		if not dd.has(sp):
			continue
		if dd[sp] < best:
			best = dd[sp]
			r = [sp]
		elif dd[sp] == best and not (sp in r):
			r.append(sp)
	return r

func ev_move_nearest(l: String) -> String:
	var from: String = s.leaders[l]
	if from == "":
		return ""
	var c := nearest_consp_spaces(from, true)
	if c.is_empty():
		log_msg("%s non ha cospiratori da raggiungere." % BOData.LEADER_NAMES[l])
		return ""
	var dest: String = c[0]
	if c.size() > 1:
		dest = await ch.choose_space(s.active, "Scegli la casella in cui muovere %s (cospiratori più vicini)" % BOData.LEADER_NAMES[l], c, false)
	if l == "HITLER":
		var moved = await ev_move_hitler(dest)
		return dest if moved else ""
	move_leader(l, dest)
	return dest

func nearest_valid(from: String, st: int, avoid_no7: bool) -> Array:
	var dd := dists_from(from)
	var best := 999
	var r: Array = []
	for sp in dd:
		if not valid(sp, st):
			continue
		if avoid_no7 and BOData.SPACES[sp].no7:
			continue
		if dd[sp] < best:
			best = dd[sp]
			r = [sp]
		elif dd[sp] == best:
			r.append(sp)
	return r

## Sposta tutti (Hitler, delegati, cospiratori) dalle caselle "no stadio 7" alla casella valida più vicina.
func relocate_no7(st: int, by_event: bool = false) -> void:
	for l in BOData.LEADERS:
		var sp: String = s.leaders[l]
		if sp != "" and BOData.SPACES[sp].no7:
			var c := nearest_valid(sp, st, true)
			var dest: String = c[0]
			if c.size() > 1:
				dest = await ch.choose_space(s.active, "Scegli dove spostare %s" % BOData.LEADER_NAMES[l], c, false)
			if l == "HITLER" and by_event:
				await ev_move_hitler(dest)
			else:
				move_leader(l, dest)
	for i in free_list():
		var sp: String = P(i).space
		if st >= 7 and ab_on(i, "bernardis"):
			continue
		if BOData.SPACES[sp].no7:
			var c := nearest_valid(sp, st, true)
			var dest: String = c[0]
			if c.size() > 1:
				dest = await ch.choose_space(i, "Scegli dove spostare %s" % cname(i), c, false)
			move_consp(i, dest)

# =====================================================================
# Limiti
# =====================================================================
func enforce_limits() -> void:
	await resolve_oven()
	if s.mods.or:
		await check_missions()
	for i in range(np()):
		var p := P(i)
		while p.dossier.size() > dossier_limit(i) and not s.over:
			var k = await ch.choose(i, "%s supera il Limite di Dossier (%d). Scegli una carta da scartare." % [cname(i), dossier_limit(i)], card_opts(p.dossier))
			discard_card(i, k)
		while p.items.size() > item_limit(i) and not s.over:
			var k = await ch.choose(i, "%s supera il Limite di Oggetti (%d). Scegli un oggetto da scartare." % [cname(i), item_limit(i)], item_opts(p.items))
			discard_item(i, k)

# =====================================================================
# Ciclo di gioco
# =====================================================================
func run() -> void:
	while not s.over:
		await play_turn()
		if s.over:
			break
		s.active = (s.active + 1) % np()
		s.turn_no += 1
	upd()

func new_turn_flags() -> void:
	s.turn = {"actions": 3, "conspired": false, "no_ability": false, "no_conspire": false,
		"bonhoeffer": false, "extra_events": 0, "skip_events": false, "free_transfer": false}

func play_turn() -> void:
	var i: int = s.active
	new_turn_flags()
	s.phase = "start"
	log_msg("──── Turno %d: %s ────" % [s.turn_no, cname(i)])
	turn_started.emit()
	exp_turn_start(i)
	upd()
	if P(i).prison:
		s.phase = "interrogation"
		await interrogation(i)
		await enforce_limits()
		if s.over:
			return
		await draw_events_step(i)
		await kopkow_step()
		return
	# inizio turno: capacità
	if ab_on(i, "goerdeler"):
		log_msg("Goerdeler: aggiunge 3 carte cospiratore al dossier.")
		gain_cards(i, 3)
	if ab_on(i, "scholl") and not s.dissent_off and dice_available() > 0:
		log_msg("Scholl aggiunge 1 dado all'indicatore del Dissenso.")
		await add_dissent(1)
	# 1. penalità
	s.phase = "penalties"
	await penalties(i)
	if ab_on(i, "stauffenberg"):
		s.turn.actions += 1
		log_msg("Stauffenberg: 1 azione aggiuntiva.")
	if s.mods.kk and s.kk.favore == i:
		s.kk.favore = -1
		s.turn.actions = mini(s.turn.actions, 2)
		s.turn.no_conspire = true
		log_msg("Restituire il Favore: %s ha solo 2 azioni e non può cospirare." % cname(i))
	await enforce_limits()
	if s.over:
		return
	# 2. azioni
	s.phase = "actions"
	while s.turn.actions > 0 and not P(i).prison and not s.over:
		upd()
		var acts := available_actions(i)
		var a = await ch.choose_action(i, acts)
		if a.id == "end":
			break
		var spent = await do_action(i, a)
		if spent and a.get("cost", 1) > 0:
			s.turn.actions -= a.get("cost", 1)
		await enforce_limits()
	if s.over:
		return
	# 3. evento
	await draw_events_step(i)
	# 4. Horst Kopkow
	await kopkow_step()

func penalties(i: int) -> void:
	var sp: String = P(i).space
	var ls := leaders_in(sp)
	if ls.is_empty():
		return
	if s.mods.or and s.orr.no_pen >= 0:
		log_msg("Contromessaggio: le penalità di Hitler e dei delegati vengono ignorate.")
		return
	if ab_on(i, "beck") or ab_on(i, "helldorf"):
		log_msg("%s ignora le penalità di Hitler e dei delegati." % cname(i))
		return
	for l in ls:
		log_msg("Penalità di %s: %s." % [BOData.LEADER_NAMES[l], BOData.PENALTY_TEXT[l]])
		match l:
			"HITLER":
				add_mot(i, -1)
			"HESS":
				if P(i).dossier.size() > 0:
					var k = await ch.choose(i, "Penalità di Hess: scegli 1 carta da scartare.", card_opts(P(i).dossier))
					discard_card(i, k)
			"GOEBBELS":
				s.turn.no_ability = true
			"BORMANN":
				s.turn.no_conspire = true
			"HIMMLER":
				add_susp(i, 1)
			"GOERING":
				var src := item_sources(i, "ANY", false, false, true)
				if src.size() > 0:
					var k = await ch.choose(i, "Penalità di Goering: scegli 1 oggetto da scartare.", src)
					use_source(src[k])
	upd()

# =====================================================================
# Azioni
# =====================================================================
func deliver_ok(i: int) -> Array:
	var sp: String = P(i).space
	var d: Array = BOData.SPACES[sp].deliver
	if d.is_empty() or s.board_items.has(sp) or kk_blocked(sp):
		return []
	match d[3]:
		"deputy":
			var any := false
			for l in BOData.DEPUTIES:
				if s.leaders[l] == sp:
					any = true
			if not any:
				return []
		"hitler":
			if hitler() != sp:
				return []
		"stage1":
			if s.stage != 1:
				return []
		"stage2":
			if s.stage != 2:
				return []
		"Abwehr", "Civile", "Wehrmacht":
			if aff(i) != d[3]:
				return []
	return item_sources(i, d[2], false)

func act_card_playable(i: int, cid: String) -> bool:
	var t := ctype(cid)
	var sp: String = P(i).space
	match t:
		"SEGRETI":
			return sp == "ZURIGO" or sp == "STOCCOLMA"
		"ATROCITA":
			return sp == "AUSCHWITZ" or sp == "TREBLINKA"
		"ORDINI":
			return prisoners().size() > 0
		"SCORTA":
			return s.item_discard.size() > 0
		"INFO_VITALE":
			return s.cdiscard.size() > 0
		"CONTATTO":
			return contatto_spaces().size() > 0
		"ORDINI_K":
			return s.mods.kk and s.kk.pos != ""
		"PROVE_D":
			return s.mods.kk and s.kk.edisc.size() > 0
		"AIUTARE":
			return s.mods.or and tel_supply_colors().size() > 0 and token_free_spaces().size() > 0
	return true

func plot_req_fail(i: int, letter: String, bolt_ctx: bool = false) -> String:
	var r = BOData.PLOTS[letter].req
	var p := P(i)
	if p.prison:
		return "in prigione"
	if BOData.CONSPIRATORS[p.cid].get("no_plots", false):
		return "%s non può tentare complotti" % cname(i)
	if s.mods.ck and s.ck.circle.is_empty():
		return "serve almeno 1 alleato reclutato nel Circolo di Kreisau"
	var need_mot: int = r.mot
	if s.mods.ck and s.ck.circle.size() == 1:
		need_mot = 4
	if p.mot < need_mot:
		return "serve motivazione %s" % BOData.MOT_NAMES[need_mot]
	if r.get("bolt", false) and not bolt_ctx:
		return "solo subito dopo che un evento ha mosso Hitler"
	if r.has("stage_min") and s.stage < r.stage_min:
		return "solo negli stadi 6 o 7"
	var h := hitler()
	if r.same and p.space != h:
		return "devi essere nella casella di Hitler"
	var hd = BOData.SPACES[h]
	match r.get("hit", ""):
		"fort":
			if not hd.fort:
				return "Hitler deve essere in una casella fortificata"
		"notfort":
			if hd.fort:
				return "Hitler NON deve essere in una casella fortificata"
		"berlin":
			if hd.stage != 0:
				return "Hitler deve essere a Berlino"
		"s12b":
			if hd.stage > 2:
				return "Hitler deve essere in una casella 1, 2 o di Berlino"
		"s345":
			if hd.stage < 3:
				return "Hitler deve essere in una casella 3, 4 o 5"
	return ""

func ability_actions(i: int) -> Array:
	var r: Array = []
	var key: String = BOData.CONSPIRATORS[P(i).cid].ability
	if not ab_on(i, key):
		return r
	match key:
		"kordt":
			if s.decks[s.stage].size() > 0:
				r.append({"id": "ability", "key": "kordt", "label": "Capacità: riordina 3 eventi"})
		"olbricht":
			r.append({"id": "ability", "key": "olbricht_move", "label": "Capacità: muoviti di 2 caselle"})
			if free_list().size() > 1:
				r.append({"id": "ability", "key": "olbricht_other", "label": "Capacità: muovi un altro cospiratore di 1"})
		"bonhoeffer":
			if not s.turn.bonhoeffer and players_in(P(i).space).size() > 1:
				r.append({"id": "ability", "key": "bonhoeffer", "label": "Capacità: +1 motivazione agli altri qui"})
		"oster":
			r.append({"id": "ability", "key": "oster", "label": "Capacità: rivela 2 carte cospiratore"})
		"canaris":
			if P(i).items.size() > 0:
				r.append({"id": "ability", "key": "canaris", "label": "Capacità: scarta oggetto, -1 sospetto"})
		"tresckow":
			if unrevealed_idx(P(i).space) >= 0 and not kk_blocked(P(i).space):
				r.append({"id": "ability", "key": "tresckow", "label": "Capacità: raccogli oggetto coperto"})
		"schacht":
			if free_list().size() > 1 and (P(i).items.size() > 0 or P(i).dossier.size() > 0):
				r.append({"id": "ability", "key": "schacht", "label": "Capacità: cedi carta/oggetto"})
		"freytag":
			r.append({"id": "ability", "key": "freytag", "label": "Capacità: cerca complotto/illegale"})
		"libertas":
			var here := players_in(P(i).space).filter(func(j): return P(j).mot < mot_cap(j))
			if here.size() > 0:
				r.append({"id": "ability", "key": "libertas_mot", "label": "Capacità: +1 motivazione a un cospiratore qui"})
			if free_list().size() > 1 and (P(i).items.size() > 0 or P(i).dossier.size() > 0):
				r.append({"id": "ability", "key": "libertas_give", "label": "Capacità: cedi carta/oggetto (qualsiasi casella)"})
		"dohnanyi":
			if s.dohnanyi_stage != s.stage:
				for c in P(i).dossier:
					if is_illegal(c) and card_trig(c) == "act" and act_card_playable(i, c):
						r.append({"id": "ability", "key": "dohnanyi", "label": "Capacità: carta illegale raddoppiata"})
						break
	return r

func available_actions(i: int) -> Array:
	var r: Array = []
	var p := P(i)
	var sp: String = p.space
	var mv: Array = []
	for n in neighbors(sp):
		if valid_for(i, n):
			mv.append(n)
	if mv.size() > 0:
		r.append({"id": "move", "label": "Movimento", "targets": mv})
	if not kk_blocked(sp):
		if collectable_idx(sp).size() > 0:
			r.append({"id": "collect", "label": "Raccogliere un oggetto"})
		if unrevealed_idx(sp) >= 0:
			r.append({"id": "reveal", "label": "Rivelare un oggetto"})
	if deliver_ok(i).size() > 0:
		r.append({"id": "deliver", "label": "Consegnare un oggetto"})
	if s.cdeck.size() + s.cdiscard.size() > 0:
		r.append({"id": "dossier", "label": "Dossier (pesca 1 carta)"})
	if not s.turn.conspired and not s.turn.no_conspire and not kk_no_conspire() and dice_available() > 0:
		r.append({"id": "conspire", "label": "Cospirare", "cost": 0})
	if sp == "GESTAPO" and p.susp < 3 and prisoners().size() > 0 and not kk_blocked(sp):
		r.append({"id": "release", "label": "Rilasciare"})
	var others := players_in(sp)
	others.erase(i)
	if others.size() > 0:
		var any: bool = p.items.size() > 0 or p.dossier.size() > 0
		for j in others:
			if P(j).items.size() > 0 or P(j).dossier.size() > 0:
				any = true
		if any:
			r.append({"id": "transfer", "label": "Trasferire" + (" (gratuito)" if s.turn.free_transfer else ""), "cost": 0 if s.turn.free_transfer else 1})
	for k in range(p.dossier.size()):
		var c: String = p.dossier[k]
		if card_trig(c) == "act" and act_card_playable(i, c):
			r.append({"id": "card", "idx": k, "cid": c, "label": "Agire: " + cardname(c)})
		elif is_plot(c) and plot_req_fail(i, plot_letter(c)) == "":
			r.append({"id": "plot", "idx": k, "cid": c, "label": "★ TENTA: " + cardname(c)})
	r.append_array(ability_actions(i))
	r.append_array(exp_actions(i))
	# carte ⚡ giocabili in qualsiasi momento (nessun costo)
	for j in free_list():
		for k in range(P(j).dossier.size()):
			var c: String = P(j).dossier[k]
			if is_plot(c):
				continue
			var t := ctype(c)
			if t == "COMUNICATO" or (t == "NIENTE" and not s.turn.skip_events) or (t == "TRASF_NASC" and placed_tels().size() > 0):
				r.append({"id": "bolt", "pidx": j, "idx": k, "cid": c, "cost": 0, "label": "⚡ %s (%s)" % [cardname(c), cname(j)]})
	r.append({"id": "end", "label": "Fine azioni → pesca evento", "cost": 0})
	return r

## Esegue un'azione; restituisce true se l'azione è stata effettivamente svolta.
func do_action(i: int, a: Dictionary) -> bool:
	var p := P(i)
	var sp: String = p.space
	match a.id:
		"move":
			var dest = await ch.choose_space(i, "Scegli la casella in cui muoverti", a.targets, true)
			if dest == "":
				return false
			move_consp(i, dest)
		"collect":
			var idxs := collectable_idx(sp)
			var k: int = idxs[0]
			if idxs.size() > 1:
				var o: Array = []
				for x in idxs:
					o.append({"label": BOData.ITEM_NAMES[s.board_items[sp][x].t], "img": item_img(s.board_items[sp][x].t)})
				var c = await ch.choose(i, "Quale oggetto raccogli?", o, {"cancel": true})
				if c < 0:
					return false
				k = idxs[c]
			await take_tile(i, sp, k)
		"reveal":
			await reveal_tile(sp, unrevealed_idx(sp), i)
		"deliver":
			return await act_deliver(i)
		"dossier":
			gain_cards(i, 1)
		"conspire":
			return await act_conspire(i)
		"release":
			await act_release(i)
		"transfer":
			return await act_transfer(i)
		"card":
			var cid: String = p.dossier[a.idx]
			log_msg("%s gioca %s." % [cname(i), cardname(cid)])
			p.dossier.remove_at(a.idx)
			await card_effect(i, ctype(cid), 1)
			s.cdiscard.append(cid)
		"plot":
			await attempt_plot(i, a.idx)
		"ability":
			return await use_ability(i, a.key)
		"exp":
			return await do_exp_action(i, a)
		"bolt":
			var j: int = a.pidx
			var cid: String = P(j).dossier[a.idx]
			var t := ctype(cid)
			if t == "COMUNICATO":
				var deps := all_deputies()
				if deps.size() == 0:
					return false
				var chosen: Array = []
				for n in range(mini(2, deps.size())):
					var opts: Array = []
					for d in deps:
						if not (d in chosen):
							opts.append({"label": "%s (a %s)" % [BOData.LEADER_NAMES[d], spname(s.leaders[d])], "img": "res://assets/leaders/%s.png" % d})
					var rem: Array = deps.filter(func(d): return not (d in chosen))
					var k = await ch.choose(j, "Comunicato Urgente: scegli il delegato n.%d da muovere" % (n + 1), opts, {"cancel": n == 0})
					if k < 0:
						return false
					chosen.append(rem[k])
				var all_sp: Array = BOData.SPACES.keys()
				var dest = await ch.choose_space(j, "Comunicato Urgente: scegli la casella di destinazione", all_sp, true)
				if dest == "":
					return false
				P(j).dossier.remove_at(a.idx)
				s.cdiscard.append(cid)
				log_msg("%s gioca Comunicato Urgente." % cname(j))
				for d in chosen:
					move_leader(d, dest)
			elif t == "NIENTE":
				P(j).dossier.remove_at(a.idx)
				s.cdiscard.append(cid)
				s.turn.skip_events = true
				log_msg("%s gioca Niente di Nuovo: in questo turno non si pescano carte evento." % cname(j))
			elif t == "TRASF_NASC":
				var tels := placed_tels()
				var from = await ch.choose_space(j, "Trasferire il Nascondiglio: scegli la telescrivente da spostare", tels, true)
				if from == "":
					return false
				var dests := token_free_spaces()
				if dests.is_empty():
					return false
				var dest = await ch.choose_space(j, "Scegli la casella in cui spostarla", dests, true)
				if dest == "":
					return false
				P(j).dossier.remove_at(a.idx)
				s.cdiscard.append(cid)
				var col: String = s.orr.tok[from]
				s.orr.tok.erase(from)
				s.orr.tok[dest] = col
				log_msg("%s sposta la telescrivente %s da %s a %s." % [cname(j), BOData.TEL_NAMES[col], spname(from), spname(dest)])
	upd()
	return true

func act_deliver(i: int) -> bool:
	var src := deliver_ok(i)
	if src.is_empty():
		return false
	var d: Array = BOData.SPACES[P(i).space].deliver
	var k = await ch.choose(i, "Scegli l'oggetto da consegnare a %s" % spname(P(i).space), src, {"cancel": true})
	if k < 0:
		return false
	log_msg("%s consegna %s a %s." % [cname(i), src[k].label, spname(P(i).space)])
	use_source(src[k])
	if d[0] == "solo":
		add_susp(i, -d[1])
	else:
		await distribute_susp(i, d[1])
	return true

func distribute_susp(i: int, amt: int) -> void:
	for n in range(amt):
		var cand: Array = []
		for j in free_list():
			if P(j).susp > susp_floor(j):
				cand.append(j)
		if cand.is_empty():
			return
		var j: int = cand[0]
		if cand.size() > 1:
			var opts: Array = []
			for c in cand:
				opts.append("%s (sospetto %s)" % [cname(c), BOData.SUSP_NAMES[P(c).susp]])
			j = cand[await ch.choose(i, "Distribuisci -1 sospetto (%d di %d): scegli il cospiratore" % [n + 1, amt], opts)]
		add_susp(j, -1)

func add_dissent(n: int) -> void:
	for k in range(n):
		if s.dissent_off:
			return
		s.dissent += 1
		if s.dissent >= 3:
			await dissent_trigger()

func dissent_trigger() -> void:
	s.dissent = 0
	log_msg("L'indicatore del Dissenso è pieno!")
	var opts: Array = []
	var codes: Array = []
	var can_mot: Array = []
	for j in free_list():
		if P(j).mot < 4 and not (ab_on(j, "scholl") and P(j).mot >= 3):
			can_mot.append(j)
	for j in can_mot:
		opts.append("+1 motivazione a %s (%s)" % [cname(j), BOData.MOT_NAMES[P(j).mot]])
		codes.append(j)
	if s.ms > s.ms_start:
		opts.append("-1 Supporto Militare di Hitler (%d → %d)" % [s.ms, s.ms - 1])
		codes.append(-1)
	if s.current == "e21_08" and can_mot.size() > 0:
		opts.append("Rivolta del Ghetto: TUTTI i cospiratori +1 motivazione")
		codes.append(-2)
	if opts.is_empty():
		log_msg("Nessun beneficio applicabile.")
		return
	var k = await ch.choose(s.active, "Dissenso: scegli il beneficio", opts)
	var c: int = codes[k]
	if c == -1:
		add_ms(-1)
	elif c == -2:
		for j in free_list():
			add_mot(j, 1)
	else:
		add_mot(c, 1)
	upd()

func act_conspire(i: int) -> bool:
	var maxd := mini(3 + (1 if ab_on(i, "schlabrendorff") else 0), dice_available())
	maxd = mini(maxd, s.turn.actions)
	if maxd <= 0:
		return false
	var opts: Array = []
	for n in range(1, maxd + 1):
		opts.append("%d dad%s (%d azion%s)" % [n, "o" if n == 1 else "i", n, "e" if n == 1 else "i"])
	var mier: bool = s.mods.ck and ally_ready("mierendorff") and s.turn.actions >= 3 and dice_available() >= 6
	if mier:
		opts.append("6 dadi con Carlo Mierendorff (3 azioni, alleato monouso)")
	var k = await ch.choose(i, "Cospirare: quanti dadi vuoi tirare? (ogni dado costa 1 azione)", opts, {"cancel": true})
	if k < 0:
		return false
	var n: int = k + 1
	var cost: int = n
	if mier and k == opts.size() - 1:
		use_ally("mierendorff")
		n = 6
		cost = 3
	s.turn.actions -= cost
	s.turn.conspired = true
	return await conspire_roll(i, n)

## Tiro dell'azione Cospirare (anche gratuita, per le missioni).
func conspire_roll(i: int, n: int) -> bool:
	var r := roll_by(i, n)
	if s.surveil == i:
		r.append("E")
		s.surveil = -1
		log_msg("Sorveglianza Potenziata: si aggiunge un risultato aquila.")
	if s.faulty == i and "T" in r:
		r.erase("T")
		s.faulty = -1
		log_msg("Equipaggiamento Difettoso: un risultato ⊕ viene ignorato.")
	log_msg("%s cospira: %s." % [cname(i), dice_txt(r)])
	await ch.notify("%s cospira" % cname(i), {"dice": r})
	if ab_on(i, "erika") and "E" in r:
		log_msg("Erika von Tresckow ignora tutte le aquile.")
		r = r.filter(func(f): return f != "E")
	if "E" in r and s.mods.ck and ally_ready("reichwein"):
		r = await reichwein_offer(i, r)
	var eagles := r.count("E")
	var targets := r.count("T")
	var nums := 0
	for f in r:
		if f in ["1", "2", "3"]:
			nums += int(f)
	# aquile
	for e in range(eagles):
		for j in players_in(P(i).space):
			add_susp(j, 1)
	# Rete della Resistenza
	for j in free_list():
		var rk := find_card(j, "RETE")
		if rk < 0:
			continue
		if eagles > 0:
			log_msg("Rete della Resistenza di %s viene scartata (aquila)." % cname(j))
			discard_card(j, rk)
		elif targets > 0:
			add_susp(j, -targets)
	# dissenso
	if targets > 0:
		if s.dissent_off:
			log_msg("L'indicatore del Dissenso non è utilizzabile.")
		else:
			await add_dissent(targets)
	if nums > 0 and i == s.active:
		s.turn.actions += nums
		log_msg("%s ottiene %d azioni." % [cname(i), nums])
	upd()
	return true

func act_release(i: int) -> void:
	var f := roll1_by(i)
	var r: Array = [f] if f != "" else []
	if s.surveil == i:
		r.append("E")
		s.surveil = -1
	log_msg("%s tenta di far rilasciare un prigioniero: %s." % [cname(i), dice_txt(r)])
	await ch.notify("Rilasciare", {"dice": r})
	if r.is_empty():
		return
	if "E" in r:
		log_msg("Troppe domande sospette!")
		arrest(i)
		return
	add_susp(i, 1)
	var pr := prisoners()
	var j: int = pr[0]
	if pr.size() > 1:
		var opts: Array = []
		for c in pr:
			opts.append(cname(c))
		j = pr[await ch.choose(i, "Scegli il cospiratore da rilasciare", opts)]
	release(j, 2)

func act_transfer(i: int) -> bool:
	var others := players_in(P(i).space)
	others.erase(i)
	var opts: Array = []
	var codes: Array = []
	for j in others:
		for k in range(P(j).items.size()):
			opts.append({"label": "Prendi da %s: %s" % [cname(j), BOData.ITEM_NAMES[P(j).items[k]]], "img": "res://assets/items/%s.png" % P(j).items[k]})
			codes.append([j, i, "item", k])
		for k in range(P(j).dossier.size()):
			opts.append({"label": "Prendi da %s: %s" % [cname(j), cardname(P(j).dossier[k])], "img": cimg(P(j).dossier[k])})
			codes.append([j, i, "card", k])
		for k in range(P(i).items.size()):
			opts.append({"label": "Dai a %s: %s" % [cname(j), BOData.ITEM_NAMES[P(i).items[k]]], "img": "res://assets/items/%s.png" % P(i).items[k]})
			codes.append([i, j, "item", k])
		for k in range(P(i).dossier.size()):
			opts.append({"label": "Dai a %s: %s" % [cname(j), cardname(P(i).dossier[k])], "img": cimg(P(i).dossier[k])})
			codes.append([i, j, "card", k])
	if opts.is_empty():
		return false
	var k = await ch.choose(i, "Trasferire: scegli cosa passare", opts, {"cancel": true})
	if k < 0:
		return false
	move_thing(codes[k][0], codes[k][1], codes[k][2], codes[k][3])
	return true

func move_thing(from: int, to: int, kind: String, k: int) -> void:
	if kind == "item":
		var t = P(from).items[k]
		P(from).items.remove_at(k)
		P(to).items.append(t)
		log_msg("%s passa %s a %s." % [cname(from), BOData.ITEM_NAMES[t], cname(to)])
	else:
		var c = P(from).dossier[k]
		P(from).dossier.remove_at(k)
		P(to).dossier.append(c)
		log_msg("%s passa %s a %s." % [cname(from), cardname(c), cname(to)])

# =====================================================================
# Capacità
# =====================================================================
func use_ability(i: int, key: String) -> bool:
	match key:
		"kordt":
			var d: Array = s.decks[s.stage]
			var top: Array = []
			for k in range(mini(3, d.size())):
				top.append(d.pop_front())
			var order: Array = []
			while top.size() > 0:
				var opts: Array = []
				for e in top:
					opts.append({"label": EV[e].name, "img": eimg(e)})
				var k: int = 0
				if top.size() > 1:
					k = await ch.choose(i, "Kordt: scegli la carta da mettere in posizione %d dalla cima" % (order.size() + 1), opts)
				order.append(top[k])
				top.remove_at(k)
			for k in range(order.size() - 1, -1, -1):
				d.push_front(order[k])
			log_msg("Kordt riordina le prime %d carte del mazzo dello stadio %d." % [order.size(), s.stage])
		"olbricht_move":
			var t := spaces_within(P(i).space, 2, i)
			var dest = await ch.choose_space(i, "Olbricht: muoviti fino a 2 caselle", t, true)
			if dest == "":
				return false
			move_consp(i, dest)
		"olbricht_other":
			var oth := free_list()
			oth.erase(i)
			var j: int = oth[0]
			if oth.size() > 1:
				var opts: Array = []
				for c in oth:
					opts.append(cname(c))
				j = oth[await ch.choose(i, "Olbricht: scegli il cospiratore da muovere", opts)]
			var t: Array = []
			for n in neighbors(P(j).space):
				if valid(n):
					t.append(n)
			var dest = await ch.choose_space(i, "Olbricht: muovi %s di 1 casella" % cname(j), t, true)
			if dest == "":
				return false
			move_consp(j, dest)
		"bonhoeffer":
			s.turn.bonhoeffer = true
			for j in players_in(P(i).space):
				if j != i:
					add_mot(j, 1)
		"oster":
			var rev: Array = []
			for k in range(2):
				var c := draw_ccard()
				if c != "":
					rev.append(c)
			if rev.is_empty():
				return true
			var k = await ch.choose(i, "Oster: scegli la carta da aggiungere al dossier (l'altra viene scartata)", card_opts(rev))
			P(i).dossier.append(rev[k])
			log_msg("Oster aggiunge %s al dossier." % cardname(rev[k]))
			rev.remove_at(k)
			s.cdiscard.append_array(rev)
		"canaris":
			var k = await ch.choose(i, "Canaris: scegli l'oggetto da scartare", item_opts(P(i).items), {"cancel": true})
			if k < 0:
				return false
			discard_item(i, k)
			await choose_and_apply(i, "Canaris: -1 sospetto a quale cospiratore?", free_list(), func(j): add_susp(j, -1))
		"tresckow":
			var sp: String = P(i).space
			log_msg("Tresckow raccoglie un oggetto coperto a %s." % spname(sp))
			await take_tile(i, sp, unrevealed_idx(sp))
		"libertas_mot":
			var here := players_in(P(i).space).filter(func(j): return P(j).mot < mot_cap(j))
			if here.is_empty():
				return false
			await choose_and_apply(i, "Libertas: +1 motivazione a quale cospiratore?", here, func(j): add_mot(j, 1))
		"libertas_give":
			var oth := free_list()
			oth.erase(i)
			var opts: Array = []
			var codes: Array = []
			for j in oth:
				for k in range(P(i).items.size()):
					opts.append({"label": "Dai a %s: %s" % [cname(j), BOData.ITEM_NAMES[P(i).items[k]]], "img": item_img(P(i).items[k])})
					codes.append([j, "item", k])
				for k in range(P(i).dossier.size()):
					opts.append({"label": "Dai a %s: %s" % [cname(j), cardname(P(i).dossier[k])], "img": cimg(P(i).dossier[k])})
					codes.append([j, "card", k])
			var k = await ch.choose(i, "Libertas: cosa vuoi cedere?", opts, {"cancel": true})
			if k < 0:
				return false
			move_thing(i, codes[k][0], codes[k][1], codes[k][2])
		"schacht":
			var oth := free_list()
			oth.erase(i)
			var opts: Array = []
			var codes: Array = []
			for j in oth:
				for k in range(P(i).items.size()):
					opts.append("Dai a %s: %s" % [cname(j), BOData.ITEM_NAMES[P(i).items[k]]])
					codes.append([j, "item", k])
				for k in range(P(i).dossier.size()):
					opts.append({"label": "Dai a %s: %s" % [cname(j), cardname(P(i).dossier[k])], "img": cimg(P(i).dossier[k])})
					codes.append([j, "card", k])
			var k = await ch.choose(i, "Schacht: cosa vuoi cedere?", opts, {"cancel": true})
			if k < 0:
				return false
			move_thing(i, codes[k][0], codes[k][1], codes[k][2])
		"freytag":
			var revealed: Array = []
			while true:
				var c := draw_ccard()
				if c == "":
					break
				if is_plot(c) or is_illegal(c):
					P(i).dossier.append(c)
					log_msg("Freytag von Loringhoven trova: %s." % cardname(c))
					break
				revealed.append(c)
			s.cdiscard.append_array(revealed)
		"dohnanyi":
			var opts: Array = []
			var idxs: Array = []
			for k in range(P(i).dossier.size()):
				var c: String = P(i).dossier[k]
				if is_illegal(c) and card_trig(c) == "act" and act_card_playable(i, c):
					opts.append({"label": cardname(c), "img": cimg(c)})
					idxs.append(k)
			var k = await ch.choose(i, "Dohnanyi: scegli la carta illegale da risolvere con effetti raddoppiati", opts, {"cancel": true})
			if k < 0:
				return false
			s.dohnanyi_stage = s.stage
			var cid: String = P(i).dossier[idxs[k]]
			P(i).dossier.remove_at(idxs[k])
			log_msg("Dohnanyi risolve %s raddoppiandone gli effetti." % cardname(cid))
			await card_effect(i, ctype(cid), 2)
			s.cdiscard.append(cid)
	upd()
	return true

func choose_and_apply(i: int, prompt: String, cand: Array, f: Callable) -> void:
	if cand.is_empty():
		return
	var j: int = cand[0]
	if cand.size() > 1:
		var opts: Array = []
		for c in cand:
			opts.append("%s (mot. %s, sosp. %s)" % [cname(c), BOData.MOT_NAMES[P(c).mot], BOData.SUSP_NAMES[P(c).susp]])
		j = cand[await ch.choose(i, prompt, opts)]
	f.call(j)

# =====================================================================
# Carte cospiratore ➡
# =====================================================================
func card_effect(i: int, t: String, mult: int) -> void:
	for rep in range(mult):
		if s.over or P(i).prison:
			return
		match t:
			"SCORTA":
				if s.item_discard.is_empty():
					return
				var k = await ch.choose(i, "Scegli 1 oggetto dalla pila degli scarti", item_opts(s.item_discard))
				var it = s.item_discard[k]
				s.item_discard.remove_at(k)
				P(i).items.append(it)
				log_msg("%s prende %s dagli scarti." % [cname(i), BOData.ITEM_NAMES[it]])
			"VOLO":
				var t2: Array = []
				for sp in BOData.SPACES:
					if valid_for(i, sp) and sp != P(i).space:
						t2.append(sp)
				var dest = await ch.choose_space(i, "Volo Aereo: scegli una casella valida", t2, false)
				move_consp(i, dest)
			"INFO_VITALE":
				if s.cdiscard.is_empty():
					return
				var k = await ch.choose(i, "Scegli 1 carta dalla pila degli scarti", card_opts(s.cdiscard))
				var c = s.cdiscard[k]
				s.cdiscard.remove_at(k)
				P(i).dossier.append(c)
				log_msg("%s recupera %s dagli scarti." % [cname(i), cardname(c)])
			"SEDIZIONE":
				var k = await ch.choose(i, "Atti di Sedizione: scegli l'effetto", ["-1 Supporto Militare di Hitler", "Tutti i cospiratori nella tua casella +1 motivazione"])
				if k == 0:
					add_ms(-1)
				else:
					for j in players_in(P(i).space):
						add_mot(j, 1)
			"SEGRETI":
				add_ms(-1)
			"PIANIFICAZIONE":
				s.turn.actions += 2
				log_msg("%s ottiene 2 azioni aggiuntive." % cname(i))
			"COMUNICAZIONE":
				await comunicazione(i)
			"ALIBI":
				add_susp(i, -1)
			"STALLO":
				for j in free_list():
					add_susp(j, -1)
			"PIANI_VIAGGIO":
				var k = await ch.choose(i, "Piani di Viaggio Trapelati", ["Muovi Hitler fino a 3 caselle", "Muovi un cospiratore fino a 3 caselle"])
				if k == 0:
					var dest = await ch.choose_space(i, "Muovi Hitler fino a 3 caselle", spaces_within(hitler(), 3), false)
					move_leader("HITLER", dest)
				else:
					var fl := free_list()
					var j: int = fl[0]
					if fl.size() > 1:
						var o: Array = []
						for c in fl:
							o.append(cname(c))
						j = fl[await ch.choose(i, "Quale cospiratore muovere?", o)]
					var dest = await ch.choose_space(i, "Muovi %s fino a 3 caselle" % cname(j), spaces_within(P(j).space, 3), false)
					move_consp(j, dest)
			"ORDINI":
				var pr := prisoners()
				if pr.is_empty():
					return
				var j: int = pr[0]
				if pr.size() > 1:
					var o: Array = []
					for c in pr:
						o.append(cname(c))
					j = pr[await ch.choose(i, "Chi rilasciare?", o)]
				release(j, 1)
			"ESCOGITARE":
				var revealed: Array = []
				while true:
					var c := draw_ccard()
					if c == "":
						break
					if is_plot(c):
						P(i).dossier.append(c)
						log_msg("%s trova %s." % [cname(i), cardname(c)])
						break
					revealed.append(c)
				s.cdiscard.append_array(revealed)
			"STORIA":
				s.cdeck.append_array(s.cdiscard)
				s.cdiscard.clear()
				shuffle(s.cdeck)
				gain_cards(i, 1)
			"CONTATTO":
				var sps: Array = contatto_spaces()
				if sps.is_empty():
					return
				var dest = await ch.choose_space(i, "Contatto Distante: scegli la casella da cui prendere l'oggetto", sps, false)
				var idxs: Array = []
				for x in range(s.board_items[dest].size()):
					if s.board_items[dest][x].t != "ALLEATO" or not s.board_items[dest][x].rev:
						idxs.append(x)
				var k: int = idxs[0]
				if idxs.size() > 1:
					var o: Array = []
					for x in idxs:
						var tl = s.board_items[dest][x]
						o.append({"label": BOData.ITEM_NAMES[tl.t] if tl.rev else "Oggetto coperto", "img": item_img(tl.t if tl.rev else "BACK")})
					k = idxs[await ch.choose(i, "Quale oggetto prendi?", o)]
				log_msg("%s usa Contatto Distante su %s." % [cname(i), spname(dest)])
				await take_tile(i, dest, k)
			"ORDINI_K":
				var t3: Array = []
				for sp in BOData.SPACES:
					if BOData.SPACES[sp].stage <= s.stage and sp != s.kk.pos:
						t3.append(sp)
				var dest = await ch.choose_space(i, "Ordini Contraffatti: dove mandare Horst Kopkow?", t3, false)
				kopkow_move_to(dest)
			"PROVE_D":
				enc_reshuffle_bottom()
			"AIUTARE":
				var cols := tel_supply_colors()
				var o: Array = []
				for c in cols:
					o.append({"label": "Telescrivente " + BOData.TEL_NAMES[c], "img": "res://assets/res/tokens/%s.png" % BOData.TEL_IMG[c]})
				var c2: String = cols[0]
				if cols.size() > 1:
					c2 = cols[await ch.choose(i, "Aiutare la Resistenza: quale telescrivente collochi?", o)]
				var dest = await ch.choose_space(i, "Scegli la casella in cui collocarla", token_free_spaces(), false)
				await place_token(i, dest, c2)
			"COPERTURA":
				for j in players_in(P(i).space):
					add_susp(j, -1)
			"ACCELERARE":
				gain_cards(i, 3)
				add_susp(i, 1)
			"DISCORSO":
				for j in players_in(P(i).space):
					add_mot(j, 1)
			"ATROCITA":
				add_ms(-1)
				for j in free_list():
					add_mot(j, 1)
		upd()

## Prende le prossime n carte evento nell'ordine di pesca (con lo stadio d'origine).
func peek_events(n: int) -> Array:
	var r: Array = []
	for st in range(1, 8):
		var d: Array = s.decks[st]
		while d.size() > 0 and r.size() < n:
			r.append(d.pop_front())
		if r.size() >= n:
			break
	return r

func return_event_top(e: String) -> void:
	s.decks[EV[e].stage].push_front(e)

func comunicazione(i: int) -> void:
	var cards := peek_events(2)
	if cards.is_empty():
		return
	var opts: Array = []
	if cards.size() == 1:
		opts = [{"label": "Rimuovi dalla partita: " + EV[cards[0]].name, "img": eimg(cards[0])},
			{"label": "Rimettila in cima: " + EV[cards[0]].name, "img": eimg(cards[0])}]
		var k = await ch.choose(i, "Comunicazione Decifrata", opts)
		if k == 0:
			s.ev_removed.append(cards[0])
			log_msg("Evento rimosso dalla partita: %s." % EV[cards[0]].name)
		else:
			return_event_top(cards[0])
		return
	var a: String = cards[0]
	var b: String = cards[1]
	opts = [
		{"label": "Rimuovi %s, rimetti in cima %s" % [EV[a].name, EV[b].name], "img": eimg(a)},
		{"label": "Rimuovi %s, rimetti in cima %s" % [EV[b].name, EV[a].name], "img": eimg(b)},
		{"label": "Rimetti entrambe: prima %s, poi %s" % [EV[a].name, EV[b].name], "img": eimg(a)},
		{"label": "Rimetti entrambe: prima %s, poi %s" % [EV[b].name, EV[a].name], "img": eimg(b)},
	]
	var k = await ch.choose(i, "Comunicazione Decifrata: le prossime carte evento sono %s e %s" % [EV[a].name, EV[b].name], opts, {"imgs": [eimg(a), eimg(b)]})
	match k:
		0:
			s.ev_removed.append(a)
			return_event_top(b)
			log_msg("Evento rimosso dalla partita: %s." % EV[a].name)
		1:
			s.ev_removed.append(b)
			return_event_top(a)
			log_msg("Evento rimosso dalla partita: %s." % EV[b].name)
		2:
			return_event_top(b)
			return_event_top(a)
		3:
			return_event_top(a)
			return_event_top(b)

# =====================================================================
# Carte ⚡
# =====================================================================
## Offre a tutti i cospiratori liberi che possiedono una carta del tipo t di giocarla. Restituisce l'indice del giocatore o -1.
func offer_bolt(t: String, prompt: String, only: int = -1) -> int:
	var opts: Array = ["Non giocare"]
	var who: Array = [-1]
	for j in free_list():
		if only >= 0 and j != only:
			continue
		var k := find_card(j, t)
		if k >= 0:
			opts.append({"label": "%s gioca %s" % [cname(j), BOData.CCARDS[t].name], "img": cimg(P(j).dossier[k])})
			who.append(j)
	if who.size() == 1:
		return -1
	var c = await ch.choose(s.active, prompt + "\nVuoi giocare %s?" % BOData.CCARDS[t].name, opts)
	var j: int = who[c]
	if j >= 0:
		discard_card(j, find_card(j, t))
	return j

# =====================================================================
# Complotti
# =====================================================================
func attempt_plot(i: int, idx: int) -> void:
	var cid: String = P(i).dossier[idx]
	var letter := plot_letter(cid)
	var pl = BOData.PLOTS[letter]
	log_msg("★ %s tenta il complotto %s!" % [cname(i), cardname(cid)])
	s.phase = "plot"
	upd()
	var pool := 1
	var cancel_e := 0
	var sp: String = P(i).space
	if s.mods.or and s.orr.done.size() > 0:
		pool += s.orr.done.size()
		log_msg("Missioni completate dell'Orchestra Rossa: +%d dad%s." % [s.orr.done.size(), "o" if s.orr.done.size() == 1 else "i"])
	for opt in pl.opt:
		match opt[0]:
			"aff":
				if aff(i) == opt[1]:
					pool += 1
					log_msg("Affiliazione %s: +1 dado." % opt[1])
			"item", "cred", "any_item":
				var t: String = "CRED" if opt[0] == "cred" else ("ANY" if opt[0] == "any_item" else opt[1])
				var rep: bool = opt[0] == "any_item" or opt[opt.size() - 1] == true
				while true:
					var src := item_sources(i, t, true)
					if src.is_empty():
						break
					var cancels: bool = opt[0] == "cred" or opt[0] == "any_item"
					var bonus := "annulla 1 aquila" if cancels else "+1 dado"
					var opts: Array = ["Nessuno"]
					opts.append_array(src)
					var k = await ch.choose(i, "Requisito facoltativo: scartare %s per %s?" % [("un oggetto" if t == "ANY" else BOData.ITEM_NAMES[t]), bonus], opts)
					if k == 0:
						break
					use_source(src[k - 1])
					if cancels:
						cancel_e += 1
					else:
						pool += 1
					if not rep:
						break
			"all_same":
				var ok := free_list().size() == np()
				for j in range(np()):
					if P(j).space != sp:
						ok = false
				if ok:
					pool += 2
					log_msg("Tutti i cospiratori nella stessa casella: +2 dadi.")
			"hitler_in":
				if hitler() in opt[1]:
					pool += 1
					log_msg("Hitler al Ministero/Cancelleria: +1 dado.")
			"other_here":
				var n := players_in(sp).size() - 1
				if n > 0:
					pool += n
					log_msg("Altri cospiratori nella casella: +%d dad%s." % [n, "o" if n == 1 else "i"])
	# Il Momento della Verità (solo per il proprio tentativo)
	var mom: int = await offer_bolt("MOMENTO", "Riserva attuale: %d dadi." % pool, i)
	if mom >= 0:
		pool += 2
	# Beck / Helldorf
	for j in free_list():
		if P(j).space != sp:
			continue
		if ab_on(j, "beck"):
			var k = await ch.choose(j, "Beck può aggiungere 1 dado alla riserva (⚡). Usare la capacità?", ["Sì, +1 dado", "No"])
			if k == 0:
				pool += 1
		if ab_on(j, "helldorf") and is_berlin(sp):
			var k = await ch.choose(j, "Helldorf può aggiungere 2 dadi alla riserva (⚡). Usare la capacità?", ["Sì, +2 dadi", "No"])
			if k == 0:
				pool += 2
	pool = mini(pool, dice_available())
	var need: int = s.ms
	var limit: int = BOData.SUSP_EAGLES[P(i).susp]
	var mod := event_mod()
	var st_t := 0
	if s.mods.ck:
		var stt = BOData.KREISAU_STATUS[mini(s.ck.circle.size(), 5)]
		st_t = stt[0]
		mod += stt[1]
	var info := "Servono %d ⊕ (Supporto Militare). Il complotto fallisce e viene scoperto con %d o più aquile (sospetto %s)." % [need, limit, BOData.SUSP_NAMES[P(i).susp]]
	if s.mods.ck:
		info += "\nCircolo di Kreisau: " + BOData.KREISAU_STATUS[mini(s.ck.circle.size(), 5)][2]
	if mod != 0:
		info += "\nEvento attuale: %s %d aquil%s." % [("aggiunge" if mod > 0 else "ignora"), absi(mod), "a" if absi(mod) == 1 else "e"]
	if cancel_e > 0:
		info += "\nAquile annullate dai requisiti facoltativi: %d." % cancel_e
	var opts: Array = []
	for n in range(pool, 0, -1):
		opts.append("Tira %d dad%s" % [n, "o" if n == 1 else "i"])
	var k = await ch.choose(i, "Riserva finale: %d dadi.\n%s\nQuanti dadi vuoi tirare?" % [pool, info], opts)
	var n: int = pool - k
	var r := roll_by(i, n)
	if s.surveil == i:
		r.append("E")
		s.surveil = -1
		log_msg("Sorveglianza Potenziata: si aggiunge un risultato aquila.")
	if s.faulty == i and "T" in r:
		r.erase("T")
		s.faulty = -1
		log_msg("Equipaggiamento Difettoso: un risultato ⊕ viene ignorato.")
	log_msg("Tiro del complotto: %s." % dice_txt(r))
	await ch.notify("Tentativo di complotto – " + pl.name, {"dice": r, "text": info})
	var extra_t := st_t
	var ignore_e := 0
	# reazioni ⚡
	while not s.over:
		var o: Array = ["Nessuna reazione – risolvi il tiro"]
		var codes: Array = [[-1, ""]]
		for j in free_list():
			for t in ["REAZIONE", "SOTTO_COPERTURA", "INFORMATORE"]:
				if find_card(j, t) >= 0:
					if t == "INFORMATORE" and s.ms < 5:
						continue
					if t == "SOTTO_COPERTURA" and r.count("E") + mod - cancel_e - ignore_e <= 0:
						continue
					o.append({"label": "%s gioca %s" % [cname(j), BOData.CCARDS[t].name], "img": cimg(P(j).dossier[find_card(j, t)])})
					codes.append([j, t])
		if s.mods.ck and r.count("E") + mod - cancel_e - ignore_e > 0:
			for ak in ["reichwein", "rosch"]:
				if ally_ready(ak):
					o.append({"label": "Alleato: %s" % ally_def(ak).name, "img": ally_img(ak)})
					codes.append([-2, ak])
		if codes.size() == 1:
			break
		var cur := "Risultato: %s  (%+d ⊕, -%d aquile)" % [dice_txt(r), extra_t, ignore_e]
		var c = await ch.choose(i, cur + "\nVuoi giocare una carta ⚡?", o, {"dice": r})
		if codes[c][0] == -1:
			break
		if codes[c][0] == -2:
			var ak: String = codes[c][1]
			use_ally(ak)
			if ak == "rosch":
				ignore_e += 99
				log_msg("Augustin Rösch: tutte le aquile del complotto sono ignorate.")
			else:
				var ei: int = r.find("E")
				var faces := ["1", "2", "3", "T"]
				var fo: Array = []
				for f in faces:
					fo.append(FACE_TXT[f])
				var fc = await ch.choose(i, "Rosemarie Reichwein: su quale faccia giri il dado con l'aquila?", fo, {"dice": r})
				r[ei] = faces[fc]
				log_msg("Rosemarie Reichwein gira un'aquila su %s." % FACE_TXT[faces[fc]])
			continue
		var j: int = codes[c][0]
		var t: String = codes[c][1]
		discard_card(j, find_card(j, t))
		match t:
			"REAZIONE":
				var fo: Array = []
				for f in r:
					fo.append(FACE_TXT[f])
				var d = await ch.choose(j, "Reazione Rapida: quale dado ritirare?", fo, {"dice": r})
				var nf: String = roll(1)[0]
				log_msg("Reazione Rapida: %s → %s." % [FACE_TXT[r[d]], FACE_TXT[nf]])
				r[d] = nf
			"SOTTO_COPERTURA":
				ignore_e += 1
				log_msg("Sotto Copertura: 1 aquila ignorata.")
			"INFORMATORE":
				extra_t += 1
				log_msg("Informatore di Alto Rango: +1 ⊕.")
	var eagles := maxi(0, r.count("E") + mod - cancel_e - ignore_e)
	var targets := maxi(0, r.count("T") + extra_t)
	log_msg("Aquile effettive: %d (limite %d). Bersagli: %d (servono %d)." % [eagles, limit, targets, need])
	s.phase = "actions"
	if eagles >= limit:
		log_msg("✖ Il complotto fallisce e viene SCOPERTO!")
		var k2: int = P(i).dossier.find(cid)
		if k2 >= 0:
			discard_card(i, k2)
		move_leader("HITLER", "CANCELLERIA")
		for j in free_list():
			add_mot(j, -1)
		await ch.notify("Il complotto fallisce e viene scoperto!", {"dice": r, "text": "Hitler si rifugia alla Cancelleria. Tutti i cospiratori perdono 1 motivazione e %s viene arrestato." % cname(i)})
		arrest(i)
	elif targets >= need:
		await ch.notify("HITLER È STATO ASSASSINATO!", {"dice": r, "text": "%s riesce nel complotto %s." % [cname(i), pl.name]})
		win("%s ha assassinato Hitler con il complotto \"%s\"." % [cname(i), pl.name])
	else:
		log_msg("Il complotto fallisce, ma i cospiratori non vengono scoperti.")
		await ch.notify("Il complotto fallisce", {"dice": r, "text": "Non abbastanza ⊕ (%d su %d), ma nessuno è stato scoperto. La carta resta nel dossier." % [targets, need]})
	upd()

func event_mod() -> int:
	if s.current == "" or s.ev_ignored:
		return 0
	return EV[s.current].get("mod", 0)

## Dopo che un evento ha mosso Hitler: possibilità di tentare i complotti C e D.
func offer_event_plots() -> void:
	while not s.over:
		var o: Array = ["Nessun complotto"]
		var codes: Array = [[-1, -1]]
		for j in free_list():
			for k in range(P(j).dossier.size()):
				var c: String = P(j).dossier[k]
				if is_plot(c) and BOData.PLOTS[plot_letter(c)].req.get("bolt", false) and plot_req_fail(j, plot_letter(c), true) == "":
					o.append({"label": "%s tenta %s" % [cname(j), cardname(c)], "img": cimg(c)})
					codes.append([j, k])
		if codes.size() == 1:
			return
		var c = await ch.choose(s.active, "Un evento ha mosso Hitler (ora a %s). Vuoi tentare subito un complotto ⚡?" % spname(hitler()), o)
		if codes[c][0] < 0:
			return
		await attempt_plot(codes[c][0], codes[c][1])
		return

# =====================================================================
# Eventi
# =====================================================================
func draw_events_step(i: int) -> void:
	s.phase = "event"
	if not s.turn.skip_events and P(i).prison:
		var j: int = await offer_bolt("NIENTE", "Stai per pescare una carta evento.")
		if j >= 0:
			s.turn.skip_events = true
	if not s.turn.skip_events and s.mods.ck and ally_ready("haubach"):
		var k = await ch.choose(s.active, "Stai per pescare una carta evento. Vuoi usare l'alleato Theodor Haubach per non risolverla?", ["No", "Sì, usa Theodor Haubach"])
		if k == 1:
			use_ally("haubach")
			s.turn.skip_events = true
	if s.turn.skip_events:
		log_msg("Niente di Nuovo: nessuna carta evento in questo turno.")
		return
	var n: int = 1 + s.turn.extra_events
	for k in range(n):
		if s.over:
			return
		await draw_event()
		await enforce_limits()

func next_stage_deck() -> int:
	for st in range(1, 8):
		if s.decks[st].size() > 0:
			return st
	return -1

func draw_event() -> void:
	var st := next_stage_deck()
	if st < 0:
		lose("Non è possibile pescare una carta evento: la guerra prosegue senza che Hitler sia stato fermato.")
		return
	if st >= 2 and s.mods.kk and s.kk.pos == "":
		log_msg("La caccia ha inizio: Horst Kopkow arriva al QG Gestapo.")
		kopkow_move_to("GESTAPO")
	var card: String = s.decks[st].pop_front()
	await place_event(card)

func place_event(card: String) -> void:
	var ev = EV[card]
	if s.current != "":
		if EV[s.current].kind == "key":
			s.key = s.current
		else:
			s.ev_discard.append(s.current)
	s.current = ""
	if ev.stage > s.stage:
		if s.key != "":
			s.ev_discard.append(s.key)
			s.key = ""
		s.stage = ev.stage
		log_msg("═══ Inizia lo STADIO %d ═══" % s.stage)
		if s.mods.kk and s.kk.nocons_stage > 0:
			s.kk.nocons_stage = 0
			log_msg("Eccesso di Cautela: Cospirare torna disponibile.")
		if s.stage >= 7 and s.mods.or and s.orr.perm != "":
			log_msg("Stadio 7: la telescrivente permanente viene rimossa da %s." % spname(s.orr.perm))
			s.orr.perm = ""
		if s.stage == 7:
			log_msg("Stadio 7: il Reich perde i territori remoti.")
			await relocate_no7(7)
	s.current = card
	log_msg("Evento: %s (Stadio %d)." % [ev.name, ev.stage])
	upd()
	await ch.notify("Carta evento: " + ev.name, {"img": eimg(card), "event": card})
	if ev.kind == "imp" and s.key != "" and EV[s.key].stage == ev.stage:
		log_msg("L'evento chiave di questo stadio è in gioco: %s viene ignorato." % ev.name)
		s.ev_discard.append(card)
		s.current = ""
		await draw_event()
		return
	s.hitler_moved = false
	s.ev_ignored = false
	if ev.kind != "raid" and ab_on(s.active, "mildred"):
		var mk = await ch.choose(s.active, "Mildred Fish-Harnack: vuoi risolvere gli effetti di «%s» o ignorarli?" % ev.name, ["Risolvi l'evento", "Ignora gli effetti"], {"imgs": [eimg(card)]})
		if mk == 1:
			s.ev_ignored = true
			log_msg("Mildred Fish-Harnack ignora gli effetti di %s." % ev.name)
			upd()
			return
	match ev.kind:
		"raid":
			await gestapo_raid()
		"lose":
			lose("Documenti Compromettenti: la Gestapo ha trovato prove schiaccianti.")
			return
		_:
			await resolve_event(ev.fx)
	await enforce_limits()
	if s.hitler_moved and not s.over:
		await offer_event_plots()
	upd()

func remove_next(st: int, n: int) -> void:
	var d: Array = s.decks[st]
	for k in range(n):
		if d.is_empty():
			return
		s.ev_removed.append(d.pop_front())
	log_msg("Rimosse dalla partita le prossime %d carte evento dello stadio %d." % [n, st])

func single_in(sp: String) -> int:
	if sp == "":
		return -1
	var r := players_in(sp)
	return r[0] if r.size() == 1 else -1

func reveal_item(sp: String) -> void:
	var k := unrevealed_idx(sp)
	if k >= 0:
		await reveal_tile(sp, k, -1)

func all_mot(d: int) -> void:
	for j in free_list():
		add_mot(j, d)

func all_susp(d: int) -> void:
	for j in free_list():
		add_susp(j, d)

func aff_mot(a: String, d: int) -> void:
	for j in free_list():
		if aff(j) == a:
			add_mot(j, d)

func move_aff(a: String, sp: String) -> void:
	for j in free_list():
		if aff(j) == a:
			move_consp(j, sp)

func resolve_event(fx: String) -> void:
	var dep := all_deputies()
	match fx:
		"discorso_berlino":
			set_ms_start()
			await ev_move_leaders(["HITLER", "GOEBBELS"], "SPORTPALAST")
			for j in free_list():
				if is_berlin(P(j).space):
					add_susp(j, -1)
		"fritsch":
			add_ms(1)
			move_leader("GOERING", "CANCELLERIA")
		"visita_himmler1":
			var sp = await ev_move_nearest("HIMMLER")
			var j := single_in(sp)
			if j >= 0:
				var k = await ch.choose(j, "Visita di Himmler: %s può tirare 1 dado (1-3: +motivazione; aquila: +2 sospetto)." % cname(j), ["Tira il dado", "Non tirare"])
				if k == 0:
					var r := roll(1)
					await ch.notify("Visita di Himmler", {"dice": r})
					if r[0] in ["1", "2", "3"]:
						add_mot(j, int(r[0]))
					elif r[0] == "E":
						add_susp(j, 2)
		"visita_goebbels1":
			var sp = await ev_move_nearest("GOEBBELS")
			var j := single_in(sp)
			if j >= 0:
				var k = await ch.choose(j, "Visita di Goebbels: %s può portare il sospetto ad Alto per +2 motivazione." % cname(j), ["Sì", "No"])
				if k == 0:
					set_susp(j, 2)
					add_mot(j, 2)
		"anschluss":
			add_ms(1)
			await ev_move_leaders(["HITLER", "GOERING"], "MONACO")
		"assassino":
			var near := nearest_consp_spaces(hitler(), false)
			for j in free_list():
				if P(j).space in near and P(j).susp < 2:
					set_susp(j, 2)
			await ev_move_hitler("CANCELLERIA")
		"delegati_schierati":
			move_leader("BORMANN", "HANNOVER")
			move_leader("GOERING", "TANNENBERG")
			move_leader("HIMMLER", "NORIMBERGA")
		"all_susp1":
			all_susp(1)
		"raduno1", "raduno2":
			if fx == "raduno2":
				set_ms_start()
			await ev_move_hitler("NORIMBERGA")
			for d in dep:
				move_leader(d, "NORIMBERGA")
		"accordo_monaco":
			add_ms(1)
			remove_next(1, 2)
		"notte_cristalli":
			all_mot(1)
			await ev_move_hitler(BOData.LEADER_START.HITLER)
			for d in dep:
				move_leader(d, BOData.LEADER_START[d])
		"parata":
			await ev_move_hitler("ZEUGHAUS")
			move_leader("GOEBBELS", "ZEUGHAUS")
			move_leader("HESS", "ZEUGHAUS")
			for j in free_list():
				if aff(j) == "Wehrmacht" and is_berlin(P(j).space):
					add_susp(j, -1)
		"ms1":
			add_ms(1)
		"ms2":
			add_ms(2)
		"ms_m1":
			add_ms(-1)
		"ms_start":
			set_ms_start()
		"patto":
			add_ms(1)
			move_leader("BORMANN", "BERGHOF")
			move_leader("HESS", "BERGHOF")
		"riunione":
			for l in ["HIMMLER", "GOERING", "HESS"]:
				move_leader(l, "ADLERHORST")
		"propaganda":
			move_leader("BORMANN", "MONACO")
			move_leader("GOEBBELS", "MONACO")
			await reveal_item("MONACO")
		"visita_hess":
			var sp = await ev_move_nearest("HESS")
			var j := single_in(sp)
			if j >= 0 and P(j).mot > mot_floor(j):
				var k = await ch.choose(j, "Visita di Hess: %s può perdere 1 motivazione per muoversi in qualsiasi casella valida e ridurre di 1 il sospetto." % cname(j), ["Sì", "No"])
				if k == 0:
					add_mot(j, -1)
					var t: Array = []
					for x in BOData.SPACES:
						if valid(x):
							t.append(x)
					var dest = await ch.choose_space(j, "Scegli la casella", t, false)
					move_consp(j, dest)
					add_susp(j, -1)
		"all_mot1":
			all_mot(1)
		"all_mot_m1":
			all_mot(-1)
		"visita_bormann2":
			var sp = await ev_move_nearest("BORMANN")
			var j := single_in(sp)
			if j >= 0 and (P(j).dossier.size() > 0 or P(j).items.size() > 0):
				var o: Array = ["Non scartare nulla"]
				var codes: Array = [[""]]
				for k in range(P(j).dossier.size()):
					o.append({"label": "Scarta " + cardname(P(j).dossier[k]), "img": cimg(P(j).dossier[k])})
					codes.append(["card", k])
				for k in range(P(j).items.size()):
					o.append({"label": "Scarta l'oggetto " + BOData.ITEM_NAMES[P(j).items[k]], "img": "res://assets/items/%s.png" % P(j).items[k]})
					codes.append(["item", k])
				var k = await ch.choose(j, "Visita di Bormann: scarta 1 carta o 1 oggetto per -2 sospetto?", o)
				if k > 0:
					if codes[k][0] == "card":
						discard_card(j, codes[k][1])
					else:
						discard_item(j, codes[k][1])
					add_susp(j, -2)
		"cecoslovacchia":
			add_ms(1)
			await ev_move_hitler("VIENNA")
			await reveal_item("VIENNA")
		"ebrei_mirino":
			all_mot(1)
			move_leader("HIMMLER", "VARSAVIA")
			await reveal_item("VARSAVIA")
		"bombe_londra":
			add_ms(1)
			move_leader("HESS", "PRAGA")
			await reveal_item("PRAGA")
		"caduta_parigi":
			if s.ms < 5:
				log_msg("Supporto Militare portato a 5.")
				s.ms = 5
			all_mot(-1)
		"visita_hitler3":
			var sp = await ev_move_nearest("HITLER")
			var j := single_in(sp)
			if j >= 0:
				var k = await ch.choose(j, "Visita di Hitler: %s può riportare sospetto e motivazione ai livelli di partenza (Medio / Cauto)." % cname(j), ["Sì", "No"])
				if k == 0:
					set_susp(j, 1)
					set_mot(j, 0)
		"berghof3":
			await ev_move_hitler("BERGHOF")
			for l in ["HIMMLER", "GOEBBELS", "BORMANN"]:
				move_leader(l, "BERGHOF")
		"visita_goering3":
			var sp = await ev_move_nearest("GOERING")
			var j := single_in(sp)
			while j >= 0 and P(j).items.size() > 0:
				var o: Array = ["Basta così"]
				o.append_array(item_opts(P(j).items))
				var k = await ch.choose(j, "Visita di Goering: scarta oggetti per -1 sospetto ciascuno.", o)
				if k == 0:
					break
				discard_item(j, k - 1)
				add_susp(j, -1)
		"offensiva_occ":
			move_aff("Wehrmacht", "ADLERHORST")
		"assume_comando":
			add_ms(-1)
			await ev_move_hitler("WOLFSSCHANZE")
			await reveal_item("WOLFSSCHANZE")
		"visita_goebbels4":
			await ev_move_nearest("GOEBBELS")
			aff_mot("Civile", -1)
		"pearl_harbor":
			add_ms(-1)
			remove_next(4, 3)
			if s.leaders.HESS != "":
				s.leaders.HESS = ""
				log_msg("Hess viene rimosso dalla partita.")
		"conferenza_guerra":
			await ev_move_hitler("ANLAGE_SUD")
			for d in dep:
				move_leader(d, "ANLAGE_SUD")
			await reveal_item("ANLAGE_SUD")
		"visita_himmler4":
			await ev_move_nearest("HIMMLER")
			aff_mot("Wehrmacht", -1)
		"barbarossa":
			add_ms(1)
			move_leader("GOERING", "POSEN")
		"jugoslavia":
			add_ms(1)
			move_leader("HIMMLER", "PARIGI")
		"hess_lascia":
			add_ms(-2)
			if s.leaders.HESS != "":
				s.leaders.HESS = ""
				log_msg("Hess viene rimosso dalla partita.")
		"afrika":
			add_ms(1)
			move_leader("BORMANN", "PRAGA")
			move_leader("GOEBBELS", "PRAGA")
		"ostacolo_russo":
			add_ms(-1)
			remove_next(5, 2)
		"sconfitta_rommel":
			add_ms(-1)
			remove_next(5, 2)
		"offensiva_or":
			add_ms(1)
			move_aff("Wehrmacht", "BORISOV")
		"lebensraum":
			all_mot(1)
			move_leader("HIMMLER", "WASSERBURG")
			await reveal_item("WASSERBURG")
		"casablanca":
			all_mot(-1)
			for j in free_list():
				if P(j).dossier.size() > 0:
					var k = await ch.choose(j, "Conferenza di Casablanca: %s scarta 1 carta dal dossier." % cname(j), card_opts(P(j).dossier))
					discard_card(j, k)
		"visita_bormann5":
			var sp = await ev_move_nearest("BORMANN")
			var j := single_in(sp)
			if j >= 0:
				arrest(j)
		"visita_goering5":
			await ev_move_nearest("GOERING")
			aff_mot("Abwehr", -1)
		"heydrich":
			await ev_move_hitler("CANCELLERIA")
			for d in dep:
				move_leader(d, "CANCELLERIA")
			for j in free_list():
				if P(j).space == "PRAGA" and P(j).susp >= 2:
					arrest(j)
		"berghof5":
			await ev_move_hitler("BERGHOF")
			move_leader("BORMANN", "BERGHOF")
			move_leader("GOEBBELS", "BERGHOF")
		"hitler_cancelleria":
			await ev_move_hitler("CANCELLERIA")
		"visita_hitler6":
			await ev_move_nearest("HITLER")
		"fortezza":
			add_ms(1)
			remove_next(6, 2)
		"branco_lupi":
			add_ms(1)
			move_leader("BORMANN", "WOLFSSCHLUCHT")
			move_leader("GOEBBELS", "WOLFSSCHLUCHT")
		"ritirata":
			await relocate_no7(6, true)
		"kursk":
			add_ms(-1)
			await ev_move_hitler("ANLAGE_SUD")
			move_leader("BORMANN", "POSEN")
		"sicilia":
			add_ms(-1)
			await ev_move_hitler("CANCELLERIA")
			move_aff("Abwehr", "CANCELLERIA")
		"rommel_funerali":
			add_ms(-1)
			move_leader("HIMMLER", "CANCELLERIA")
		"overlord":
			set_ms_start()
			move_leader("GOEBBELS", "MINISTERO")
		"v2":
			add_ms(1)
			all_mot(1)
			move_leader("GOERING", "HANNOVER")
			move_leader("BORMANN", "BERGHOF")
		"coscrizione":
			for j in free_list():
				gain_cards(j, 2)
		"fuhrerbunker":
			all_susp(1)
			await ev_move_hitler("CANCELLERIA")
		"anzio":
			s.anzio = true
			log_msg("I cospiratori Abwehr non possono più usare la propria capacità.")
		_:
			await resolve_exp_event(fx)
	upd()

func gestapo_raid(is_tile: bool = false) -> void:
	log_msg("🚨 RAID DELLA GESTAPO!")
	if s.mods.or and s.orr.skip_raid > 0:
		s.orr.skip_raid -= 1
		log_msg("Autorizzazione di Sicurezza: questo Raid viene ignorato.")
		return
	if s.mods.ck and ally_ready("myorck"):
		var mk = await ch.choose(s.active, "Raid della Gestapo! Vuoi usare l'alleato Marion Yorck per ignorarlo?", ["No", "Sì, ignora il Raid"])
		if mk == 1:
			use_ally("myorck")
			log_msg("Marion Yorck: il Raid viene ignorato.")
			return
	if s.mods.or:
		or_on_raid()
	if s.mods.kk and s.kk.fiato.size() > 0:
		for j in s.kk.fiato:
			if not P(j).prison and P(j).susp >= 2:
				log_msg("Fiato sul Collo: %s viene arrestato." % cname(j))
				arrest(j)
		s.kk.fiato = []
		s.kk.edisc.append(16)
	for j in free_list():
		if P(j).susp >= 3:
			arrest(j)
	if s.over:
		return
	for j in free_list():
		if ab_on(j, "gisevius") or find_card(j, "NULLA_OSTA") >= 0:
			continue
		var ill: Array = []
		for c in P(j).dossier:
			if is_illegal_raid(c):
				ill.append(c)
		for c in ill:
			if P(j).susp >= 3:
				log_msg("%s è a sospetto Estremo: conserva le restanti carte illegali." % cname(j))
				break
			var k = await ch.choose(j, "Raid della Gestapo: %s possiede la carta illegale %s." % [cname(j), cardname(c)],
				[{"label": "Scartala", "img": cimg(c)}, {"label": "Conservala (+1 sospetto)", "img": cimg(c)}])
			if k == 0:
				discard_card(j, P(j).dossier.find(c))
			else:
				add_susp(j, 1)
	if s.dissent > 0:
		log_msg("I dadi sull'indicatore del Dissenso tornano nella riserva.")
	s.dissent = 0
	upd()

# =====================================================================
# Interrogatorio
# =====================================================================
func interrogation(i: int) -> void:
	if s.mods.ck and ally_ready("lukaschek"):
		var lk = await ch.choose(i, "%s è in prigione. Vuoi usare l'alleato Hans Lukaschek per essere rilasciato invece di risolvere la carta interrogatorio?" % cname(i), ["No", "Sì, usa Hans Lukaschek"])
		if lk == 1:
			use_ally("lukaschek")
			release(i, 2)
			return
	if s.ideck.is_empty():
		return
	var k: int = s.ideck.pop_front()
	var card = BOData.INTERR[k]
	var img := "res://assets/cards/interr/i%02d.jpg" % k
	log_msg("%s pesca una carta interrogatorio." % cname(i))
	var opts: Array = []
	var codes: Array = []
	var fxs := {"A": card.A[1], "B": card.B[1]}
	if card.has("C"):
		fxs["C"] = card.C[1]
	for o in ["A", "B", "C"]:
		var lbl: String
		var ok: bool
		if o == "C" and not card.has("C"):
			lbl = "C – Prova a Resistere (tira %d dad%s)" % [2 if P(i).mot <= 1 else 1, "i" if P(i).mot <= 1 else "o"]
			ok = true
		else:
			lbl = "%s – %s" % [o, card[o][0]]
			ok = can_fx(i, fxs[o])
		if ok:
			opts.append(lbl)
			codes.append(o)
	if opts.is_empty():
		for o in fxs:
			opts.append("%s – %s" % [o, card[o][0]])
			codes.append(o)
	var c = await ch.choose(i, "Carta interrogatorio%s: scegli un'opzione (solo le opzioni risolvibili per intero sono disponibili)." % ((" «" + card.title + "»") if card.has("title") else ""), opts, {"imgs": [img]})
	var o: String = codes[c]
	if o == "C" and not card.has("C"):
		var n := 2 if P(i).mot <= 1 else 1
		var r := roll(n)
		var worst: String = r[0]
		for f in r:
			if FACE_RANK[f] < FACE_RANK[worst]:
				worst = f
		log_msg("%s prova a resistere: %s → %s." % [cname(i), dice_txt(r), FACE_TXT[worst]])
		await ch.notify("Prova a Resistere", {"dice": r, "text": "Risultato considerato: " + FACE_TXT[worst]})
		await exec_fx(i, card.res[worst])
	else:
		log_msg("%s sceglie: %s." % [cname(i), card[o][0]])
		await exec_fx(i, fxs[o])
	if card.get("remove", false):
		s.iremoved.append(k)
	else:
		s.ideck.append(k)
		shuffle(s.ideck)
	upd()

func targets_free(r: int) -> Array:
	var t := free_list()
	t.erase(r)
	return t

func can_op(r: int, op: Array) -> bool:
	var fr := targets_free(r)
	match op[0]:
		"release", "release_all", "extra_events":
			return true
		"dissent_clear":
			return s.dissent > 0
		"card_each":
			if fr.is_empty():
				return false
			for j in fr:
				if P(j).dossier.size() < op[1]:
					return false
			return true
		"card_one":
			return fr.any(func(j): return P(j).dossier.size() >= op[1])
		"card_two":
			return fr.filter(func(j): return P(j).dossier.size() >= op[1]).size() >= 2
		"card_total":
			var t := 0
			for j in fr:
				t += P(j).dossier.size()
			return t >= op[1]
		"plot_one":
			return fr.any(func(j): return count_plots(j) >= op[1])
		"plot_total":
			var t := 0
			for j in fr:
				t += count_plots(j)
			return t >= op[1]
		"item_one":
			return fr.any(func(j): return P(j).items.size() >= op[1])
		"item_two":
			return fr.filter(func(j): return P(j).items.size() >= op[1]).size() >= 2
		"item_each":
			if fr.is_empty():
				return false
			for j in fr:
				if P(j).items.size() < op[1]:
					return false
			return true
		"susp_one":
			return fr.any(func(j): return P(j).susp + op[1] <= 3)
		"susp_two":
			return fr.filter(func(j): return P(j).susp + op[1] <= 3).size() >= 2
		"mot_one":
			return fr.any(func(j): return P(j).mot - op[1] >= mot_floor(j))
		"mot_two":
			return fr.filter(func(j): return P(j).mot - op[1] >= mot_floor(j)).size() >= 2
		"mot_every":
			if fr.is_empty():
				return false
			for j in fr:
				if P(j).mot - op[1] < mot_floor(j):
					return false
			return true
		"ms":
			return s.ms + op[1] <= 7
		"arrest_one":
			return fr.size() > 0
		"or":
			return can_fx(r, op[1]) or can_fx(r, op[2])
		"burn_cover":
			return fr.any(func(j): return P(j).susp == 0)
		"deputies_nearest":
			for d in all_deputies():
				if nearest_consp_spaces(s.leaders[d], true).size() > 0:
					return true
			return false
		"faulty_die":
			return fr.size() > 0 and s.faulty < 0 and dice_available() > 0
		"surveil_die":
			return fr.size() > 0 and s.surveil < 0 and dice_available() > 0
		"block_ability":
			return fr.any(func(j): return not (j in s.blocked)) and dice_available() > 0
		"silence_dissent":
			return not s.dissent_off
		"reshuffle_raid":
			for e in s.ev_discard:
				if EV[e].kind == "raid" and EV[e].stage == s.stage:
					return true
			return false
		"board_items":
			return board_item_cands(op[2]).size() >= op[1]
		"ordini_berlino":
			if fr.is_empty():
				return false
			return nearest_deputies(P(fr[0]).space).size() > 0
		"take_discard":
			return s.cdiscard.size() + s.item_discard.size() > 0
	return true

func can_fx(r: int, fx: Array) -> bool:
	for op in fx:
		if not can_op(r, op):
			return false
	return true

func count_plots(j: int) -> int:
	var n := 0
	for c in P(j).dossier:
		if is_plot(c):
			n += 1
	return n

func board_item_cands(revealed: bool) -> Array:
	var r: Array = []
	for sp in s.board_items:
		for tl in s.board_items[sp]:
			if tl.rev == revealed:
				r.append(sp)
				break
	return r

func nearest_deputies(sp: String) -> Array:
	var best := 999
	var r: Array = []
	var dd := dists_from(sp)
	for d in all_deputies():
		var ds: String = s.leaders[d]
		if ds == sp or not dd.has(ds):
			continue
		if dd[ds] < best:
			best = dd[ds]
			r = [d]
		elif dd[ds] == best:
			r.append(d)
	return r

func pick_player(r: int, prompt: String, cand: Array) -> int:
	if cand.is_empty():
		return -1
	if cand.size() == 1:
		return cand[0]
	var o: Array = []
	for c in cand:
		o.append("%s (mot. %s, sosp. %s, %d carte, %d oggetti)" % [cname(c), BOData.MOT_NAMES[P(c).mot], BOData.SUSP_NAMES[P(c).susp], P(c).dossier.size(), P(c).items.size()])
	return cand[await ch.choose(r, prompt, o)]

func discard_cards_of(r: int, j: int, n: int, only_plots: bool = false) -> void:
	for k in range(n):
		var idxs: Array = []
		var cards: Array = []
		for x in range(P(j).dossier.size()):
			if not only_plots or is_plot(P(j).dossier[x]):
				idxs.append(x)
				cards.append(P(j).dossier[x])
		if idxs.is_empty():
			return
		var c = await ch.choose(r, "Scegli la carta da scartare dal dossier di %s" % cname(j), card_opts(cards))
		discard_card(j, idxs[c])

func discard_items_of(r: int, j: int, n: int) -> void:
	for k in range(n):
		if P(j).items.is_empty():
			return
		var c = await ch.choose(r, "Scegli l'oggetto da scartare dalla scheda di %s" % cname(j), item_opts(P(j).items))
		discard_item(j, c)

func exec_fx(r: int, fx: Array) -> void:
	for op in fx:
		if s.over:
			return
		await exec_op(r, op)
		upd()

func exec_op(r: int, op: Array) -> void:
	var fr := targets_free(r)
	match op[0]:
		"release":
			release(r, op[1] if op.size() > 1 else 2)
		"release_all":
			for j in prisoners():
				release(j, 2)
		"extra_events":
			s.turn.extra_events += op[1]
			log_msg("Dopo l'evento di questo turno si pescheranno %d carte evento aggiuntive." % op[1])
		"dissent_clear":
			s.dissent = 0
			log_msg("I dadi del Dissenso tornano nella riserva.")
		"card_each":
			for j in fr:
				await discard_cards_of(r, j, op[1])
		"card_one":
			var j = await pick_player(r, "Da quale dossier scartare %d carte?" % op[1], fr.filter(func(x): return P(x).dossier.size() > 0))
			if j >= 0:
				await discard_cards_of(r, j, op[1])
		"card_two":
			var c: Array = fr.filter(func(x): return P(x).dossier.size() > 0)
			for n in range(2):
				var j = await pick_player(r, "Scegli un dossier da cui scartare", c)
				if j < 0:
					break
				c.erase(j)
				await discard_cards_of(r, j, op[1])
		"card_total", "plot_total":
			var only: bool = op[0] == "plot_total"
			for n in range(op[1]):
				var c: Array = fr.filter(func(x): return (count_plots(x) if only else P(x).dossier.size()) > 0)
				var j = await pick_player(r, "Scegli il dossier da cui scartare (%d di %d)" % [n + 1, op[1]], c)
				if j < 0:
					break
				await discard_cards_of(r, j, 1, only)
		"plot_one":
			var j = await pick_player(r, "Da quale dossier scartare un complotto?", fr.filter(func(x): return count_plots(x) > 0))
			if j >= 0:
				await discard_cards_of(r, j, op[1], true)
		"item_one":
			var j = await pick_player(r, "Da quale scheda scartare %d oggetti?" % op[1], fr.filter(func(x): return P(x).items.size() > 0))
			if j >= 0:
				await discard_items_of(r, j, op[1])
		"item_two":
			var c: Array = fr.filter(func(x): return P(x).items.size() > 0)
			for n in range(2):
				var j = await pick_player(r, "Scegli una scheda da cui scartare un oggetto", c)
				if j < 0:
					break
				c.erase(j)
				await discard_items_of(r, j, op[1])
		"item_each":
			for j in fr:
				await discard_items_of(r, j, op[1])
		"susp_one":
			var c: Array = fr.filter(func(x): return P(x).susp < 3)
			var j = await pick_player(r, "Chi aumenta il sospetto di %d?" % op[1], c)
			if j >= 0:
				add_susp(j, op[1])
		"susp_two":
			var c: Array = fr.filter(func(x): return P(x).susp < 3)
			for n in range(2):
				var j = await pick_player(r, "Chi aumenta il sospetto di %d?" % op[1], c)
				if j < 0:
					break
				c.erase(j)
				add_susp(j, op[1])
		"mot_one":
			var c: Array = fr.filter(func(x): return P(x).mot > mot_floor(x))
			var j = await pick_player(r, "Chi perde %d motivazione?" % op[1], c)
			if j >= 0:
				add_mot(j, -op[1])
		"mot_two":
			var c: Array = fr.filter(func(x): return P(x).mot > mot_floor(x))
			for n in range(2):
				var j = await pick_player(r, "Chi perde %d motivazione?" % op[1], c)
				if j < 0:
					break
				c.erase(j)
				add_mot(j, -op[1])
		"mot_every":
			for j in fr:
				add_mot(j, -op[1])
		"ms":
			add_ms(op[1])
		"arrest_one":
			var j = await pick_player(r, "Chi viene arrestato?", fr)
			if j >= 0:
				arrest(j)
		"or":
			var o: Array = []
			var fxl: Array = []
			if can_fx(r, op[1]):
				o.append(fx_label(op[1]))
				fxl.append(op[1])
			if can_fx(r, op[2]):
				o.append(fx_label(op[2]))
				fxl.append(op[2])
			if fxl.is_empty():
				fxl = [op[1]]
				o = [fx_label(op[1])]
			var k = await ch.choose(r, "Scegli l'effetto", o)
			await exec_fx(r, fxl[k])
		"burn_cover":
			var j = await pick_player(r, "Quale cospiratore passa da sospetto Basso a Estremo?", fr.filter(func(x): return P(x).susp == 0))
			if j >= 0:
				set_susp(j, 3)
		"deputies_nearest":
			for d in all_deputies():
				var c := nearest_consp_spaces(s.leaders[d], true)
				if c.is_empty():
					continue
				var dest: String = c[0]
				if c.size() > 1:
					dest = await ch.choose_space(r, "Dove muovere %s?" % BOData.LEADER_NAMES[d], c, false)
				move_leader(d, dest)
		"faulty_die":
			var j = await pick_player(r, "Su quale scheda collocare il dado difettoso?", fr)
			if j >= 0:
				s.faulty = j
				log_msg("Equipaggiamento Difettoso: il prossimo ⊕ di %s verrà ignorato." % cname(j))
		"surveil_die":
			var j = await pick_player(r, "Su quale scheda collocare il dado della sorveglianza?", fr)
			if j >= 0:
				s.surveil = j
				log_msg("Sorveglianza Potenziata: il prossimo tiro di %s riceverà un'aquila aggiuntiva." % cname(j))
		"block_ability":
			var j = await pick_player(r, "Quale capacità cospiratore viene bloccata per il resto della partita?", fr.filter(func(x): return not (x in s.blocked)))
			if j >= 0:
				s.blocked.append(j)
				log_msg("La capacità di %s è bloccata per il resto della partita." % cname(j))
		"silence_dissent":
			s.dissent = 0
			s.dissent_off = true
			log_msg("Popolazione Zittita: l'indicatore del Dissenso non può più essere usato.")
		"reshuffle_raid":
			for e in s.ev_discard:
				if EV[e].kind == "raid" and EV[e].stage == s.stage:
					s.ev_discard.erase(e)
					s.decks[s.stage].append(e)
					shuffle(s.decks[s.stage])
					log_msg("Un Raid della Gestapo viene rimescolato nel mazzo dello stadio %d." % s.stage)
					break
		"board_items":
			for n in range(op[1]):
				var c := board_item_cands(op[2])
				if c.is_empty():
					break
				if op[3]:
					var lo := 99
					for sp in c:
						lo = mini(lo, sp_stage(sp))
					c = c.filter(func(x): return sp_stage(x) == lo)
				var sp: String = c[0]
				if c.size() > 1:
					sp = await ch.choose_space(r, "Scegli l'oggetto da rimuovere dal tabellone (%d di %d)" % [n + 1, op[1]], c, false)
				for x in range(s.board_items[sp].size()):
					if s.board_items[sp][x].rev == op[2]:
						remove_tile(sp, x, true)
						break
				log_msg("Rimosso l'oggetto da %s." % spname(sp))
		"ordini_berlino":
			if fr.is_empty():
				return
			var tsp: String = P(fr[0]).space
			var c := nearest_deputies(tsp)
			if c.is_empty():
				return
			var d: String = c[0]
			if c.size() > 1:
				var o: Array = []
				for x in c:
					o.append(BOData.LEADER_NAMES[x])
				d = c[await ch.choose(r, "Quale delegato muovere?", o)]
			move_leader(d, tsp)
		"take_discard":
			var o: Array = []
			var codes: Array = []
			for k in range(s.cdiscard.size()):
				o.append({"label": cardname(s.cdiscard[k]), "img": cimg(s.cdiscard[k])})
				codes.append(["card", k])
			for k in range(s.item_discard.size()):
				o.append({"label": "Oggetto: " + BOData.ITEM_NAMES[s.item_discard[k]], "img": "res://assets/items/%s.png" % s.item_discard[k]})
				codes.append(["item", k])
			if o.is_empty():
				return
			var k = await ch.choose(r, "Effetti Personali: scegli una carta cospiratore scartata o un oggetto scartato", o)
			if codes[k][0] == "card":
				P(r).dossier.append(s.cdiscard[codes[k][1]])
				s.cdiscard.remove_at(codes[k][1])
			else:
				P(r).items.append(s.item_discard[codes[k][1]])
				s.item_discard.remove_at(codes[k][1])

func fx_label(fx: Array) -> String:
	var t: Array = []
	for op in fx:
		match op[0]:
			"susp_one":
				t.append("+%d sospetto a un cospiratore" % op[1])
			"susp_two":
				t.append("+%d sospetto a due cospiratori" % op[1])
			_:
				t.append(str(op))
	return ", ".join(t)

# =====================================================================
# Anteprima di un complotto (per l'interfaccia)
# =====================================================================
func count_sources(i: int, t: String) -> int:
	return item_sources(i, t, true).size()

func plot_preview(i: int, letter: String, bolt_ctx: bool = false) -> Dictionary:
	var pl = BOData.PLOTS[letter]
	var r = pl.req
	var p := P(i)
	var req: Array = []
	var need_mot: int = r.mot
	if BOData.CONSPIRATORS[p.cid].get("no_plots", false):
		req.append(["%s non può tentare complotti" % cname(i), false])
	if s.mods.ck:
		req.append(["Almeno 1 alleato nel Circolo di Kreisau (%d)" % s.ck.circle.size(), s.ck.circle.size() > 0])
		if s.ck.circle.size() == 1:
			need_mot = 4
	req.append(["Motivazione %s (ora %s)" % [BOData.MOT_NAMES[need_mot], BOData.MOT_NAMES[p.mot]], p.mot >= need_mot])
	if r.get("bolt", false):
		req.append(["Subito dopo che un evento ha mosso Hitler", bolt_ctx])
	if r.has("stage_min"):
		req.append(["Stadio 6 o 7 (ora %d)" % s.stage, s.stage >= r.stage_min])
	var h := hitler()
	if r.same:
		req.append(["Nella casella di Hitler (%s)" % spname(h), p.space == h])
	if r.has("hit"):
		var hd = BOData.SPACES[h]
		var ok := true
		match r.hit:
			"fort":
				ok = hd.fort
			"notfort":
				ok = not hd.fort
			"berlin":
				ok = hd.stage == 0
			"s12b":
				ok = hd.stage <= 2
			"s345":
				ok = hd.stage >= 3
		req.append([BOData.HIT_TEXT[r.hit], ok])
	var dice := 1
	var cancel := 0
	var opt: Array = []
	var extra_txt: Array = []
	if s.mods.or and s.orr.done.size() > 0:
		dice += s.orr.done.size()
		extra_txt.append("+%d dad%s per le missioni completate" % [s.orr.done.size(), "o" if s.orr.done.size() == 1 else "i"])
	var kmod_t := 0
	var kmod_e := 0
	if s.mods.ck:
		var stt = BOData.KREISAU_STATUS[mini(s.ck.circle.size(), 5)]
		kmod_t = stt[0]
		kmod_e = stt[1]
		extra_txt.append("Circolo di Kreisau: " + stt[2])
	var sp: String = p.space
	for o in pl.opt:
		match o[0]:
			"aff":
				var ok: bool = aff(i) == o[1]
				opt.append(["Affiliazione %s: +1 dado" % o[1], ok])
				if ok:
					dice += 1
			"item":
				var n := count_sources(i, o[1])
				var use := mini(n, 99 if o[2] else 1)
				opt.append(["%s%s: +1 dado%s (disponibili: %d)" % [BOData.ITEM_NAMES[o[1]], "*" if o[2] else "", " ciascuno" if o[2] else "", n], use > 0])
				dice += use
			"cred":
				var n := count_sources(i, "CRED")
				var use := mini(n, 99 if o[1] else 1)
				opt.append(["Credenziali%s: annulla 1 aquila%s (disponibili: %d)" % ["*" if o[1] else "", " ciascuna" if o[1] else "", n], use > 0])
				cancel += use
			"all_same":
				var ok := free_list().size() == np()
				for j in range(np()):
					if P(j).space != sp:
						ok = false
				opt.append(["Tutti i cospiratori nella stessa casella: +2 dadi", ok])
				if ok:
					dice += 2
			"hitler_in":
				var ok: bool = h in o[1]
				opt.append(["Hitler al Ministero o alla Cancelleria: +1 dado", ok])
				if ok:
					dice += 1
			"other_here":
				var n := players_in(sp).size() - 1
				opt.append(["Altri cospiratori nella casella: +1 dado ciascuno (%d)" % n, n > 0])
				dice += maxi(n, 0)
			"any_item":
				var n := count_sources(i, "ANY")
				opt.append(["Qualsiasi oggetto: annulla 1 aquila ciascuno (disponibili: %d)" % n, n > 0])
				cancel += n
	var ok_all := true
	for q in req:
		if not q[1]:
			ok_all = false
	var extra: Array = []
	if find_card(i, "MOMENTO") >= 0:
		extra.append("Il Momento della Verità (+2 dadi)")
	for j in players_in(sp):
		if ab_on(j, "beck"):
			extra.append("Beck (+1 dado)")
		if ab_on(j, "helldorf") and is_berlin(sp):
			extra.append("Helldorf (+2 dadi)")
	return {"ok": ok_all, "req": req, "opt": opt, "dice": mini(dice, dice_available()), "cancel": cancel,
		"need": s.ms - kmod_t, "limit": BOData.SUSP_EAGLES[p.susp], "mod": event_mod() + kmod_e, "extra": extra, "name": pl.name, "notes": extra_txt}

# #####################################################################
# ESPANSIONE «LA RESISTENZA»
# #####################################################################
func exp_setup() -> void:
	var md: Array = []
	for k in range(BOData.MISSIONS.size()):
		md.append(k)
	shuffle(md)
	s.orr = {"tok": {}, "perm": "", "sup": {"A": 2, "R": 2, "G": 2, "V": 5},
		"act": {"A": -1, "R": -1, "G": -1}, "comb": {"A": -1, "R": -1, "G": -1},
		"mdeck": md, "mdisc": [], "done": [], "prove": 2, "comb_sup": 2,
		"skip_raid": 0, "no_pen": -1, "dossier_bonus": 0, "hideout": "", "hideout_have": false,
		"flagged": {}, "pending": [], "checking": false}
	var ed: Array = []
	for k in range(BOData.ENCOUNTERS.size()):
		ed.append(k)
	shuffle(ed)
	s.kk = {"pos": "", "edeck": ed, "edisc": [], "fiato": [], "nocons_until": -1, "nocons_stage": 0, "favore": -1}
	var ap: Array = []
	for k in range(BOData.ALLIES.size()):
		ap.append(k)
	shuffle(ap)
	s.ck = {"apile": ap, "res": [], "circle": []}
	if s.mods.ck:
		for k in range(3):
			s.ck.res.append(s.ck.apile.pop_front())
	var names: Array = []
	if s.mods.or:
		names.append("Orchestra Rossa")
	if s.mods.kk:
		names.append("Horst Kopkow")
	if s.mods.ck:
		names.append("Circolo di Kreisau")
	if names.size() > 0:
		log_msg("Moduli de «La Resistenza»: " + ", ".join(names) + ".")

func exp_turn_start(i: int) -> void:
	if s.mods.or and s.orr.no_pen == i:
		s.orr.no_pen = -1
		log_msg("Contromessaggio: le penalità tornano ad applicarsi.")
	if s.mods.kk and s.kk.nocons_until == i:
		s.kk.nocons_until = -1
		log_msg("Eccesso di Cautela: Cospirare torna disponibile.")

## Margarethe von Oven: ogni aumento di motivazione può diventare −1 sospetto.
func resolve_oven() -> void:
	while s.oven_pending.size() > 0 and not s.over:
		var j: int = s.oven_pending.pop_front()
		var p := P(j)
		if p.prison or p.mot >= mot_cap(j):
			continue
		var k := 0
		if p.susp > susp_floor(j):
			k = await ch.choose(j, "Margarethe von Oven può aumentare la motivazione. Cosa scegli?", ["+1 motivazione (%s → %s)" % [BOData.MOT_NAMES[p.mot], BOData.MOT_NAMES[p.mot + 1]], "−1 sospetto (%s → %s)" % [BOData.SUSP_NAMES[p.susp], BOData.SUSP_NAMES[p.susp - 1]]])
		if k == 0:
			log_msg("%s: motivazione %s → %s." % [cname(j), BOData.MOT_NAMES[p.mot], BOData.MOT_NAMES[p.mot + 1]])
			p.mot += 1
		else:
			add_susp(j, -1)
		upd()

## Hitler o un delegato entrano in una casella: rimuovono segnalini e alleati rivelati.
func leader_entered(sp: String) -> void:
	if s.mods.or and s.orr.tok.has(sp):
		var col: String = s.orr.tok[sp]
		s.orr.tok.erase(sp)
		s.orr.sup[col] += 1
		log_msg("Il segnalino %s a %s viene rimosso." % [BOData.TEL_NAMES[col], spname(sp)])
		if col != "V" and s.orr.act[col] >= 0 and tels_of(col).is_empty() and s.orr.perm == "":
			discard_mission(col, "tutte le telescriventi %s sono state rimosse" % BOData.TEL_NAMES[col])
	if s.mods.ck and s.board_items.has(sp):
		var arr: Array = s.board_items[sp]
		for x in range(arr.size() - 1, -1, -1):
			if arr[x].t == "ALLEATO" and arr[x].rev:
				remove_tile(sp, x, false)
				log_msg("La tessera Alleato a %s viene rimossa dal gioco." % spname(sp))

# ---------------------------------------------------------------------
# Tessere oggetto (pile sulle caselle)
# ---------------------------------------------------------------------
func unrevealed_idx(sp: String) -> int:
	if not s.board_items.has(sp):
		return -1
	var arr: Array = s.board_items[sp]
	for x in range(arr.size()):
		if not arr[x].rev:
			return x
	return -1

func collectable_idx(sp: String) -> Array:
	var r: Array = []
	if not s.board_items.has(sp):
		return r
	var arr: Array = s.board_items[sp]
	for x in range(arr.size()):
		if arr[x].rev and arr[x].t != "ALLEATO":
			r.append(x)
	return r

func remove_tile(sp: String, k: int, to_discard: bool) -> void:
	var arr: Array = s.board_items[sp]
	var tl = arr[k]
	arr.remove_at(k)
	if to_discard and (tl.t in BOData.BASE_ITEMS or tl.t == "QUALSIASI"):
		s.item_discard.append(tl.t)
	if arr.is_empty():
		s.board_items.erase(sp)

func contatto_spaces() -> Array:
	var r: Array = []
	for sp in s.board_items:
		for tl in s.board_items[sp]:
			if not (tl.t == "ALLEATO" and tl.rev):
				r.append(sp)
				break
	return r

func reveal_tile(sp: String, k: int, who: int) -> void:
	if k < 0 or not s.board_items.has(sp):
		return
	var tl = s.board_items[sp][k]
	tl.rev = true
	if who >= 0:
		log_msg("%s rivela l'oggetto a %s: %s." % [cname(who), spname(sp), BOData.ITEM_NAMES[tl.t]])
	else:
		log_msg("Rivelato l'oggetto a %s: %s." % [spname(sp), BOData.ITEM_NAMES[tl.t]])
	if tl.t == "RAIDT":
		remove_tile(sp, k, false)
		await ch.notify("Tessera Raid della Gestapo!", {"img": item_img("RAIDT"), "text": "Si risolve immediatamente un Raid della Gestapo."})
		await gestapo_raid(true)
	upd()

func take_tile(i: int, sp: String, k: int, resolve_ally: bool = false) -> void:
	if k < 0 or not s.board_items.has(sp):
		return
	var tl = s.board_items[sp][k]
	if tl.t == "ALLEATO":
		if resolve_ally and s.ck.res.size() > 0:
			remove_tile(sp, k, false)
			log_msg("%s recluta un alleato da %s." % [cname(i), spname(sp)])
			await recruit(i)
		elif not tl.rev:
			tl.rev = true
			log_msg("L'oggetto a %s è un Alleato: resta sulla casella, rivelato." % spname(sp))
		return
	remove_tile(sp, k, false)
	match tl.t:
		"RAIDT":
			log_msg("%s scopre una tessera Raid della Gestapo a %s!" % [cname(i), spname(sp)])
			await ch.notify("Tessera Raid della Gestapo!", {"img": item_img("RAIDT"), "text": "Si risolve immediatamente un Raid della Gestapo."})
			await gestapo_raid(true)
		"MOTMS":
			var o: Array = []
			var codes: Array = []
			if P(i).mot < mot_cap(i):
				o.append("+1 motivazione a %s" % cname(i))
				codes.append(0)
			if s.ms > s.ms_start:
				o.append("−1 Supporto Militare di Hitler")
				codes.append(1)
			if codes.is_empty():
				log_msg("La tessera +1 Motivazione / −1 Supporto Militare non ha effetto.")
			else:
				var c = await ch.choose(i, "Tessera «+1 Motivazione o −1 Supporto Militare»: cosa scegli?", o, {"imgs": [item_img("MOTMS")]})
				if codes[c] == 0:
					add_mot(i, 1)
				else:
					add_ms(-1)
		_:
			P(i).items.append(tl.t)
			log_msg("%s raccoglie l'oggetto %s a %s." % [cname(i), BOData.ITEM_NAMES[tl.t], spname(sp)])
	upd()

# ---------------------------------------------------------------------
# Orchestra Rossa
# ---------------------------------------------------------------------
func tels_of(col: String) -> Array:
	var r: Array = []
	for sp in s.orr.tok:
		if s.orr.tok[sp] == col:
			r.append(sp)
	return r

func placed_tels() -> Array:
	var r: Array = []
	for sp in s.orr.tok:
		if s.orr.tok[sp] != "V":
			r.append(sp)
	return r

func tel_supply_colors() -> Array:
	var r: Array = []
	for c in BOData.TEL_COLORS:
		if s.orr.sup[c] > 0:
			r.append(c)
	return r

func token_free_spaces() -> Array:
	var r: Array = []
	for sp in BOData.SPACES:
		if BOData.SPACES[sp].deliver.size() > 0 and valid(sp) and not s.orr.tok.has(sp) and s.orr.perm != sp:
			r.append(sp)
	return r

func mission_img(m: int) -> String:
	return "res://assets/res/missions/m%02d.jpg" % m

func place_token(i: int, sp: String, col: String) -> void:
	s.orr.tok[sp] = col
	s.orr.sup[col] -= 1
	log_msg("%s colloca %s a %s." % [cname(i), ("un volantino" if col == "V" else "una telescrivente " + BOData.TEL_NAMES[col]), spname(sp)])
	if col != "V" and s.orr.act[col] < 0:
		await reveal_mission(col)
	upd()

func reveal_mission(col: String) -> void:
	if s.orr.mdeck.is_empty() and s.orr.mdisc.size() > 0:
		s.orr.mdeck = s.orr.mdisc.duplicate()
		s.orr.mdisc.clear()
		shuffle(s.orr.mdeck)
	if s.orr.mdeck.is_empty():
		return
	var m: int = s.orr.mdeck.pop_front()
	s.orr.act[col] = m
	log_msg("Nuova missione (%s): %s." % [BOData.TEL_NAMES[col], BOData.MISSIONS[m].name])
	upd()
	await ch.notify("Nuova missione – telescrivente %s" % BOData.TEL_NAMES[col], {"img": mission_img(m), "text": BOData.MISSIONS[m].req})

func discard_mission(col: String, reason: String) -> void:
	var m: int = s.orr.act[col]
	if m < 0:
		return
	s.orr.mdisc.append(m)
	s.orr.act[col] = -1
	var c: int = s.orr.comb[col]
	if c >= 0:
		var k: int = P(c).items.find("COMB")
		if k >= 0:
			P(c).items.remove_at(k)
		s.orr.comb_sup += 1
		s.orr.comb[col] = -1
	log_msg("La missione %s viene scartata (%s)." % [BOData.MISSIONS[m].name, reason])

func comb_carrier_for(key: String) -> int:
	for col in BOData.TEL_COLORS:
		var m: int = s.orr.act[col]
		if m >= 0 and BOData.MISSIONS[m].k == key:
			return s.orr.comb[col]
	return -1

## Un Combattente della Resistenza viene scartato dalla scheda di i.
func comb_lost(i: int) -> void:
	s.orr.comb_sup += 1
	for col in BOData.TEL_COLORS:
		if s.orr.comb[col] == i:
			s.orr.comb[col] = -1
			discard_mission(col, "il Combattente della Resistenza è stato perso")
			if tels_of(col).size() > 0:
				s.orr.pending.append(["reveal", col])
			return

func or_on_arrest(i: int) -> void:
	for col in BOData.TEL_COLORS:
		var m: int = s.orr.act[col]
		if m < 0:
			continue
		match BOData.MISSIONS[m].k:
			"goebbels":
				var g: String = s.leaders.GOEBBELS
				if g != "" and P(i).space in nearest_consp_spaces(g, false):
					s.orr.pending.append(["done", col, i])
			"tieni_duro":
				s.orr.flagged[str(i)] = true

func or_on_release(i: int) -> void:
	if not s.orr.flagged.has(str(i)):
		return
	s.orr.flagged.erase(str(i))
	for col in BOData.TEL_COLORS:
		var m: int = s.orr.act[col]
		if m >= 0 and BOData.MISSIONS[m].k == "tieni_duro":
			s.orr.pending.append(["done", col, i])

func or_on_raid() -> void:
	for col in BOData.TEL_COLORS:
		if s.orr.act[col] >= 0 and s.orr.comb[col] >= 0:
			discard_mission(col, "il Raid della Gestapo ha sorpreso il Combattente della Resistenza")

func v_count(f: Callable) -> int:
	var n := 0
	for sp in s.orr.tok:
		if s.orr.tok[sp] == "V" and f.call(sp):
			n += 1
	return n

func illegal_count(j: int) -> int:
	var n := 0
	for c in P(j).dossier:
		if is_illegal(c):
			n += 1
	return n

## Controlla le missioni che si completano da sole e quelle in sospeso.
func check_missions() -> void:
	if s.orr.checking or s.over:
		return
	s.orr.checking = true
	var guard := 0
	while not s.over and guard < 10:
		guard += 1
		var found := false
		while s.orr.pending.size() > 0:
			var pd: Array = s.orr.pending.pop_front()
			if pd[0] == "reveal":
				if s.orr.act[pd[1]] < 0:
					await reveal_mission(pd[1])
			elif s.orr.act[pd[1]] >= 0:
				await complete_mission(pd[1], pd[2])
				found = true
		for col in BOData.TEL_COLORS:
			var m: int = s.orr.act[col]
			if m < 0:
				continue
			var md = BOData.MISSIONS[m]
			var who := -1
			match md.k:
				"contromessaggio":
					if v_count(func(sp): return leaders_in(sp).size() > 0) >= 3:
						who = s.active
				"arresto_gestapo", "arresto_dh":
					for j in free_list():
						if P(j).space == md.sp and P(j).susp == 0:
							who = j
							break
				"promuovi_berlino":
					if v_count(func(sp): return is_berlin(sp)) >= np():
						who = s.active
				"promuovi_23":
					if v_count(func(sp): return sp_stage(sp) == 2 or sp_stage(sp) == 3) >= np():
						who = s.active
				"dodd":
					var fl := free_list()
					if fl.size() > 0 and fl.all(func(j): return illegal_count(j) >= 2):
						who = s.active
				"fuggitivi":
					for j in free_list():
						if "FIRMA" in P(j).items and "CRED" in P(j).items:
							who = j
							break
				"confine", "cielo", "piani":
					var c: int = s.orr.comb[col]
					if c >= 0 and not P(c).prison and P(c).space in md.to and not kk_blocked(P(c).space):
						var k: int = P(c).items.find("COMB")
						if k >= 0:
							P(c).items.remove_at(k)
						s.orr.comb_sup += 1
						s.orr.comb[col] = -1
						log_msg("%s consegna il Combattente della Resistenza a %s." % [cname(c), spname(P(c).space)])
						who = c
			if who >= 0:
				await complete_mission(col, who)
				found = true
				break
		if not found:
			break
	s.orr.checking = false

func complete_mission(col: String, who: int) -> void:
	var m: int = s.orr.act[col]
	if m < 0:
		return
	var md = BOData.MISSIONS[m]
	s.orr.done.append(m)
	s.orr.act[col] = -1
	s.orr.comb[col] = -1
	for sp in tels_of(col):
		s.orr.tok.erase(sp)
	s.orr.sup[col] = 2
	log_msg("✔ MISSIONE COMPLETATA: %s (%s). Tutti i futuri complotti hanno +1 dado." % [md.name, cname(who)])
	upd()
	await ch.notify("Missione completata: " + md.name, {"img": mission_img(m), "text": "Ricompensa: " + md.rew})
	match md.k:
		"contromessaggio":
			s.orr.no_pen = who
		"arresto_gestapo", "arresto_dh":
			if not P(who).prison and dice_available() > 0:
				await conspire_roll(who, mini(3, dice_available()))
		"intercetta_hess", "intercetta_himmler", "prove_fort", "prove_st4":
			give_prove(who)
		"goebbels":
			for j in free_list():
				if j != who:
					set_susp(j, 0)
		"inventario":
			for sp in s.board_items.keys():
				if sp_stage(sp) <= s.stage:
					while unrevealed_idx(sp) >= 0 and not s.over:
						await reveal_tile(sp, unrevealed_idx(sp), -1)
		"segreti":
			add_mot(who, 1)
			var deps := all_deputies()
			if deps.size() > 0:
				var o: Array = []
				for d in deps:
					o.append({"label": "%s (a %s)" % [BOData.LEADER_NAMES[d], spname(s.leaders[d])], "img": "res://assets/leaders/%s.png" % d})
				var d: String = deps[await ch.choose(who, "Proteggere i Segreti: quale delegato muovi (fino a 3 caselle)?", o)]
				var dest = await ch.choose_space(who, "Dove muovere %s?" % BOData.LEADER_NAMES[d], within_any(s.leaders[d], 3), false)
				move_leader(d, dest)
		"autorizzazione":
			s.orr.skip_raid += 1
		"conversazione":
			s.orr.dossier_bonus += 1
		"falsario":
			for j in free_list():
				if s.cdeck.is_empty():
					break
				var k = await ch.choose(j, "Esperto Falsario: %s sceglie 1 carta dal mazzo cospiratore." % cname(j), card_opts(s.cdeck))
				P(j).dossier.append(s.cdeck[k])
				log_msg("%s prende %s dal mazzo." % [cname(j), cardname(s.cdeck[k])])
				s.cdeck.remove_at(k)
			shuffle(s.cdeck)
		"promuovi_berlino":
			for j in free_list():
				if is_berlin(P(j).space):
					add_mot(j, 2)
		"promuovi_23":
			for j in free_list():
				if sp_stage(P(j).space) == 2 or sp_stage(P(j).space) == 3:
					add_mot(j, 2)
		"informare":
			add_ms(-2)
		"stalin":
			add_ms(-1)
		"cielo", "piani":
			add_susp(who, -2)
		"tieni_duro":
			set_susp(who, 0)
			await take_from_item_discard(who)
		"dodd":
			for j in free_list():
				add_susp(j, -2)
		"bormann":
			if s.leaders.BORMANN != "":
				s.leaders.BORMANN = ""
				log_msg("Martin Bormann viene rimosso dal gioco.")
		"reclutamento":
			if s.stage < 7:
				s.orr.perm = "WOLFSSCHANZE"
				log_msg("La telescrivente permanente viene collocata su Wolfsschanze.")
		"fuggitivi":
			s.orr.hideout_have = true
			await place_hideout(who)
		"lista":
			add_mot(who, 1)
			var dest = await ch.choose_space(who, "Lista dei Cospiratori: dove muovere Hitler (fino a 3 caselle)?", within_any(hitler(), 3), false)
			move_leader("HITLER", dest)
		"riunione":
			await take_from_item_discard(who)
			s.turn.free_transfer = true
			log_msg("Riunione Segreta: fino alla fine del turno i trasferimenti sono gratuiti.")
	upd()

func within_any(sp: String, n: int) -> Array:
	var dd := dists_from(sp)
	var r: Array = []
	for k in dd:
		if k != sp and dd[k] <= n:
			r.append(k)
	return r

func give_prove(who: int) -> void:
	if s.orr.prove <= 0:
		log_msg("Non ci sono più oggetti Prove disponibili.")
		return
	s.orr.prove -= 1
	P(who).items.append("PROVE")
	log_msg("%s prende un oggetto Prove." % cname(who))

func take_from_item_discard(who: int) -> void:
	if s.item_discard.is_empty():
		return
	var k = await ch.choose(who, "Scegli 1 oggetto dalla pila degli scarti", item_opts(s.item_discard))
	var it = s.item_discard[k]
	s.item_discard.remove_at(k)
	P(who).items.append(it)
	log_msg("%s prende %s dagli scarti." % [cname(who), BOData.ITEM_NAMES[it]])

func all_illegal_cards() -> Array:
	var r: Array = []
	for j in range(np()):
		for c in P(j).dossier:
			if is_illegal(c):
				r.append(c)
	return r

func place_hideout(who: int) -> void:
	var ill := all_illegal_cards()
	if ill.is_empty():
		log_msg("Il segnalino nascondiglio verrà collocato quando ci sarà una carta illegale.")
		return
	var k = await ch.choose(who, "Nascondere i Fuggitivi: su quale carta illegale collochi il nascondiglio?", card_opts(ill))
	s.orr.hideout = ill[k]
	log_msg("Il nascondiglio protegge %s durante i Raid." % cardname(ill[k]))

func mission_actions(i: int) -> Array:
	var r: Array = []
	var sp: String = P(i).space
	var blocked := kk_blocked(sp)
	var fort: bool = BOData.SPACES[sp].fort
	for col in BOData.TEL_COLORS:
		var m: int = s.orr.act[col]
		if m < 0:
			continue
		var md = BOData.MISSIONS[m]
		var ok := false
		var cost := 0
		match md.k:
			"inventario":
				ok = fort and item_sources(i, "ANY", false, false).size() >= 2
			"segreti":
				ok = fort and leaders_in(sp).any(func(l): return l != "HITLER") and item_sources(i, "ESPL", false, false).size() > 0
			"autorizzazione":
				ok = sp == "GESTAPO" and item_sources(i, "FIRMA", false, false).size() > 0
			"falsario":
				ok = sp == "ZURIGO" and P(i).dossier.size() >= 3
			"informare":
				ok = sp == "STOCCOLMA" and item_sources(i, "ANY", false, false).size() > 0
			"stalin":
				ok = sp == "VARSAVIA" and not leaders_in(sp).any(func(l): return l != "HITLER") and item_sources(i, "INFO", false, false).size() > 0
			"lista":
				ok = sp == hitler() and item_sources(i, "ESPL", false, false).size() > 0
			"riunione":
				ok = free_list().all(func(j): return P(j).space == sp)
			"intercetta_hess", "intercetta_himmler":
				ok = s.leaders[md.leader] == sp
				cost = 1
			"prove_fort":
				ok = fort
				cost = 1
			"prove_st4":
				ok = sp_stage(sp) == 4
				cost = 1
			"conversazione":
				ok = is_berlin(sp)
				cost = 1
			"bormann":
				var b: String = s.leaders.BORMANN
				ok = b != "" and ((s.orr.tok.has(b) and s.orr.tok[b] != "V") or s.orr.perm == b)
				cost = 1
			"reclutamento":
				ok = sp == "WOLFSSCHANZE" and P(i).items.size() > 0
				cost = 1
			"goebbels":
				var g: String = s.leaders.GOEBBELS
				if g != "" and sp in nearest_consp_spaces(g, false):
					r.append({"id": "exp", "key": "goebbels_arrest", "col": col, "cost": 1, "label": "Missione «%s»: fatti arrestare" % md.name})
			"confine", "cielo", "piani":
				if s.orr.comb[col] < 0 and sp == md.from and s.orr.comb_sup > 0 and not blocked:
					r.append({"id": "exp", "key": "comb_take", "col": col, "cost": 0, "label": "Missione «%s»: prendi il Combattente (+2 sospetto)" % md.name})
		if ok and not (blocked and md.k != "bormann"):
			r.append({"id": "exp", "key": "mission", "col": col, "cost": cost, "label": ("Missione: " if cost == 0 else "Missione (1 azione): ") + md.name})
	return r

func do_mission(i: int, col: String) -> bool:
	var m: int = s.orr.act[col]
	if m < 0:
		return false
	var md = BOData.MISSIONS[m]
	match md.k:
		"inventario":
			for n in range(2):
				var src := item_sources(i, "ANY", false, false)
				var k = await ch.choose(i, "Inventario Aggiornato: scegli l'oggetto da scartare (%d di 2)" % (n + 1), src)
				use_source(src[k])
		"segreti", "lista":
			var src := item_sources(i, "ESPL", false, false)
			use_source(src[0])
		"autorizzazione":
			use_source(item_sources(i, "FIRMA", false, false)[0])
		"stalin":
			use_source(item_sources(i, "INFO", false, false)[0])
		"informare":
			var src := item_sources(i, "ANY", false, false)
			var k = await ch.choose(i, "Informare gli Alleati: quale oggetto scarti a Stoccolma?", src, {"cancel": true})
			if k < 0:
				return false
			use_source(src[k])
		"falsario":
			await discard_cards_of(i, i, 3)
		"riunione":
			for j in free_list():
				add_susp(j, 1)
		"intercetta_hess", "intercetta_himmler", "prove_fort", "prove_st4":
			var r := roll_by(i, 3)
			await ch.notify("Missione: " + md.name, {"dice": r, "text": "Servono 2 o più simboli uguali (non aquila)."})
			var ok := false
			for f in ["1", "2", "3", "T"]:
				if r.count(f) >= 2:
					ok = true
			if not ok:
				log_msg("Tentativo fallito per la missione %s (%s)." % [md.name, dice_txt(r)])
				return true
		"conversazione":
			var n := 0
			for j in free_list():
				n += P(j).dossier.size()
			var r := roll_by(i, n)
			await ch.notify("Missione: " + md.name, {"dice": r, "text": "Nessuna aquila = successo."})
			if "E" in r:
				log_msg("Tentativo fallito per la missione %s." % md.name)
				return true
		"bormann":
			var n: int = placed_tels().size() + (1 if s.orr.perm != "" else 0)
			var r := roll_by(i, n)
			await ch.notify("Missione: " + md.name, {"dice": r, "text": "Servono 2 o più ⊕."})
			if r.count("T") < 2:
				log_msg("Tentativo fallito per la missione %s." % md.name)
				return true
		"reclutamento":
			var r := roll_by(i, P(i).items.size())
			await ch.notify("Missione: " + md.name, {"dice": r, "text": "Serve almeno 1 ⊕."})
			if r.count("T") < 1:
				log_msg("Tentativo fallito per la missione %s." % md.name)
				return true
	await complete_mission(col, i)
	return true

# ---------------------------------------------------------------------
# Horst Kopkow
# ---------------------------------------------------------------------
func kk_blocked(sp: String) -> bool:
	return s.mods.kk and s.kk.pos != "" and s.kk.pos == sp

func kk_no_conspire() -> bool:
	return s.mods.kk and (s.kk.nocons_until >= 0 or s.kk.nocons_stage > 0)

func kopkow_move_to(sp: String) -> void:
	var from: String = s.kk.pos
	s.kk.pos = sp
	moved.emit("KOPKOW", from if from != "" else sp, sp)
	log_msg("Horst Kopkow si sposta a %s." % spname(sp))
	upd()

func enc_img(e: int) -> String:
	return "res://assets/res/enc/n%02d.jpg" % e

func enc_reshuffle_bottom() -> void:
	if s.kk.edisc.is_empty():
		log_msg("Non ci sono carte incontro scartate.")
		return
	var c: int = s.kk.edisc.pop_front()
	s.kk.edeck.append(c)
	shuffle(s.kk.edeck)
	log_msg("Una carta incontro scartata viene rimescolata nel mazzo incontro (%d carte)." % s.kk.edeck.size())

func kopkow_target() -> String:
	var fl := free_list()
	if fl.is_empty():
		return ""
	var mx := -1
	for j in fl:
		mx = maxi(mx, P(j).susp)
	var cands: Array = fl.filter(func(j): return P(j).susp == mx)
	for j in cands:
		if P(j).space == s.kk.pos:
			return s.kk.pos
	var dd := dists_from(s.kk.pos)
	var best := 999
	var sps: Array = []
	for j in cands:
		var sp: String = P(j).space
		if not dd.has(sp):
			continue
		if dd[sp] < best:
			best = dd[sp]
			sps = [sp]
		elif dd[sp] == best and not (sp in sps):
			sps.append(sp)
	if sps.is_empty():
		return ""
	if sps.size() == 1:
		return sps[0]
	return await ch.choose_space(s.active, "Horst Kopkow: verso quale cospiratore si muove?", sps, false)

func kopkow_step() -> void:
	if not s.mods.kk or s.kk.pos == "" or s.over:
		return
	s.phase = "kopkow"
	var steps := 1
	if s.current != "" and EV[s.current].get("fx", "") == "kim" and not s.ev_ignored:
		steps = 2
	for k in range(steps):
		var target: String = await kopkow_target()
		if target == "" or target == s.kk.pos:
			break
		var dt := dists_from(target)
		var nxt := ""
		for n in neighbors(s.kk.pos):
			if dt.has(n) and dt[n] == dt[s.kk.pos] - 1:
				nxt = n
				break
		if nxt == "":
			break
		kopkow_move_to(nxt)
	await get_tree_wait()
	await kopkow_encounter()
	await enforce_limits()

## Attende che l'interfaccia abbia finito le animazioni (se il chooser lo supporta).
func get_tree_wait() -> void:
	if ch.has_method("wait_board"):
		await ch.wait_board()

func kopkow_encounter() -> void:
	var here := players_in(s.kk.pos)
	if here.is_empty():
		return
	var mx := -1
	for j in here:
		mx = maxi(mx, P(j).susp)
	if mx == 0:
		log_msg("Horst Kopkow incontra solo cospiratori con sospetto Basso: nessun incontro.")
		return
	var cands: Array = here.filter(func(j): return P(j).susp == mx)
	var j: int = cands[0]
	if cands.size() > 1:
		j = await pick_player(s.active, "Horst Kopkow: quale cospiratore pesca la carta incontro?", cands)
	if s.kk.edeck.is_empty():
		lose("Il mazzo incontro è esaurito: Horst Kopkow ha completato la sua indagine e arrestato i cospiratori.")
		return
	var e: int = s.kk.edeck.pop_front()
	log_msg("🔍 Incontro con Horst Kopkow: %s pesca «%s»." % [cname(j), BOData.ENCOUNTERS[e].name])
	await ch.notify("Incontro: " + BOData.ENCOUNTERS[e].name, {"img": enc_img(e)})
	var keep := await resolve_encounter(j, e)
	if not keep:
		s.kk.edisc.append(e)
	upd()

func nearest_unrevealed(from: String) -> Array:
	var dd := dists_from(from)
	var lst: Array = []
	for sp in s.board_items:
		for x in range(s.board_items[sp].size()):
			if not s.board_items[sp][x].rev:
				lst.append([dd.get(sp, 99), sp])
	lst.sort_custom(func(a, b): return a[0] < b[0])
	return lst

func remove_nearest_unrevealed(from: String, n: int) -> void:
	for k in range(n):
		var lst := nearest_unrevealed(from)
		if lst.is_empty():
			return
		var sp: String = lst[0][1]
		remove_tile(sp, unrevealed_idx(sp), false)
		log_msg("Un oggetto non rivelato a %s viene rimosso dal gioco." % spname(sp))

## Restituisce true se la carta resta in gioco (Fiato sul Collo).
func resolve_encounter(j: int, e: int) -> bool:
	var sp: String = P(j).space
	var present := players_in(sp)
	var solo := present.size() <= 1
	match BOData.ENCOUNTERS[e].k:
		"legame":
			if solo:
				add_susp(j, -2)
			else:
				for x in present:
					add_susp(x, -1)
		"conti":
			add_susp(j, -1 if solo else 1)
		"mormorii":
			if not solo:
				for x in present:
					add_susp(x, 1)
		"attenzione":
			move_leader("HITLER", sp)
			if not solo:
				for l in ["HIMMLER", "GOEBBELS"]:
					if s.leaders[l] != "":
						move_leader(l, sp)
		"niente":
			if s.dissent > 0:
				s.dissent = 0
				log_msg("I dadi del Dissenso vengono rimossi.")
			else:
				var src := item_sources(j, "ANY", false, false, true)
				if src.size() > 0:
					var k = await ch.choose(j, "Niente da Fare: scegli 1 oggetto da perdere.", src)
					use_source(src[k])
		"contrattempo":
			var nc: int = P(j).dossier.size()
			var opt := await safe_or_risk(j, nc >= 1, nc >= 2, "Perdi 1 carta.", "Tira un dado: ⊕ = rimescoli 1 carta incontro scartata nel mazzo; altrimenti perdi 3 carte.")
			if opt == 0:
				await discard_cards_of(j, j, 1)
			elif opt == 1:
				var f := roll1_by(j)
				await ch.notify("Corri un rischio", {"dice": [f] if f != "" else []})
				if f == "T":
					enc_reshuffle_bottom()
				elif f != "":
					await discard_cards_of(j, j, 3)
		"attivita":
			if P(j).susp < 3:
				add_susp(j, 1)
			elif P(j).dossier.size() > 0:
				await discard_cards_of(j, j, 1)
		"tempo":
			var cnt := 0
			for st in range(1, 8):
				if s.decks[st].is_empty():
					continue
				if solo and cnt >= 3:
					break
				s.ev_removed.append(s.decks[st].pop_front())
				cnt += 1
			log_msg("Rimosse senza rivelarle %d carte evento (1 per mazzo)." % cnt)
		"fallirete":
			var opt := await safe_or_risk(j, P(j).mot > mot_floor(j), P(j).susp < 3, "−1 motivazione.", "+2 sospetto (+1 se il tuo sospetto è Alto).")
			if opt == 0:
				add_mot(j, -1)
			elif opt == 1:
				add_susp(j, 1 if P(j).susp == 2 else 2)
		"cautela":
			var opt := await safe_or_risk(j, true, true, "Fino al tuo prossimo turno nessun cospiratore può Cospirare.", "Tira un dado: ⊕ = rimescoli 1 carta incontro scartata nel mazzo; altrimenti nessuno può Cospirare fino al prossimo stadio.")
			if opt == 0:
				s.kk.nocons_until = j
				log_msg("Eccesso di Cautela: Cospirare non disponibile fino al prossimo turno di %s." % cname(j))
			else:
				var f := roll1_by(j)
				await ch.notify("Corri un rischio", {"dice": [f] if f != "" else []})
				if f == "T":
					enc_reshuffle_bottom()
				elif f != "":
					s.kk.nocons_stage = s.stage
					log_msg("Eccesso di Cautela: Cospirare non disponibile fino al prossimo stadio.")
		"agnello":
			if prisoners().is_empty():
				var oth := free_list()
				oth.erase(j)
				if oth.size() > 0:
					var x: int = await pick_player(j, "Agnello Sacrificale: quale altro cospiratore va in prigione?", oth)
					arrest(x)
			else:
				set_susp(j, 3)
		"favore":
			s.kk.favore = (s.active + 1) % np()
			log_msg("Restituire il Favore: nel prossimo turno %s avrà solo 2 azioni e non potrà cospirare." % cname(s.kk.favore))
			if not solo:
				for x in present:
					add_susp(x, 1)
		"annullato":
			if count_plots(j) > 0:
				await discard_cards_of(j, j, 1, true)
			else:
				enc_reshuffle_bottom()
		"inizio":
			var n: int = P(j).dossier.size()
			while P(j).dossier.size() > 0:
				discard_card(j, 0)
			gain_cards(j, n if solo else maxi(0, n - 1))
		"scompartimento":
			var ni: int = P(j).items.size()
			var opt := await safe_or_risk(j, ni >= 1, true, "Perdi 2 oggetti (1 se ne hai solo 1).", "Tira un dado: aquila = vai in prigione; altrimenti nessun effetto.")
			if opt == 0:
				for n in range(mini(2, ni)):
					var k = await ch.choose(j, "Scompartimento Segreto: scegli l'oggetto da perdere.", item_opts(P(j).items))
					discard_item(j, k)
			else:
				var f := roll1_by(j)
				await ch.notify("Corri un rischio", {"dice": [f] if f != "" else []})
				if f == "E":
					arrest(j)
		"sventato":
			var opt := await safe_or_risk(j, nearest_unrevealed(sp).size() > 0, true, "Rimuovi dal gioco i 2 oggetti non rivelati più vicini.", "Tira un dado: ⊕ = riveli i 2 oggetti non rivelati più vicini; altrimenti rimuovi dal gioco i 4 più vicini.")
			if opt == 0:
				remove_nearest_unrevealed(sp, 2)
			else:
				var f := roll1_by(j)
				await ch.notify("Corri un rischio", {"dice": [f] if f != "" else []})
				if f == "T":
					for n in range(2):
						var lst := nearest_unrevealed(sp)
						if lst.is_empty():
							break
						await reveal_tile(lst[0][1], unrevealed_idx(lst[0][1]), -1)
				elif f != "":
					remove_nearest_unrevealed(sp, 4)
		"fiato":
			s.kk.fiato = [j] if solo else present.duplicate()
			log_msg("Fiato sul Collo: al prossimo Raid della Gestapo chi è coinvolto finisce in prigione con sospetto Alto o Estremo.")
			return true
		"documenti":
			var opt := await safe_or_risk(j, P(j).susp < 3, true, "Il tuo sospetto sale a Estremo.", "Tira un dado: aquila = vai in prigione; altrimenti nessun effetto.")
			if opt == 0:
				set_susp(j, 3)
			else:
				var f := roll1_by(j)
				await ch.notify("Corri un rischio", {"dice": [f] if f != "" else []})
				if f == "E":
					arrest(j)
	return false

## Scelta «Vai sul sicuro / Corri un rischio»: restituisce 0, 1 o -1 (nessuna opzione possibile).
func safe_or_risk(j: int, safe_ok: bool, risk_ok: bool, safe_txt: String, risk_txt: String) -> int:
	if safe_ok and not risk_ok:
		return 0
	if risk_ok and not safe_ok:
		return 1
	if not safe_ok and not risk_ok:
		log_msg("Nessuna opzione dell'incontro è applicabile.")
		return -1
	return await ch.choose(j, "%s: scegli un'opzione." % cname(j), ["VAI SUL SICURO – " + safe_txt, "CORRI UN RISCHIO – " + risk_txt])

# ---------------------------------------------------------------------
# Circolo di Kreisau
# ---------------------------------------------------------------------
func ally_def(k: String) -> Dictionary:
	for a in BOData.ALLIES:
		if a.k == k:
			return a
	return {}

func ally_idx(k: String) -> int:
	for x in range(BOData.ALLIES.size()):
		if BOData.ALLIES[x].k == k:
			return x
	return -1

func ally_img(k: String) -> String:
	return "res://assets/res/allies/a%02d.jpg" % ally_idx(k)

func ally_img_i(a: int) -> String:
	return "res://assets/res/allies/a%02d.jpg" % a

func ally_ready(k: String) -> bool:
	if not s.mods.ck:
		return false
	var a := ally_idx(k)
	for e in s.ck.circle:
		if e.a == a and not e.used:
			return true
	return false

func use_ally(k: String) -> void:
	var a := ally_idx(k)
	for e in s.ck.circle:
		if e.a == a and not e.used:
			e.used = true
			log_msg("Alleato usato: %s." % BOData.ALLIES[a].name)
			upd()
			return

func recruit(i: int) -> void:
	if s.ck.res.is_empty():
		return
	var o: Array = []
	for a in s.ck.res:
		o.append({"label": "%s – %s" % [BOData.ALLIES[a].name, BOData.ALLIES[a].text], "img": ally_img_i(a)})
	var k = await ch.choose(i, "Recluta un alleato dalla riserva di reclutamento", o)
	var a: int = s.ck.res[k]
	s.ck.res.remove_at(k)
	if s.ck.circle.size() >= 5:
		var o2: Array = []
		for e in s.ck.circle:
			o2.append({"label": BOData.ALLIES[e.a].name + (" (usato)" if e.used else ""), "img": ally_img_i(e.a)})
		var d = await ch.choose(i, "Il Circolo è al completo: scegli un alleato reclutato da scartare", o2)
		log_msg("%s lascia il Circolo di Kreisau." % BOData.ALLIES[s.ck.circle[d].a].name)
		s.ck.circle.remove_at(d)
	s.ck.circle.append({"a": a, "used": false})
	log_msg("★ %s entra nel Circolo di Kreisau (%d alleati)." % [BOData.ALLIES[a].name, s.ck.circle.size()])
	if s.ck.apile.size() > 0:
		s.ck.res.append(s.ck.apile.pop_front())
	upd()

func reichwein_offer(i: int, r: Array) -> Array:
	var k = await ch.choose(i, "Risultato: %s. Vuoi usare l'alleata Rosemarie Reichwein per girare un'aquila su un'altra faccia?" % dice_txt(r), ["No", "Sì, usa Rosemarie Reichwein"], {"dice": r})
	if k == 0:
		return r
	use_ally("reichwein")
	var faces := ["1", "2", "3", "T"]
	var fo: Array = []
	for f in faces:
		fo.append(FACE_TXT[f])
	var fc = await ch.choose(i, "Su quale faccia giri il dado?", fo, {"dice": r})
	r[r.find("E")] = faces[fc]
	return r

func ally_actions(i: int) -> Array:
	var r: Array = []
	var sp: String = P(i).space
	for e in s.ck.circle:
		if e.used:
			continue
		var a = BOData.ALLIES[e.a]
		var ok := false
		match a.k:
			"haubach":
				ok = not s.turn.skip_events
			"leber":
				ok = free_list().any(func(j): return P(j).susp > susp_floor(j))
			"gerstenmaier":
				ok = free_list().any(func(j): return P(j).mot < mot_cap(j))
			"pyorck", "einsiedel":
				ok = true
			"freya":
				ok = s.board_items.keys().any(func(x): return unrevealed_idx(x) >= 0)
			"trotha":
				ok = s.board_items.size() > 0
			"trott":
				ok = (sp == "ZURIGO" or sp == "STOCCOLMA") and item_sources(i, "ANY", false, false).size() > 0
			"peters":
				ok = s.cdeck.size() + s.cdiscard.size() > 0
		if ok:
			r.append({"id": "exp", "key": "ally", "ally": a.k, "cost": 0, "label": "⚡ Alleato: %s" % a.name, "tip": a.text})
	return r

func do_ally(i: int, k: String) -> bool:
	match k:
		"haubach":
			s.turn.skip_events = true
			log_msg("Theodor Haubach: in questo turno la carta evento non viene risolta.")
		"leber":
			var c := free_list().filter(func(j): return P(j).susp > susp_floor(j))
			for n in range(2):
				if c.is_empty():
					break
				var j: int = await pick_player(i, "Julius Leber: −1 sospetto a quale cospiratore? (%d di 2)" % (n + 1), c)
				add_susp(j, -1)
				c.erase(j)
		"gerstenmaier":
			var c := free_list().filter(func(j): return P(j).mot < mot_cap(j))
			for n in range(2):
				if c.is_empty():
					break
				var j: int = await pick_player(i, "Eugen Gerstenmaier: +1 motivazione a quale cospiratore? (%d di 2)" % (n + 1), c)
				add_mot(j, 1)
				c.erase(j)
		"pyorck":
			var c := free_list()
			for n in range(3):
				if c.is_empty():
					break
				var o: Array = ["Basta così"]
				for j in c:
					o.append("Muovi %s (a %s)" % [cname(j), spname(P(j).space)])
				var x = await ch.choose(i, "Peter Yorck: muovi fino a 3 cospiratori (%d di 3)" % (n + 1), o)
				if x == 0:
					break
				var j: int = c[x - 1]
				var t: Array = []
				for sp in BOData.SPACES:
					if valid_for(j, sp) and sp != P(j).space:
						t.append(sp)
				var dest = await ch.choose_space(i, "Dove muovere %s?" % cname(j), t, false)
				move_consp(j, dest)
				c.erase(j)
		"freya":
			var sps: Array = s.board_items.keys().filter(func(x): return unrevealed_idx(x) >= 0)
			var sp = await ch.choose_space(i, "Freya von Moltke: in quale casella riveli gli oggetti?", sps, false)
			while unrevealed_idx(sp) >= 0 and not s.over:
				var x := unrevealed_idx(sp)
				if s.board_items[sp][x].t == "RAIDT":
					var q = await ch.choose(i, "Freya von Moltke rivela una tessera Raid della Gestapo a %s. Vuoi ignorarla?" % spname(sp), ["Sì, ignorala (viene rimossa)", "No, risolvi il Raid"], {"imgs": [item_img("RAIDT")]})
					if q == 0:
						remove_tile(sp, x, false)
						log_msg("Freya von Moltke neutralizza una tessera Raid della Gestapo.")
						continue
				await reveal_tile(sp, x, i)
		"trotha":
			for n in range(2):
				if s.board_items.is_empty():
					break
				var sp = await ch.choose_space(i, "Margarete von Trotha: da quale casella raccogli l'oggetto in cima? (%d di 2)" % (n + 1), s.board_items.keys(), false)
				await take_tile(i, sp, 0, true)
		"trott":
			var src := item_sources(i, "ANY", false, false)
			var x = await ch.choose(i, "Adam von Trott: quale oggetto consegni?", src)
			use_source(src[x])
			add_ms(-1)
		"peters":
			var drawn: Array = []
			for n in range(5):
				var c := draw_ccard()
				if c != "":
					drawn.append(c)
			if drawn.is_empty():
				return true
			var x = await ch.choose(i, "Hans Peters: scegli la carta da conservare (le altre tornano nel mazzo)", card_opts(drawn))
			P(i).dossier.append(drawn[x])
			log_msg("%s conserva %s." % [cname(i), cardname(drawn[x])])
			drawn.remove_at(x)
			s.cdeck.append_array(drawn)
			shuffle(s.cdeck)
		"einsiedel":
			gain_cards(i, 3)
	use_ally(k)
	return true

# ---------------------------------------------------------------------
# Azioni dell'espansione
# ---------------------------------------------------------------------
func exp_actions(i: int) -> Array:
	var r: Array = []
	var sp: String = P(i).space
	var blocked := kk_blocked(sp)
	if s.mods.or:
		if BOData.SPACES[sp].deliver.size() > 0 and not s.orr.tok.has(sp) and s.orr.perm != sp and not blocked:
			if tel_supply_colors().size() > 0 or s.orr.sup.V > 0:
				r.append({"id": "exp", "key": "collocare", "cost": 1, "label": "Collocare telescrivente/volantino"})
		r.append_array(mission_actions(i))
		if s.orr.hideout_have and all_illegal_cards().size() > (1 if s.orr.hideout != "" else 0):
			r.append({"id": "exp", "key": "hideout", "cost": 0, "label": "Sposta il nascondiglio"})
	if s.mods.kk and s.kk.pos != "":
		r.append({"id": "exp", "key": "diversivo", "cost": 1, "label": "Diversivo (muovi Kopkow)"})
	if s.mods.ck and not blocked:
		if unrevealed_idx(sp) >= 0:
			r.append({"id": "exp", "key": "svelare", "cost": 1, "label": "Svelare (rivela entrambi gli oggetti)"})
		if s.board_items.has(sp) and s.ck.res.size() > 0:
			for tl in s.board_items[sp]:
				if tl.t == "ALLEATO" and tl.rev:
					r.append({"id": "exp", "key": "reclutare", "cost": 1, "label": "Reclutare un alleato"})
					break
	if s.mods.ck:
		r.append_array(ally_actions(i))
	return r

func do_exp_action(i: int, a: Dictionary) -> bool:
	var sp: String = P(i).space
	match a.key:
		"collocare":
			var o: Array = []
			var codes: Array = []
			for c in tel_supply_colors():
				o.append({"label": "Telescrivente " + BOData.TEL_NAMES[c] + (" (missione attiva)" if s.orr.act[c] >= 0 else " (rivela una missione)"), "img": "res://assets/res/tokens/%s.png" % BOData.TEL_IMG[c]})
				codes.append(c)
			if s.orr.sup.V > 0:
				o.append({"label": "Volantino", "img": "res://assets/res/tokens/VOL.png"})
				codes.append("V")
			var k = await ch.choose(i, "Collocare: quale segnalino vuoi mettere a %s? (tiro di 1 dado: con un'aquila +1 sospetto e nessun segnalino)" % spname(sp), o, {"cancel": true})
			if k < 0:
				return false
			var f := roll1_by(i)
			await ch.notify("Collocare", {"dice": [f] if f != "" else []})
			if f == "E":
				add_susp(i, 1)
				log_msg("%s non riesce a collocare il segnalino." % cname(i))
			elif f != "":
				await place_token(i, sp, codes[k])
		"mission":
			return await do_mission(i, a.col)
		"comb_take":
			add_susp(i, 2)
			P(i).items.append("COMB")
			s.orr.comb_sup -= 1
			s.orr.comb[a.col] = i
			log_msg("%s prende un Combattente della Resistenza a %s." % [cname(i), spname(sp)])
		"goebbels_arrest":
			log_msg("%s si fa arrestare per la missione Goebbels Informato." % cname(i))
			arrest(i)
		"hideout":
			await place_hideout(i)
		"diversivo":
			var f := roll1_by(i)
			await ch.notify("Diversivo", {"dice": [f] if f != "" else []})
			if f == "E":
				add_susp(i, 1)
			elif f != "":
				var dest = await ch.choose_space(i, "Diversivo: dove sposti Horst Kopkow (1 casella)?", neighbors(s.kk.pos), false)
				kopkow_move_to(dest)
		"svelare":
			var f := roll1_by(i)
			await ch.notify("Svelare", {"dice": [f] if f != "" else []})
			if f == "E":
				add_susp(i, 1)
			elif f != "":
				while unrevealed_idx(sp) >= 0 and not s.over:
					await reveal_tile(sp, unrevealed_idx(sp), i)
		"reclutare":
			var f := roll1_by(i)
			await ch.notify("Reclutare", {"dice": [f] if f != "" else [], "text": "Con 1, 2 o 3 il reclutamento riesce."})
			if f in ["1", "2", "3"]:
				for x in range(s.board_items[sp].size()):
					if s.board_items[sp][x].t == "ALLEATO" and s.board_items[sp][x].rev:
						remove_tile(sp, x, false)
						break
				await recruit(i)
			else:
				log_msg("%s non riesce a reclutare l'alleato." % cname(i))
		"ally":
			return await do_ally(i, a.ally)
	upd()
	return true

# ---------------------------------------------------------------------
# Eventi dell'espansione
# ---------------------------------------------------------------------
func resolve_exp_event(fx: String) -> void:
	if fx == "kim":
		log_msg("Alla fine del turno Horst Kopkow si muove fino a 2 caselle.")
	elif fx == "msgint":
		if s.kk.edeck.size() > 0:
			s.kk.edisc.append(s.kk.edeck.pop_front())
			log_msg("Viene scartata la prima carta del mazzo incontro (%d rimaste)." % s.kk.edeck.size())
	elif fx == "allarr":
		var o: Array = []
		var codes: Array = []
		for x in range(s.ck.circle.size()):
			var e = s.ck.circle[x]
			if not e.used:
				o.append({"label": "Gira (usa senza effetto) %s" % BOData.ALLIES[e.a].name, "img": ally_img_i(e.a)})
				codes.append([0, x])
			else:
				o.append({"label": "Rimuovi dal Circolo %s (già usato)" % BOData.ALLIES[e.a].name, "img": ally_img_i(e.a)})
				codes.append([1, x])
		if o.is_empty():
			log_msg("Nessun alleato reclutato: l'evento non ha effetto.")
			return
		var k = await ch.choose(s.active, "Alleato Arrestato: scegli un alleato da girare oppure uno già usato da rimuovere.", o)
		var x: int = codes[k][1]
		if codes[k][0] == 0:
			s.ck.circle[x].used = true
			log_msg("%s viene girato sul lato usato." % BOData.ALLIES[s.ck.circle[x].a].name)
		else:
			log_msg("%s viene rimosso dal Circolo." % BOData.ALLIES[s.ck.circle[x].a].name)
			s.ck.circle.remove_at(x)
	elif fx.begins_with("telscop:"):
		var l: String = fx.substr(8)
		var lp: String = s.leaders.get(l, "")
		var tels := placed_tels()
		if lp == "" or tels.is_empty():
			log_msg("Nessuna telescrivente da rimuovere.")
			return
		var dd := dists_from(lp)
		var best := 999
		var c: Array = []
		for sp in tels:
			var d: int = dd.get(sp, 99)
			if d < best:
				best = d
				c = [sp]
			elif d == best:
				c.append(sp)
		var sp: String = c[0]
		if c.size() > 1:
			sp = await ch.choose_space(s.active, "Quale telescrivente viene scoperta?", c, false)
		var col: String = s.orr.tok[sp]
		s.orr.tok.erase(sp)
		s.orr.sup[col] += 1
		log_msg("La telescrivente %s a %s viene scoperta e rimossa." % [BOData.TEL_NAMES[col], spname(sp)])
		if s.orr.act[col] >= 0 and tels_of(col).is_empty() and s.orr.perm == "":
			discard_mission(col, "tutte le telescriventi %s sono state rimosse" % BOData.TEL_NAMES[col])
	upd()
