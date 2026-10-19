extends Control
class_name BOBoardView
## Disegno del tabellone e delle pedine.

signal space_clicked(sp: String)
signal event_clicked(eid: String)
signal item_clicked(sp: String)

const SIZE := 1080.0
const K := SIZE / 2000.0
const MS_Y := {7: 1490, 6: 1558, 5: 1625, 4: 1692, 3: 1760, 2: 1827}
const DISSENT := [Vector2(105, 152), Vector2(187, 152), Vector2(268, 152)]
const EVENT_RECT := Rect2(1600, 542, 228, 321)
const KEY_RECT := Rect2(1842, 575, 156, 219)
const INTERR_SLOT := Rect2(0, 430, 72, 375)
const CONSP_SLOT := Rect2(0, 898, 72, 360)
const DECK_X := [175, 446, 724, 1003, 1281, 1557, 1832]

var game: BOGame
var highlights: Array = []
var soft: Array = []
var hover := ""
var t := 0.0
var item_hot: Array = []        # caselle con oggetto cliccabile
var plot_ready := false         # c'è un complotto tentabile: Hitler lampeggia
# animazioni: token -> {"pos": Vector2, "queue": [Vector2...], "speed": float}
var anim := {}
const SEG_TIME := 0.2

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "

func _process(delta: float) -> void:
	t += delta
	for k in anim:
		var a: Dictionary = anim[k]
		if a.queue.is_empty():
			continue
		var target: Vector2 = a.queue[0]
		var step: float = a.speed * delta
		var d: float = a.pos.distance_to(target)
		if d <= step:
			a.pos = target
			a.queue.pop_front()
		else:
			a.pos += (target - a.pos) / d * step
	queue_redraw()

func is_busy() -> bool:
	for k in anim:
		if not anim[k].queue.is_empty():
			return true
	return false

func _item_rect(sp: String) -> Rect2:
	var c := bp(BOData.SPACES[sp].pos)
	if game and game.s.board_items.has(sp) and game.s.board_items[sp].size() > 1:
		return Rect2(c - Vector2(28, 26), Vector2(56, 52))
	return Rect2(c - Vector2(23, 23), Vector2(46, 46))

func _space_center(sp: String) -> Vector2:
	if sp == "PRISON":
		return bp(BOData.PRISON_POS)
	return bp(BOData.SPACES[sp].pos)

## Chiamato dal segnale BOGame.moved: accoda l'animazione lungo il percorso.
func on_moved(token: String, from: String, to: String) -> void:
	if game == null:
		return
	var start: Vector2 = anim[token].pos if anim.has(token) else _token_target(token, from)
	if not anim.has(token):
		anim[token] = {"pos": start, "queue": [], "speed": 300.0}
	var a: Dictionary = anim[token]
	var pts: Array = []
	if from != "PRISON" and to != "PRISON" and BOData.SPACES.has(from) and BOData.SPACES.has(to) and (token.begins_with("P") or token == "KOPKOW"):
		var path := _path(from, to)
		if path.size() >= 2 and path.size() <= 6:
			for k in range(1, path.size() - 1):
				pts.append(_space_center(path[k]) + Vector2(0, -24))
	pts.append(_token_target(token, to))
	a.queue.append_array(pts)
	var total: float = a.pos.distance_to(pts[0])
	for k in range(1, pts.size()):
		total += pts[k - 1].distance_to(pts[k])
	var segs: int = maxi(1, pts.size())
	a.speed = maxf(260.0, total / (SEG_TIME * segs + 0.25))

func _path(from: String, to: String) -> Array:
	var prev := {from: ""}
	var q: Array = [from]
	while q.size() > 0:
		var c: String = q.pop_front()
		if c == to:
			break
		for n in game.neighbors(c):
			if not prev.has(n):
				prev[n] = c
				q.append(n)
	if not prev.has(to):
		return []
	var path: Array = [to]
	var c: String = to
	while prev[c] != "":
		c = prev[c]
		path.push_front(c)
	return path

## Posizione di riposo di un token in base allo stato attuale.
func _token_target(token: String, sp: String = "") -> Vector2:
	var s: Dictionary = game.s
	if token == "KOPKOW":
		if sp == "":
			sp = s.kk.pos
		return _space_center(sp) + Vector2(0, 12)
	if token.begins_with("P"):
		var i := int(token.substr(1))
		if sp == "":
			sp = game.P(i).space
		var here: Array = []
		for j in range(game.np()):
			if game.P(j).space == sp:
				here.append(j)
		var k: int = maxi(here.find(i), 0)
		var n: int = maxi(here.size(), 1)
		if sp == "PRISON":
			return bp(BOData.PRISON_POS) + Vector2(-36 + k * 24, -6 + (k % 2) * 12)
		var c := _space_center(sp)
		if n == 1:
			return c + Vector2(0, -30)
		var ang: float = lerpf(-PI * 0.95, -PI * 0.05, float(k) / float(n - 1))
		var rad: float = 36.0 if n <= 3 else 40.0
		return c + Vector2(cos(ang) * rad, sin(ang) * rad * 0.85 - 4)
	else:
		if sp == "":
			sp = s.leaders[token]
		var c := _space_center(sp)
		var ls: Array = []
		for l in BOData.LEADERS:
			if s.leaders[l] == sp:
				ls.append(l)
		var k: int = maxi(ls.find(token), 0)
		return c + Vector2(0, 41 + k * 17)

func _token_pos(token: String) -> Vector2:
	var target := _token_target(token)
	if not anim.has(token):
		anim[token] = {"pos": target, "queue": [], "speed": 300.0}
	var a: Dictionary = anim[token]
	if a.queue.is_empty():
		# riposo (o riallineamento dopo cambi di disposizione)
		if a.pos.distance_to(target) > 0.5:
			a.pos = a.pos.lerp(target, 0.25)
		else:
			a.pos = target
	return a.pos

func _is_moving(token: String) -> bool:
	return anim.has(token) and not anim[token].queue.is_empty()



func bp(v: Vector2) -> Vector2:
	return v * K

func space_at(p: Vector2) -> String:
	var best := ""
	var bd := 46.0
	for sp in BOData.SPACES:
		var d: float = bp(BOData.SPACES[sp].pos).distance_to(p)
		if d < bd:
			bd = d
			best = sp
	return best

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var sp := space_at(ev.position)
		if sp != hover:
			hover = sp
			queue_redraw()
		var clickable := sp != "" and (sp in highlights or sp in soft)
		for isp in item_hot:
			if _item_rect(isp).grow(4).has_point(ev.position):
				clickable = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable or _in_event(ev.position) else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var eid := _event_at(ev.position)
		if eid != "":
			event_clicked.emit(eid)
			return
		for sp in item_hot:
			if _item_rect(sp).grow(4).has_point(ev.position):
				item_clicked.emit(sp)
				return
		var sp := space_at(ev.position)
		if sp != "" and (sp in highlights or sp in soft):
			space_clicked.emit(sp)

func _in_event(p: Vector2) -> bool:
	return _event_at(p) != ""

func _event_at(p: Vector2) -> String:
	if game == null or game.s.is_empty():
		return ""
	if game.s.current != "" and Rect2(EVENT_RECT.position * K, EVENT_RECT.size * K).has_point(p):
		return game.s.current
	if game.s.key != "" and Rect2(KEY_RECT.position * K, KEY_RECT.size * K).has_point(p):
		return game.s.key
	return ""

func _get_tooltip(at: Vector2) -> String:
	if game == null or game.s.is_empty():
		return ""
	var sp := space_at(at)
	if Rect2(INTERR_SLOT.position * K, INTERR_SLOT.size * K).grow(10).has_point(at):
		return "Mazzo interrogatorio: %d carte" % game.s.ideck.size()
	if Rect2(CONSP_SLOT.position * K, CONSP_SLOT.size * K).grow(10).has_point(at):
		return "Mazzo cospiratore: %d carte\nScarti cospiratore: %d\nOggetti scartati: %d" % [game.s.cdeck.size(), game.s.cdiscard.size(), game.s.item_discard.size()]
	if game.s.key != "" and Rect2(KEY_RECT.position * K, KEY_RECT.size * K).has_point(at):
		return "Evento chiave: %s (clicca per ingrandire)" % game.EV[game.s.key].name
	if sp == "":
		return ""
	var d = BOData.SPACES[sp]
	var lines: Array = []
	lines.append("%s  –  %s" % [d.name, ("Berlino" if d.stage == 0 else "Stadio %d" % d.stage)])
	var tags: Array = []
	if d.fort:
		tags.append("fortificata")
	if d.no7:
		tags.append("inaccessibile nello Stadio 7")
	if not game.valid(sp):
		tags.append("non ancora accessibile")
	if tags.size() > 0:
		lines.append("(" + ", ".join(tags) + ")")
	if d.has("enter"):
		var e = d.enter
		var parts: Array = []
		if e.has("mot"):
			parts.append("+%d motivazione" % e.mot)
		if e.has("susp"):
			parts.append("%+d sospetto" % e.susp)
		if e.has("ms"):
			parts.append("+%d Supporto Militare" % e.ms)
		lines.append("Entrando: " + ", ".join(parts))
	if d.deliver.size() > 0:
		var dv: Array = d.deliver
		var it: String = "un oggetto qualsiasi" if dv[2] == "ANY" else BOData.ITEM_NAMES[dv[2]]
		var cond := ""
		match dv[3]:
			"deputy":
				cond = "se è presente un delegato, "
			"hitler":
				cond = "se è presente Hitler, "
			"stage1":
				cond = "se è lo Stadio 1, "
			"stage2":
				cond = "se è lo Stadio 2, "
			"Abwehr", "Civile", "Wehrmacht":
				cond = "se sei %s, " % dv[3]
		var eff := "-%d sospetto (solo tu)" % dv[1] if dv[0] == "solo" else "-%d sospetto (distribuito)" % dv[1]
		lines.append("Consegna: %s%s per %s" % [cond, eff, it])
		if game.s.board_items.has(sp):
			var names: Array = []
			for bi in game.s.board_items[sp]:
				names.append(BOData.ITEM_NAMES[bi.t] if bi.rev else "coperto")
			lines.append("Oggetti sulla casella: " + ", ".join(names))
		else:
			lines.append("Oggetti rimossi: consegna possibile.")
	if game.s.mods.or and game.s.orr.tok.has(sp):
		var col: String = game.s.orr.tok[sp]
		lines.append("Segnalino: " + ("volantino" if col == "V" else "telescrivente " + BOData.TEL_NAMES[col]))
	if game.s.mods.or and game.s.orr.perm == sp:
		lines.append("Telescrivente permanente")
	if game.kk_blocked(sp):
		lines.append("HORST KOPKOW: casella bloccata (niente oggetti, consegne o azioni della casella)")
	var who: Array = []
	for l in game.leaders_in(sp):
		who.append(BOData.LEADER_NAMES[l])
	for i in game.players_in(sp):
		who.append(game.cname(i))
	if who.size() > 0:
		lines.append("Presenti: " + ", ".join(who))
	return "\n".join(lines)

func _draw() -> void:
	draw_texture_rect(UI.tex("res://assets/board.jpg"), Rect2(0, 0, SIZE, SIZE), false)
	if game == null or game.s.is_empty():
		return
	var s: Dictionary = game.s
	var fnt := UI.font("head")
	# spazi non accessibili: velo scuro
	for sp in BOData.SPACES:
		if not game.valid(sp):
			draw_circle(bp(BOData.SPACES[sp].pos), 41, Color(0, 0, 0, 0.45))
	# mazzi evento: conteggi
	for st in range(1, 8):
		var x: float = DECK_X[st - 1] * K
		var n: int = s.decks[st].size()
		var col := UI.GOLD if st == s.stage else Color(1, 1, 1, 0.75)
		var r := Rect2(x - 38, 2, 76, 22)
		draw_rect(r, Color(0, 0, 0, 0.72))
		if st == s.stage:
			draw_rect(r, UI.GOLD, false, 2)
		draw_string(fnt, Vector2(x - 36, 19), "St.%d: %d" % [st, n], HORIZONTAL_ALIGNMENT_CENTER, 72, 14, col)
	# evidenziazioni
	for sp in soft:
		var c := bp(BOData.SPACES[sp].pos)
		draw_circle(c, 40, Color(1, 0.9, 0.5, 0.16))
		draw_arc(c, 41, 0, TAU, 48, Color(1, 0.9, 0.5, 0.55), 2.0, true)
	for sp in highlights:
		var c := bp(BOData.SPACES[sp].pos)
		var a := 0.55 + 0.35 * sin(t * 5.0)
		draw_circle(c, 40, Color(1, 0.8, 0.2, 0.18))
		draw_arc(c, 42, 0, TAU, 48, Color(1, 0.8, 0.2, a), 4.0, true)
	if hover != "" and (hover in highlights or hover in soft):
		draw_arc(bp(BOData.SPACES[hover].pos), 44, 0, TAU, 48, Color.WHITE, 3.0, true)
	# oggetti (pile di 1 o 2 tessere)
	for sp in s.board_items:
		var c := bp(BOData.SPACES[sp].pos)
		var arr: Array = s.board_items[sp]
		var nn := arr.size()
		for x in range(nn - 1, -1, -1):
			var bi = arr[x]
			var off := Vector2.ZERO if nn == 1 else Vector2(-8 + x * 16, -6 + x * 12)
			var sz := 46.0 if nn == 1 else 38.0
			var p := "res://assets/items/%s.png" % (bi.t if bi.rev else "BACK")
			var rr := Rect2(c + off - Vector2(sz / 2, sz / 2), Vector2(sz, sz))
			draw_rect(Rect2(rr.position + Vector2(2, 3), rr.size), Color(0, 0, 0, 0.5))
			draw_texture_rect(UI.tex(p), rr, false)
		var r := _item_rect(sp)
		if sp in item_hot:
			var a := 0.6 + 0.4 * sin(t * 6.0)
			draw_rect(r.grow(3), Color(0.35, 1.0, 0.45, a), false, 3)
			draw_rect(r.grow(7), Color(0.35, 1.0, 0.45, a * 0.35), false, 3)
	# Supporto Militare
	var my: float = MS_Y.get(s.ms, 1827) * K
	var mc := Vector2(1367 * K, my)
	draw_rect(Rect2(mc - Vector2(15, 15) + Vector2(2, 3), Vector2(30, 30)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(mc - Vector2(15, 15), Vector2(30, 30)), Color("c62a1f"))
	draw_rect(Rect2(mc - Vector2(15, 15), Vector2(30, 30)), Color("ffd0c0"), false, 2)
	# marcatore valore di partenza
	var sy: float = MS_Y.get(s.ms_start, 1827) * K
	draw_string(fnt, Vector2(1290 * K, sy + 6), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GOLD)
	# Dissenso
	for k in range(3):
		var c := bp(DISSENT[k])
		if s.dissent_off:
			draw_line(c - Vector2(14, 14), c + Vector2(14, 14), UI.RED, 4)
			draw_line(c + Vector2(-14, 14), c + Vector2(14, -14), UI.RED, 4)
		elif k < s.dissent:
			draw_texture_rect(UI.tex(UI.face_path("T")), Rect2(c - Vector2(18, 18), Vector2(36, 36)), false)
	# segnalini dell'Orchestra Rossa
	if s.mods.or:
		for sp in s.orr.tok:
			var c := bp(BOData.SPACES[sp].pos) + Vector2(31, 16)
			draw_circle(c + Vector2(1, 2), 14, Color(0, 0, 0, 0.5))
			draw_texture_rect(UI.tex("res://assets/res/tokens/%s.png" % BOData.TEL_IMG[s.orr.tok[sp]]), Rect2(c - Vector2(14, 14), Vector2(28, 28)), false)
		if s.orr.perm != "":
			var c := bp(BOData.SPACES[s.orr.perm].pos) + Vector2(-31, 16)
			draw_circle(c + Vector2(1, 2), 14, Color(0, 0, 0, 0.5))
			draw_texture_rect(UI.tex("res://assets/res/tokens/TEL_P.png"), Rect2(c - Vector2(14, 14), Vector2(28, 28)), false)
	# evento attuale
	if s.current != "":
		var r := Rect2(EVENT_RECT.position * K, EVENT_RECT.size * K)
		draw_texture_rect(UI.tex(game.eimg(s.current)), r, false)
		draw_rect(r, UI.GOLD, false, 2)
	if s.key != "":
		var kr := Rect2(KEY_RECT.position * K, KEY_RECT.size * K)
		draw_rect(Rect2(kr.position + Vector2(2, 3), kr.size), Color(0, 0, 0, 0.5))
		draw_texture_rect(UI.tex(game.eimg(s.key)), kr, false)
		draw_rect(kr, Color("e8b84a"), false, 2)
	# conteggi dei mazzi sugli spazi del tabellone
	_deck_badge(INTERR_SLOT, "%d" % s.ideck.size(), "carte", "")
	_deck_badge(CONSP_SLOT, "%d" % s.cdeck.size(), "carte", "scarti %d\nogg. scart. %d" % [s.cdiscard.size(), s.item_discard.size()])
	# leader (prima quelli fermi, poi quelli in movimento sopra)
	var order: Array = []
	for l in BOData.LEADERS:
		if s.leaders[l] != "":
			order.append(l)
	order.sort_custom(func(a, b): return int(_is_moving(a)) < int(_is_moving(b)))
	for l in order:
		var c := _token_pos(l)
		var mv := _is_moving(l)
		var sz := Vector2(80, 27) * (1.25 if mv else 1.0)
		var r := Rect2(c - Vector2(sz.x / 2, sz.y / 2), sz)
		if mv:
			draw_rect(r.grow(5), Color(1, 0.85, 0.3, 0.55))
		if l == "HITLER" and plot_ready:
			draw_rect(r.grow(3 + 2 * sin(t * 6.0)), Color(0.9, 0.15, 0.1, 0.8), false, 3)
		draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0, 0, 0, 0.55))
		draw_texture_rect(UI.tex("res://assets/leaders/%s.png" % l), r, false)
	# Horst Kopkow
	if s.mods.kk and s.kk.pos != "":
		var c := _token_pos("KOPKOW")
		var mv := _is_moving("KOPKOW")
		var sz := Vector2(74, 31) * (1.25 if mv else 1.0)
		var r := Rect2(c - sz / 2, sz)
		if mv:
			draw_rect(r.grow(5), Color(1, 0.85, 0.3, 0.55))
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.6))
		draw_texture_rect(UI.tex("res://assets/res/tokens/KOPKOW.png"), r, false)
	# pedine con il volto del cospiratore
	var porder: Array = []
	for i in range(game.np()):
		porder.append(i)
	porder.sort_custom(func(a, b): return int(_is_moving("P%d" % a)) < int(_is_moving("P%d" % b)))
	for i in porder:
		var p: Dictionary = game.P(i)
		var key := "P%d" % i
		var base := _token_pos(key)
		var mv := _is_moving(key)
		var rad := 21.0 if mv else 17.0
		if p.prison:
			rad = 12.0
		var col: Color = UI.PCOLORS[i % UI.PCOLORS.size()]
		if mv:
			draw_circle(base, rad + 9, Color(1, 0.85, 0.3, 0.35))
			draw_arc(base, rad + 7, 0, TAU, 40, Color(1, 0.9, 0.5, 0.9), 2.5, true)
		elif i == s.active and not s.over:
			draw_circle(base, rad + 5 + 2 * sin(t * 4.0), Color(1, 0.85, 0.3, 0.5))
		draw_circle(base + Vector2(2, 3), rad + 1, Color(0, 0, 0, 0.6))
		draw_circle(base, rad + 1, col)
		draw_texture_rect(UI.tex("res://assets/faces/f%02d.png" % p.cid), Rect2(base - Vector2(rad - 2, rad - 2), Vector2(rad * 2 - 4, rad * 2 - 4)), false, Color(0.75, 0.6, 0.6) if p.prison else Color.WHITE)
		draw_arc(base, rad, 0, TAU, 40, col, 3.5, true)
		if mv:
			var nm: String = BOData.CONSPIRATORS[p.cid].name.split(" ")[-1]
			var tw := fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var lr := Rect2(base + Vector2(-tw / 2 - 5, rad + 4), Vector2(tw + 10, 20))
			draw_rect(lr, Color(0, 0, 0, 0.75))
			draw_string(fnt, lr.position + Vector2(5, 15), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.3))

func _deck_badge(slot: Rect2, big: String, small: String, extra: String) -> void:
	var fnt := UI.font("head")
	var c := (slot.position + slot.size / 2) * K
	var lines: Array = extra.split("\n") if extra != "" else []
	var h := 52.0 + lines.size() * 15
	var r := Rect2(3, c.y - h / 2, 60, h)
	draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.5))
	draw_rect(r, Color(0.08, 0.06, 0.05, 0.9))
	draw_rect(r, UI.GOLD.darkened(0.2), false, 1.5)
	draw_string(fnt, Vector2(r.position.x, r.position.y + 30), big, HORIZONTAL_ALIGNMENT_CENTER, 60, 28, UI.GOLD)
	draw_string(UI.font("head2"), Vector2(r.position.x, r.position.y + 46), small, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, UI.TEXT)
	for k in range(lines.size()):
		draw_string(UI.font("head2"), Vector2(r.position.x, r.position.y + 61 + k * 15), lines[k], HORIZONTAL_ALIGNMENT_CENTER, 60, 11, UI.MUTED)
