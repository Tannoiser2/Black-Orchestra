extends Control
class_name BOExpBoards
## Plance dell'espansione «La Resistenza» disegnate con carte e segnalini nelle loro posizioni.

signal zoom_requested(path: String)

var game: BOGame
var kind := ""          # "or", "kk", "ck"
var sc := 1.0
var hot: Array = []     # [Rect2, testo tooltip, immagine da ingrandire]

const RES_SIZE := Vector2(1669, 718)
const IND_SIZE := Vector2(1547, 266)
const ALL_SIZE := Vector2(1313, 1270)
const COL_X := {"A": [20, 510], "R": [578, 1095], "G": [1150, 1645]}
const VOL_POS := [Vector2(1100, 320), Vector2(1100, 505), Vector2(1240, 415), Vector2(1375, 320), Vector2(1375, 505)]
const ALLY_ROWS := [116, 348, 580, 812, 1044]

func setup(g: BOGame, k: String, width: float) -> void:
	game = g
	kind = k
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	match kind:
		"or":
			sc = width / RES_SIZE.x
			custom_minimum_size = Vector2(width, 275 + RES_SIZE.y * sc)
		"kk":
			sc = width / IND_SIZE.x
			custom_minimum_size = Vector2(width, IND_SIZE.y * sc + 190)
		"ck":
			sc = 880.0 / ALL_SIZE.y
			custom_minimum_size = Vector2(250 + ALL_SIZE.x * sc, ALL_SIZE.y * sc + 10)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for h in hot:
			if h[0].has_point(ev.position) and h[2] != "":
				zoom_requested.emit(h[2])
				accept_event()
				return

func _get_tooltip(at: Vector2) -> String:
	for h in hot:
		if h[0].has_point(at):
			return h[1]
	return ""

func _tex(p: String) -> Texture2D:
	return UI.tex(p)

func _circle_tok(c: Vector2, r: float, img: String) -> void:
	draw_circle(c + Vector2(2, 3), r, Color(0, 0, 0, 0.45))
	draw_texture_rect(_tex(img), Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), false)

func _count_badge(p: Vector2, text: String) -> void:
	var f := UI.font("head")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 16
	var r := Rect2(p - Vector2(w / 2, 14), Vector2(w, 28))
	draw_rect(r, Color(0.08, 0.06, 0.05, 0.9))
	draw_rect(r, UI.GOLD, false, 1.5)
	draw_string(f, r.position + Vector2(8, 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.GOLD)

func _draw() -> void:
	hot.clear()
	if game == null:
		return
	match kind:
		"or":
			_draw_or()
		"kk":
			_draw_kk()
		"ck":
			_draw_ck()

# ---------------------------------------------------------------------
func _draw_or() -> void:
	var s: Dictionary = game.s
	var o := Vector2(0, 275)
	var b := func(v: Vector2) -> Vector2: return o + v * sc
	# carte missione sopra le colonne colorate
	for col in BOData.TEL_COLORS:
		var x0: float = COL_X[col][0] * sc
		var x1: float = COL_X[col][1] * sc
		var w := x1 - x0
		var h := w * 400.0 / 560.0
		var r := Rect2(x0, 268 - h, w, h)
		var m: int = s.orr.act[col]
		if m >= 0:
			draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.5))
			draw_texture_rect(_tex(game.mission_img(m)), r, false)
			var who: int = game.comb_carrier_for(BOData.MISSIONS[m].k)
			var tip: String = "%s\n%s\nRicompensa: %s" % [BOData.MISSIONS[m].name, BOData.MISSIONS[m].req, BOData.MISSIONS[m].rew]
			if who >= 0:
				tip += "\nCombattente portato da " + game.cname(who)
			hot.append([r, tip + "\n(clicca per ingrandire)", game.mission_img(m)])
		else:
			draw_rect(r, Color(1, 1, 1, 0.05))
			draw_rect(r, Color(1, 1, 1, 0.25), false, 1.5)
			var f := UI.font("italic")
			draw_multiline_string(f, r.position + Vector2(10, r.size.y / 2 - 10), "Nessuna missione %s:\ncolloca una telescrivente %s" % [BOData.TEL_NAMES[col], BOData.TEL_NAMES[col]], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20, 16, -1, UI.MUTED)
	draw_texture_rect(_tex("res://assets/res/boards/resistenza.jpg"), Rect2(o, RES_SIZE * sc), false)
	# telescriventi ancora sulla plancia (nei due cerchi di ogni colore)
	for col in BOData.TEL_COLORS:
		var x0: float = COL_X[col][0]
		var x1: float = COL_X[col][1]
		var circles := [Vector2(x0 + (x1 - x0) * 0.27, 100), Vector2(x0 + (x1 - x0) * 0.73, 100)]
		var on_board: int = 2 - s.orr.sup[col]
		for k in range(2):
			if k >= on_board:
				_circle_tok(b.call(circles[k]), 80 * sc, "res://assets/res/tokens/%s.png" % BOData.TEL_IMG[col])
		hot.append([Rect2(b.call(Vector2(x0, 0)), Vector2(x1 - x0, 205) * sc), "Telescriventi %s: %d sulla plancia, %d sul tabellone.\nLa prima collocata rivela la missione, la seconda la protegge." % [BOData.TEL_NAMES[col], s.orr.sup[col], on_board], ""])
	# Prove
	for k in range(s.orr.prove):
		var rr := Rect2(b.call(Vector2(465, 245 + k * 190)), Vector2(150, 165) * sc)
		draw_texture_rect(_tex("res://assets/items/PROVE.png"), rr, false)
	hot.append([Rect2(b.call(Vector2(465, 245)), Vector2(150, 355) * sc), "Oggetti Prove disponibili: %d" % s.orr.prove, ""])
	# telescrivente permanente e nascondiglio
	if s.orr.perm == "" and not s.orr.done.has(_mission_index("reclutamento")):
		_circle_tok(b.call(Vector2(793, 300)), 62 * sc, "res://assets/res/tokens/TEL_P.png")
	if not s.orr.hideout_have:
		_circle_tok(b.call(Vector2(793, 475)), 62 * sc, "res://assets/res/tokens/NASC.png")
	elif s.orr.hideout != "":
		hot.append([Rect2(b.call(Vector2(720, 400)), Vector2(150, 150) * sc), "Nascondiglio su: " + game.cardname(s.orr.hideout), ""])
	# volantini
	for k in range(mini(s.orr.sup.V, 5)):
		_circle_tok(b.call(VOL_POS[k]), 70 * sc, "res://assets/res/tokens/VOL.png")
	# combattenti
	for k in range(s.orr.comb_sup):
		draw_texture_rect(_tex("res://assets/items/COMB.png"), Rect2(b.call(Vector2(1495, 255 + k * 185)), Vector2(130, 145) * sc), false)
	# mazzo, scarti, completate
	_count_badge(b.call(Vector2(265, 690)), "%d carte" % s.orr.mdeck.size())
	_count_badge(b.call(Vector2(836, 690)), "%d carte" % s.orr.mdisc.size())
	var done: Array = s.orr.done
	_count_badge(b.call(Vector2(1395, 690)), "%d  →  +%d dad%s ai complotti" % [done.size(), done.size(), "o" if done.size() == 1 else "i"])
	if done.size() > 0:
		var names: Array = []
		for m in done:
			names.append(BOData.MISSIONS[m].name)
		hot.append([Rect2(b.call(Vector2(1150, 630)), Vector2(495, 88) * sc), "Missioni completate:\n" + "\n".join(names), ""])

func _mission_index(k: String) -> int:
	for x in range(BOData.MISSIONS.size()):
		if BOData.MISSIONS[x].k == k:
			return x
	return -1

# ---------------------------------------------------------------------
func _draw_kk() -> void:
	var s: Dictionary = game.s
	var o := Vector2.ZERO
	var bsz := IND_SIZE * sc
	draw_texture_rect(_tex("res://assets/res/boards/indagine.jpg"), Rect2(o, bsz), false)
	var cw := 120.0
	var chh := 168.0
	# mazzo incontro
	var dr := Rect2(Vector2(755 * sc - cw / 2, bsz.y + 10), Vector2(cw, chh))
	if s.kk.edeck.size() > 0:
		draw_rect(Rect2(dr.position + Vector2(4, 5), dr.size), Color(0, 0, 0, 0.5))
		draw_texture_rect(_tex("res://assets/res/enc/back.jpg"), dr, false)
	_count_badge(dr.position + Vector2(cw / 2, chh - 4), "%d" % s.kk.edeck.size())
	hot.append([dr, "Mazzo incontro: %d carte.\nSe bisogna pescare e il mazzo è finito, la partita è persa." % s.kk.edeck.size(), ""])
	# scarti incontro (a ventaglio)
	var n: int = s.kk.edisc.size()
	var x0 := 1278 * sc - cw / 2
	for k in range(n):
		var e: int = s.kk.edisc[k]
		var rr := Rect2(Vector2(x0 + (k - (n - 1) / 2.0) * minf(34.0, 300.0 / maxf(n, 1)), bsz.y + 10), Vector2(cw, chh))
		draw_rect(Rect2(rr.position + Vector2(3, 4), rr.size), Color(0, 0, 0, 0.45))
		draw_texture_rect(_tex(game.enc_img(e)), rr, false)
	if n > 0:
		var last: int = s.kk.edisc[n - 1]
		hot.append([Rect2(Vector2(x0 - 160, bsz.y + 10), Vector2(cw + 320, chh)), "Scarti incontro: %d carte (in cima: %s)" % [n, BOData.ENCOUNTERS[last].name], game.enc_img(last)])
	# Kopkow e fiato sul collo
	var f := UI.font("head")
	var txt: String = "Horst Kopkow: " + (game.spname(s.kk.pos) if s.kk.pos != "" else "entra al QG Gestapo con il primo evento dello Stadio 2")
	draw_string(f, Vector2(10, bsz.y + 40), txt, HORIZONTAL_ALIGNMENT_LEFT, 420, 18, UI.GOLD)
	var y := bsz.y + 70
	if s.kk.fiato.size() > 0:
		var nm: Array = []
		for j in s.kk.fiato:
			nm.append(game.cname(j))
		draw_multiline_string(UI.font("body"), Vector2(10, y), "Fiato sul Collo su: " + ", ".join(nm), HORIZONTAL_ALIGNMENT_LEFT, 420, 16, -1, Color("ff8a70"))
		y += 44
	if game.kk_no_conspire():
		draw_string(UI.font("body"), Vector2(10, y), "Eccesso di Cautela: niente Cospirare", HORIZONTAL_ALIGNMENT_LEFT, 420, 16, Color("ff8a70"))
		y += 24
	if s.kk.favore >= 0:
		draw_string(UI.font("body"), Vector2(10, y), "Restituire il Favore: %s avrà 2 azioni" % game.cname(s.kk.favore), HORIZONTAL_ALIGNMENT_LEFT, 420, 16, Color("ff8a70"))

# ---------------------------------------------------------------------
func _draw_ck() -> void:
	var s: Dictionary = game.s
	var res_w := 230.0
	var o := Vector2(res_w + 20, 0)
	var bsz := ALL_SIZE * sc
	draw_texture_rect(_tex("res://assets/res/boards/alleati.jpg"), Rect2(o, bsz), false)
	# riserva di reclutamento (a sinistra della plancia)
	var f := UI.font("head2")
	draw_string(f, Vector2(0, 22), "Riserva di reclutamento", HORIZONTAL_ALIGNMENT_LEFT, res_w, 17, UI.GOLD)
	for k in range(s.ck.res.size()):
		var a: int = s.ck.res[k]
		var rr := Rect2(Vector2(0, 34 + k * 132), Vector2(res_w, res_w * 205.0 / 380.0))
		draw_rect(Rect2(rr.position + Vector2(3, 4), rr.size), Color(0, 0, 0, 0.5))
		draw_texture_rect(_tex(game.ally_img_i(a)), rr, false)
		hot.append([rr, "%s – %s\n%s\n(clicca per ingrandire)" % [BOData.ALLIES[a].name, BOData.ALLIES[a].role, BOData.ALLIES[a].text], game.ally_img_i(a)])
	# pila delle tessere alleato
	var pr := Rect2(o + Vector2(24, 1044) * sc, Vector2(388, 200) * sc)
	if s.ck.apile.size() > 0:
		draw_texture_rect(_tex("res://assets/res/boards/ally_back.jpg"), pr, false)
	_count_badge(pr.get_center(), "%d tessere" % s.ck.apile.size())
	# Circolo: alleati reclutati negli slot
	var n: int = s.ck.circle.size()
	for k in range(n):
		var e = s.ck.circle[k]
		var rr := Rect2(o + Vector2(448, ALLY_ROWS[k] + 2) * sc, Vector2(396, 196) * sc)
		draw_texture_rect(_tex(game.ally_img_i(e.a)), rr, false, Color(0.45, 0.45, 0.45) if e.used else Color.WHITE)
		if e.used:
			draw_string(UI.font("head"), rr.position + Vector2(8, rr.size.y - 10), "USATO", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ff8a70"))
		hot.append([rr, "%s – %s%s\n%s" % [BOData.ALLIES[e.a].name, BOData.ALLIES[e.a].role, " (già usato)" if e.used else " (pronto, ⚡ monouso)", BOData.ALLIES[e.a].text], game.ally_img_i(e.a)])
	# status attivo: lo slot occupato più in basso
	if n > 0:
		var row := Rect2(o + Vector2(440, ALLY_ROWS[n - 1] - 6) * sc, Vector2(866, 212) * sc)
		draw_rect(row.grow(2), Color(1, 0.8, 0.25, 0.95), false, 4)
		draw_rect(row, Color(1, 0.85, 0.3, 0.12))
	else:
		var row := Rect2(o + Vector2(440, ALLY_ROWS[0] - 6) * sc, Vector2(866, 212) * sc)
		draw_rect(row, Color(0.7, 0.1, 0.1, 0.25))
		draw_rect(row, Color(0.9, 0.2, 0.15), false, 3)
	hot.append([Rect2(o + Vector2(860, 100) * sc, Vector2(450, 1150) * sc), "Status attuale: " + BOData.KREISAU_STATUS[mini(n, 5)][2] + "\nSi applica solo lo slot occupato più in basso.", ""])
