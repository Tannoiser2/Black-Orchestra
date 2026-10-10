extends Control
class_name BOGameView
## Schermata di gioco e "chooser" interattivo per il motore BOGame.

signal answered(v)
signal quit_to_menu
signal restart_requested

const SAVE_PATH := "user://blackorchestra_save.txt"
const AFF_COLORS := {"Abwehr": Color("7cc46a"), "Wehrmacht": Color("c98a5a"), "Civile": Color("7fa8e0")}

var game: BOGame
var board: BOBoardView
var header_lbl: RichTextLabel
var ev_thumb: TextureRect
var key_thumb: TextureRect
var stats_lbl: RichTextLabel
var player_box: VBoxContainer
var prompt_lbl: RichTextLabel
var dice_row: HBoxContainer
var btn_flow: HFlowContainer
var log_lbl: RichTextLabel
var overlay: Control
var modal_layer: Control

var _waiting := ""          # "", "choose", "space", "action"
var _cur_actions: Array = []
var _pending_space := ""
var _refresh_queued := false
var _auto_events := false
var _focus := -1          # cospiratore mostrato per esteso (-1 = attivo)
var plot_box: RichTextLabel
var log_panel: PanelContainer
var stats_panel: PanelContainer

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	board = BOBoardView.new()
	board.position = Vector2(0, 0)
	board.space_clicked.connect(_on_space_clicked)
	board.event_clicked.connect(func(eid): zoom(game.eimg(eid)))
	add_child(board)
	_build_right()
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)

func start(g: BOGame) -> void:
	game = g
	game.ch = self
	board.game = game
	game.changed.connect(_queue_refresh)
	game.logged.connect(_on_log)
	game.finished.connect(_on_finished)
	game.turn_started.connect(_autosave)
	game.turn_started.connect(func(): _focus = -1)
	game.moved.connect(board.on_moved)
	board.item_clicked.connect(_on_item_clicked)
	for line in game.s.log:
		_on_log(line)
	_refresh()
	game.run()

# ---------------------------------------------------------------------
# Costruzione interfaccia
# ---------------------------------------------------------------------
func _build_right() -> void:
	var right := VBoxContainer.new()
	right.position = Vector2(1088, 6)
	right.size = Vector2(826, 1068)
	right.add_theme_constant_override("separation", 6)
	add_child(right)
	# intestazione
	var hp := UI.panel(UI.PANEL, UI.BORDER, 8)
	var hb := HBoxContainer.new()
	hp.add_child(hb)
	header_lbl = RichTextLabel.new()
	header_lbl.bbcode_enabled = true
	header_lbl.fit_content = true
	header_lbl.scroll_active = false
	header_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_lbl.add_theme_font_override("normal_font", UI.font("head2"))
	header_lbl.add_theme_font_override("bold_font", UI.font("head"))
	header_lbl.add_theme_font_size_override("normal_font_size", 19)
	header_lbl.add_theme_font_size_override("bold_font_size", 19)
	hb.add_child(header_lbl)
	hb.add_child(UI.button("Scheda riassuntiva", func(): _show_aid(), 15))
	hb.add_child(UI.button("Menu", func(): _confirm_menu(), 15))
	right.add_child(hp)
	# cospiratori
	player_box = VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 6)
	right.add_child(player_box)
	# pannello azioni
	var ap := UI.panel(Color("241a15"), UI.GOLD.darkened(0.45), 10)
	ap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 6)
	ap.add_child(av)
	prompt_lbl = RichTextLabel.new()
	prompt_lbl.bbcode_enabled = true
	prompt_lbl.fit_content = true
	prompt_lbl.scroll_active = false
	prompt_lbl.add_theme_font_size_override("normal_font_size", 19)
	prompt_lbl.add_theme_font_size_override("bold_font_size", 19)
	av.add_child(prompt_lbl)
	dice_row = HBoxContainer.new()
	av.add_child(dice_row)
	plot_box = RichTextLabel.new()
	plot_box.bbcode_enabled = true
	plot_box.fit_content = true
	plot_box.scroll_active = false
	plot_box.visible = false
	plot_box.add_theme_font_size_override("normal_font_size", 16)
	plot_box.add_theme_font_size_override("bold_font_size", 17)
	plot_box.add_theme_stylebox_override("normal", UI.sbox(Color("2c1a12"), Color("6fae5a"), 1, 6, 8))
	av.add_child(plot_box)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 100)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	btn_flow = HFlowContainer.new()
	btn_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_flow.add_theme_constant_override("h_separation", 6)
	btn_flow.add_theme_constant_override("v_separation", 6)
	sc.add_child(btn_flow)
	av.add_child(sc)
	right.add_child(ap)
	# registro
	var lp := UI.panel(Color("16110e"), UI.BORDER, 8)
	lp.custom_minimum_size = Vector2(0, 168)
	log_panel = lp
	log_lbl = RichTextLabel.new()
	log_lbl.bbcode_enabled = true
	log_lbl.scroll_following = true
	log_lbl.add_theme_font_size_override("normal_font_size", 16)
	log_lbl.add_theme_font_size_override("bold_font_size", 16)
	log_lbl.add_theme_color_override("default_color", Color("cfc3b2"))
	lp.add_child(log_lbl)
	right.add_child(lp)

func _click(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT

# ---------------------------------------------------------------------
# Aggiornamento
# ---------------------------------------------------------------------
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	_refresh_queued = false
	if game == null or game.s.is_empty():
		return
	var s := game.s
	var act: int = s.active
	var acts := ""
	if s.phase == "actions" and not game.P(act).prison:
		acts = "  ·  Azioni: [b][color=#d9b45a]%d[/color][/b]" % s.turn.get("actions", 0)
	header_lbl.text = "[b]Turno %d[/b]  ·  Stadio [b]%d[/b]  ·  Attivo: [color=#%s][b]%s[/b][/color]%s" % [s.turn_no, s.stage, UI.PCOLORS[act].to_html(false), game.cname(act), acts]
	var mod := game.event_mod()
	if mod != 0:
		header_lbl.text += "\n[color=#d9b45a]Evento attuale: %s %d aquil%s nei complotti[/color]" % ["+" if mod > 0 else "ignora", absi(mod), "a" if absi(mod) == 1 else "e"]
	_build_players()
	board.queue_redraw()

func _events_left() -> int:
	var n := 0
	for st in range(1, 8):
		n += game.s.decks[st].size()
	return n

func _pill(text: String, on: bool, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sbox(col if on else Color("2a201b"), (UI.GOLD if on else Color("4a3428")), 1, 4, 5))
	var l := UI.label(text, 14, Color.WHITE if on else UI.MUTED, "head2")
	p.add_child(l)
	return p

func _build_players() -> void:
	for c in player_box.get_children():
		c.queue_free()
	var full: int = _focus if _focus >= 0 and _focus < game.np() else game.s.active
	for i in range(game.np()):
		if game.np() <= 2 or i == full:
			player_box.add_child(_player_panel(i))
		else:
			player_box.add_child(_player_compact(i))
	log_panel.custom_minimum_size.y = 150 if game.np() <= 2 else (120 if game.np() == 3 else 84)

func _plot_doable(i: int, cid: String) -> bool:
	return game.is_plot(cid) and not game.P(i).prison and game.plot_req_fail(i, game.plot_letter(cid)) == ""

func _dossier_thumb(i: int, k: int, h: float) -> Control:
	var cid: String = game.P(i).dossier[k]
	var plot := game.is_plot(cid)
	var tr := UI.trect(game.cimg(cid), Vector2(h * 1.4, h) if plot else Vector2(h * 0.72, h))
	tr.tooltip_text = game.cardname(cid) + ("  [ILLEGALE]" if game.is_illegal(cid) else "")
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tr.gui_input.connect(func(e): if _click(e): _card_clicked(i, k))
	if _plot_doable(i, cid):
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.sbox(Color(0.2, 0.6, 0.25, 0.35), Color("7fff6a"), 3, 4, 2))
		tr.tooltip_text = "★ COMPLOTTO TENTABILE ★\n" + game.cardname(cid) + "\nClicca per i dettagli e per tentarlo."
		pc.add_child(tr)
		var tw := pc.create_tween().set_loops()
		tw.tween_property(pc, "self_modulate", Color(1, 1, 1, 0.35), 0.6)
		tw.tween_property(pc, "self_modulate", Color(1, 1, 1, 1.0), 0.6)
		return pc
	return tr

func _player_compact(i: int) -> Control:
	var p := game.P(i)
	var cd = BOData.CONSPIRATORS[p.cid]
	var pcol: Color = UI.PCOLORS[i]
	var pan := UI.panel(UI.PANEL, pcol.darkened(0.3), 6)
	pan.custom_minimum_size = Vector2(0, 92)
	pan.mouse_filter = Control.MOUSE_FILTER_STOP
	pan.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pan.tooltip_text = "Clicca per espandere " + cd.name
	pan.gui_input.connect(func(e): if _click(e):
		_focus = i
		_refresh())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(hb)
	var face := UI.trect("res://assets/faces/f%02d.png" % p.cid, Vector2(70, 70))
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p.prison:
		face.modulate = Color(0.6, 0.45, 0.45)
	hb.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(190, 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UI.label(cd.name, 18, pcol.lightened(0.25), "head")
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.clip_text = true
	v.add_child(nm)
	var sub := UI.label("%s · %s" % [cd.aff, ("IN PRIGIONE" if p.prison else game.spname(p.space))], 14, UI.RED if p.prison else AFF_COLORS[cd.aff], "head2")
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	hb.add_child(v)
	var v2 := VBoxContainer.new()
	v2.add_theme_constant_override("separation", 2)
	v2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 4)
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r1.add_child(_pill("Mot. " + BOData.MOT_NAMES[p.mot], true, Color("b8862b")))
	r1.add_child(_pill("Sosp. " + BOData.SUSP_NAMES[p.susp], true, Color("9b2c22")))
	v2.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 2)
	r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in p.items:
		var tr := UI.trect("res://assets/items/%s.png" % it, Vector2(44, 44))
		tr.tooltip_text = BOData.ITEM_NAMES[it]
		r2.add_child(tr)
	if p.items.is_empty():
		r2.add_child(UI.label("nessun oggetto", 13, UI.MUTED, "italic"))
	v2.add_child(r2)
	hb.add_child(v2)
	var csc := ScrollContainer.new()
	csc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csc.custom_minimum_size = Vector2(80, 86)
	csc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 3)
	for k in range(p.dossier.size()):
		cards.add_child(_dossier_thumb(i, k, 80))
	csc.add_child(cards)
	hb.add_child(csc)
	return pan

func _player_panel(i: int) -> Control:
	var p := game.P(i)
	var cd = BOData.CONSPIRATORS[p.cid]
	var active: bool = i == game.s.active
	var pcol: Color = UI.PCOLORS[i]
	var pan := UI.panel(Color("221915") if active else UI.PANEL, pcol if active else UI.BORDER, 8)
	if game.np() > 2 and not active:
		pan.tooltip_text = "Clicca per tornare al cospiratore attivo"
		pan.gui_input.connect(func(e): if _click(e):
			_focus = -1
			_refresh())
	pan.custom_minimum_size = Vector2(0, 250)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pan.add_child(hb)
	var lv := VBoxContainer.new()
	var por := UI.trect("res://assets/sheets/p%02d.jpg" % p.cid, Vector2(118, 138))
	por.mouse_filter = Control.MOUSE_FILTER_STOP
	por.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	por.tooltip_text = "Clicca per vedere la scheda cospiratore"
	por.gui_input.connect(func(e): if _click(e): zoom("res://assets/sheets/s%02d.jpg" % p.cid))
	if p.prison:
		por.modulate = Color(0.55, 0.45, 0.45)
	lv.add_child(por)
	var stripe := ColorRect.new()
	stripe.color = pcol
	stripe.custom_minimum_size = Vector2(118, 6)
	lv.add_child(stripe)
	var loc := UI.label(game.spname(p.space), 15, UI.GOLD if not p.prison else UI.RED, "head2")
	loc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loc.custom_minimum_size = Vector2(118, 0)
	loc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(loc)
	hb.add_child(lv)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	hb.add_child(v)
	var r1 := HBoxContainer.new()
	var nm := UI.label(cd.name, 22, pcol.lightened(0.25), "head")
	r1.add_child(nm)
	var af := UI.label("  " + cd.aff.to_upper(), 16, AFF_COLORS[cd.aff], "head")
	r1.add_child(af)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(spacer)
	if p.prison:
		r1.add_child(_pill("IN PRIGIONE", true, UI.RED))
	if i in game.s.blocked:
		r1.add_child(_pill("capacità bloccata", true, Color("555555")))
	if game.s.faulty == i:
		r1.add_child(_pill("dado difettoso", true, Color("6b5a2a")))
	if game.s.surveil == i:
		r1.add_child(_pill("sorvegliato", true, Color("6b2a2a")))
	v.add_child(r1)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 3)
	r2.add_child(UI.label("Motivazione ", 15, UI.MUTED, "head2"))
	for k in range(5):
		r2.add_child(_pill(BOData.MOT_NAMES[k], k == p.mot, Color("b8862b")))
	v.add_child(r2)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 3)
	r3.add_child(UI.label("Sospetto      ", 15, UI.MUTED, "head2"))
	for k in range(4):
		r3.add_child(_pill(BOData.SUSP_NAMES[k], k == p.susp, Color("9b2c22")))
	r3.add_child(UI.label("  complotto scoperto con %d aquil%s" % [BOData.SUSP_EAGLES[p.susp], "a" if BOData.SUSP_EAGLES[p.susp] == 1 else "e"], 14, UI.MUTED, "italic"))
	v.add_child(r3)
	# oggetti e dossier
	var r4 := HBoxContainer.new()
	r4.add_theme_constant_override("separation", 4)
	r4.add_child(UI.label("Oggetti %d/%d " % [p.items.size(), game.item_limit(i)], 15, UI.MUTED, "head2"))
	for it in p.items:
		var tr := UI.trect("res://assets/items/%s.png" % it, Vector2(54, 54))
		tr.tooltip_text = BOData.ITEM_NAMES[it]
		r4.add_child(tr)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(14, 0)
	r4.add_child(sep)
	var abl: bool = game.ab_on(i, cd.ability)
	var ab := UI.label("Capacità: " + ("ATTIVA" if abl else "inattiva (serve Determinato)" if p.mot < 2 else "inattiva"), 14, UI.GREEN if abl else UI.MUTED, "head2")
	ab.tooltip_text = cd.text
	ab.mouse_filter = Control.MOUSE_FILTER_STOP
	r4.add_child(ab)
	v.add_child(r4)
	var r5 := HBoxContainer.new()
	r5.add_theme_constant_override("separation", 4)
	r5.add_child(UI.label("Dossier %d/%d " % [p.dossier.size(), game.dossier_limit(i)], 15, UI.MUTED, "head2"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 96)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	sc.add_child(cards)
	for k in range(p.dossier.size()):
		cards.add_child(_dossier_thumb(i, k, 88))
	r5.add_child(sc)
	v.add_child(r5)
	return pan

func _on_log(t: String) -> void:
	if log_lbl == null:
		return
	var line := t.replace("[", "(").replace("]", ")")
	if t.begins_with("────"):
		line = "\n[b][color=#d9b45a]%s[/color][/b]" % line
	elif t.begins_with("═══"):
		line = "[b][color=#e04a3c]%s[/color][/b]" % line
	elif t.begins_with("Evento:"):
		line = "[color=#e8c27a]%s[/color]" % line
	elif t.begins_with("★") or t.begins_with("✖") or t.begins_with("⛓") or t.begins_with("🚨"):
		line = "[b][color=#ff8a70]%s[/color][/b]" % line
	log_lbl.append_text(line + "\n")

# ---------------------------------------------------------------------
# Chooser
# ---------------------------------------------------------------------
func _clear_buttons() -> void:
	for c in btn_flow.get_children():
		c.queue_free()
	for c in dice_row.get_children():
		c.queue_free()

func _opt_label(o) -> String:
	return o.label if o is Dictionary else str(o)

func _opt_img(o) -> String:
	return o.get("img", "") if o is Dictionary else ""

func _who(p: int) -> String:
	if p < 0 or p >= game.np():
		return ""
	return "[color=#%s][b]%s[/b][/color] – " % [UI.PCOLORS[p].to_html(false), game.cname(p)]

func choose(p: int, prompt: String, options: Array, extra: Dictionary = {}) -> int:
	if options.is_empty():
		return -1
	await _wait_board()
	_refresh()
	var has_img := extra.has("imgs")
	for o in options:
		if _opt_img(o) != "":
			has_img = true
	_waiting = "choose"
	if has_img:
		_modal_choice(p, prompt, options, extra)
	else:
		_clear_buttons()
		prompt_lbl.text = _who(p) + _esc(prompt)
		if extra.has("dice"):
			_dice_icons(dice_row, extra.dice, 40)
		for k in range(options.size()):
			var idx := k
			btn_flow.add_child(UI.button(_opt_label(options[k]), func(): answered.emit(idx), 17))
		if extra.get("cancel", false):
			btn_flow.add_child(UI.button("Annulla", func(): answered.emit(-1), 17))
	var v = await answered
	_waiting = ""
	_close_modal()
	_clear_buttons()
	prompt_lbl.text = ""
	return v

func choose_space(p: int, prompt: String, spaces: Array, cancel: bool) -> String:
	if spaces.is_empty():
		return ""
	await _wait_board()
	if _pending_space != "" and _pending_space in spaces:
		var sp := _pending_space
		_pending_space = ""
		return sp
	_pending_space = ""
	_refresh()
	_waiting = "space"
	_clear_buttons()
	prompt_lbl.text = _who(p) + _esc(prompt) + "\n[i][color=#a89a88]Clicca una casella evidenziata sul tabellone oppure scegli qui sotto.[/color][/i]"
	board.highlights = spaces.duplicate()
	var sorted_sp := spaces.duplicate()
	sorted_sp.sort_custom(func(a, b): return game.spname(a) < game.spname(b))
	for sp in sorted_sp:
		var spc: String = sp
		btn_flow.add_child(UI.button(game.spname(spc), func(): answered.emit(spc), 16))
	if cancel:
		btn_flow.add_child(UI.button("Annulla", func(): answered.emit(""), 16))
	var v = await answered
	board.highlights = []
	_waiting = ""
	_clear_buttons()
	prompt_lbl.text = ""
	return v

func choose_action(p: int, actions: Array) -> Dictionary:
	await _wait_board()
	_refresh()
	_waiting = "action"
	_cur_actions = actions
	_clear_buttons()
	var n: int = game.s.turn.actions
	prompt_lbl.text = _who(p) + "scegli un'azione ([b]%d[/b] azion%s rimast%s)." % [n, "e" if n == 1 else "i", "a" if n == 1 else "e"]
	if game.np() <= 2:
		prompt_lbl.text += " [i][color=#a89a88]Puoi anche cliccare una casella adiacente per muoverti o una carta del dossier per esaminarla.[/color][/i]"
	board.soft = []
	board.item_hot = []
	var plots_bb: Array = []
	for a in actions:
		if a.id == "move":
			board.soft = a.targets.duplicate()
		elif a.id == "collect" or a.id == "reveal":
			board.item_hot = [game.P(p).space]
		elif a.id == "plot":
			plots_bb.append(_plot_info_bb(p, a.cid))
	board.plot_ready = plots_bb.size() > 0
	plot_box.visible = plots_bb.size() > 0
	plot_box.text = "\n".join(plots_bb)
	plot_box.add_theme_font_size_override("normal_font_size", 16 if game.np() <= 2 else 14)
	plot_box.add_theme_font_size_override("bold_font_size", 17 if game.np() <= 2 else 15)
	if board.item_hot.size() > 0:
		prompt_lbl.text += " [i][color=#7fd06a]Clicca l'oggetto evidenziato per %s.[/color][/i]" % ("raccoglierlo" if game.s.board_items[board.item_hot[0]].rev else "rivelarlo")
	var order := ["plot", "move", "collect", "reveal", "deliver", "dossier", "conspire", "release", "transfer", "card", "ability", "bolt", "end"]
	var sorted_a := actions.duplicate()
	sorted_a.sort_custom(func(a, b): return order.find(a.id) < order.find(b.id))
	for a in sorted_a:
		var act: Dictionary = a
		var b: Button
		if a.id in ["plot", "end"]:
			b = UI.accent_button(a.label, func(): answered.emit(act), 17)
		else:
			b = UI.button(a.label, func(): answered.emit(act), 17)
		if a.id == "card" or a.id == "bolt":
			b.tooltip_text = BOData.CCARDS[game.ctype(a.cid)].text
		elif a.id == "ability":
			b.tooltip_text = BOData.CONSPIRATORS[game.P(p).cid].text
		elif a.id == "plot":
			b.tooltip_text = _plot_tip(a.cid)
		btn_flow.add_child(b)
	var v = await answered
	board.soft = []
	board.item_hot = []
	board.plot_ready = false
	plot_box.visible = false
	_waiting = ""
	_cur_actions = []
	_clear_buttons()
	prompt_lbl.text = ""
	return v

func notify(text: String, extra: Dictionary = {}) -> void:
	await _wait_board()
	_refresh()
	if extra.has("event") and _auto_events:
		return
	_waiting = "notify"
	var box := _open_modal(text)
	if extra.has("img"):
		var tr := UI.trect(extra.img, Vector2(340, 476))
		box.add_child(tr)
	if extra.has("dice"):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		_animate_dice(row, extra.dice)
	if extra.has("text"):
		var rl := _rich(_esc(extra.text), 19)
		rl.custom_minimum_size = Vector2(620, 0)
		box.add_child(rl)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	var ok := UI.accent_button("  Continua  ", func(): answered.emit(null), 20)
	hb.add_child(ok)
	if extra.has("event"):
		var cb := CheckBox.new()
		cb.text = "Non mostrare più le carte evento"
		cb.button_pressed = _auto_events
		cb.toggled.connect(func(on): _auto_events = on)
		hb.add_child(cb)
	box.add_child(hb)
	ok.grab_focus.call_deferred()
	await answered
	_waiting = ""
	_close_modal()

func _wait_board() -> void:
	var guard := 0
	while board.is_busy() and guard < 300:
		guard += 1
		await get_tree().process_frame

func _on_item_clicked(sp: String) -> void:
	if _waiting != "action":
		return
	for a in _cur_actions:
		if a.id == "collect" or a.id == "reveal":
			answered.emit(a)
			return

## Riepilogo bbcode di un complotto: requisiti soddisfatti e dadi.
func _plot_info_bb(i: int, cid: String, compact: bool = false) -> String:
	var pv := game.plot_preview(i, game.plot_letter(cid))
	var ok_c := "#7fd06a"
	var no_c := "#e0604c"
	var t := "[b][color=#d9b45a]★ %s[/color][/b]  –  " % pv.name
	t += "[b]%d dad%s[/b]" % [pv.dice, "o" if pv.dice == 1 else "i"]
	if pv.cancel > 0:
		t += ", annulla fino a %d aquil%s" % [pv.cancel, "a" if pv.cancel == 1 else "e"]
	t += "  ·  servono [b]%d ⊕[/b], scoperto con [b]%d aquil%s[/b]" % [pv.need, pv.limit, "a" if pv.limit == 1 else "e"]
	if pv.mod != 0:
		t += " (evento: %s%d aquil%s)" % ["+" if pv.mod > 0 else "−", absi(pv.mod), "a" if absi(pv.mod) == 1 else "e"]
	t += "\n"
	var parts: Array = []
	for q in pv.req:
		parts.append("[color=%s]%s %s[/color]" % [ok_c if q[1] else no_c, "✔" if q[1] else "✘", q[0]])
	t += "Necessari: " + "  ".join(parts)
	parts = []
	for q in pv.opt:
		parts.append("[color=%s]%s %s[/color]" % [ok_c if q[1] else "#8a7d6c", "✔" if q[1] else "○", q[0]])
	t += "\nFacoltativi: " + "  ".join(parts)
	if pv.extra.size() > 0:
		t += "\n[color=#a89a88]Disponibili al momento del tiro: %s[/color]" % ", ".join(pv.extra)
	return t

func _plot_tip(cid: String) -> String:
	var l := game.plot_letter(cid)
	var pl = BOData.PLOTS[l]
	var t := "%s\nRequisiti: motivazione %s" % [pl.name, BOData.MOT_NAMES[pl.req.mot]]
	if pl.req.same:
		t += ", nella casella di Hitler"
	if pl.req.has("hit"):
		t += ", " + BOData.HIT_TEXT[pl.req.hit]
	if pl.req.get("bolt", false):
		t += ", solo subito dopo che un evento ha mosso Hitler"
	return t

func _esc(t: String) -> String:
	return t.replace("[", "(").replace("]", ")")

func _rich(text: String, size: int = 19) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r

func _dice_icons(row: HBoxContainer, faces: Array, sz: int) -> void:
	for f in faces:
		row.add_child(UI.trect(UI.face_path(f), Vector2(sz, sz)))

func _animate_dice(row: HBoxContainer, faces: Array) -> void:
	var rects: Array = []
	for f in faces:
		var tr := UI.trect(UI.face_path("T"), Vector2(72, 72))
		row.add_child(tr)
		rects.append(tr)
	var all := ["1", "2", "3", "T", "E"]
	for step in range(8):
		await get_tree().create_timer(0.06).timeout
		if not is_instance_valid(row):
			return
		for tr in rects:
			tr.texture = UI.tex(UI.face_path(all[randi() % 5]))
			tr.rotation = randf_range(-0.2, 0.2)
			tr.pivot_offset = Vector2(36, 36)
	for k in range(rects.size()):
		rects[k].texture = UI.tex(UI.face_path(faces[k]))
		rects[k].rotation = 0

# ---------------------------------------------------------------------
# Finestre modali
# ---------------------------------------------------------------------
func _open_modal(title: String) -> VBoxContainer:
	_close_modal()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var pan := UI.panel(Color("1f1714"), UI.GOLD.darkened(0.3), 18)
	cc.add_child(pan)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	pan.add_child(box)
	var tl := _rich("[center]" + _esc(title).replace("\n", "[/center]\n[center]") + "[/center]", 22)
	tl.custom_minimum_size = Vector2(700, 0)
	box.add_child(tl)
	return box

func _close_modal() -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null

func _modal_choice(p: int, prompt: String, options: Array, extra: Dictionary) -> void:
	var box := _open_modal((game.cname(p) + " – " if p >= 0 and p < game.np() else "") + prompt)
	if extra.has("imgs"):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		for im in extra.imgs:
			var tr := UI.trect(im, Vector2(300, 420))
			row.add_child(tr)
		box.add_child(row)
	if extra.has("dice"):
		var dr := HBoxContainer.new()
		dr.alignment = BoxContainer.ALIGNMENT_CENTER
		_dice_icons(dr, extra.dice, 56)
		box.add_child(dr)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1100, 0)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	sc.add_child(flow)
	var max_h := 0.0
	for k in range(options.size()):
		var o = options[k]
		var idx := k
		var img := _opt_img(o)
		var b: Button
		if img != "":
			b = UI.button(_opt_label(o), func(): answered.emit(idx), 15)
			var tx := UI.tex(img)
			b.icon = tx
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			var asp: float = float(tx.get_width()) / float(tx.get_height())
			var sz: Vector2
			if asp > 2.0:
				sz = Vector2(190, 110)
			elif asp > 1.1:
				sz = Vector2(250, 220)
			elif asp > 0.9:
				sz = Vector2(150, 170)
			else:
				sz = Vector2(170, 280)
			b.custom_minimum_size = sz
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			max_h = maxf(max_h, sz.y)
		else:
			b = UI.button(_opt_label(o), func(): answered.emit(idx), 18)
			b.custom_minimum_size = Vector2(0, 44)
			max_h = maxf(max_h, 44)
		flow.add_child(b)
	var rows: int = ceili(options.size() / 5.0)
	sc.custom_minimum_size.y = mini(int((max_h + 10) * rows), 540)
	box.add_child(sc)
	if extra.get("cancel", false):
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(UI.button("Annulla", func(): answered.emit(-1), 18))
		box.add_child(hb)

## Ingrandimento di un'immagine (carta, scheda). Clic per chiudere.
func zoom(path: String, play_action = null, info_bb: String = "") -> void:
	var z := Control.new()
	z.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(z)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(cc)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	cc.add_child(v)
	var tx := UI.tex(path)
	var asp: float = float(tx.get_width()) / float(tx.get_height())
	var sz := Vector2(560 * asp, 560) if asp < 1.0 else Vector2(minf(1300, 820 * asp), minf(1300, 820 * asp) / asp)
	if asp >= 1.0 and asp < 1.6:
		sz = Vector2(1100, 1100 / asp)
		if sz.y > 900:
			sz = Vector2(900 * asp, 900)
	if info_bb != "":
		sz *= 0.8
	var tr := UI.trect(path, sz)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	if info_bb != "":
		var ip := UI.panel(Color("1f1714"), UI.GOLD.darkened(0.3), 12)
		ip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rl := _rich(info_bb, 18)
		rl.custom_minimum_size = Vector2(1000, 0)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ip.add_child(rl)
		v.add_child(ip)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	if play_action != null:
		var act: Dictionary = play_action
		var play_cb := func():
			z.queue_free()
			if _waiting == "action":
				answered.emit(act)
		hb.add_child(UI.accent_button(act.label, play_cb, 18))
	hb.add_child(UI.button("Chiudi", func(): z.queue_free(), 18))
	z.gui_input.connect(func(e): if _click(e): z.queue_free())

func _card_clicked(i: int, k: int) -> void:
	var cid: String = game.P(i).dossier[k]
	var act = null
	if _waiting == "action":
		for a in _cur_actions:
			if a.has("cid") and a.cid == cid and (a.get("pidx", game.s.active) == i):
				act = a
				break
	var info := ""
	if game.is_plot(cid) and not game.P(i).prison:
		info = _plot_info_bb(i, cid)
	zoom(game.cimg(cid), act, info)

func _on_space_clicked(sp: String) -> void:
	if _waiting == "space" and sp in board.highlights:
		answered.emit(sp)
	elif _waiting == "action" and sp in board.soft:
		for a in _cur_actions:
			if a.id == "move":
				_pending_space = sp
				answered.emit(a)
				return

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_SPACE or e.keycode == KEY_ENTER) and _waiting == "notify":
		answered.emit(null)
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------
# Varie
# ---------------------------------------------------------------------
func _show_aid() -> void:
	zoom("res://assets/ui/aid_front.jpg")

func _confirm_menu() -> void:
	var z := Control.new()
	z.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(z)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.add_child(cc)
	var pan := UI.panel(Color("1f1714"), UI.GOLD.darkened(0.3), 20)
	cc.add_child(pan)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pan.add_child(v)
	v.add_child(UI.label("Tornare al menu principale?", 26, UI.TEXT, "head"))
	v.add_child(UI.label("La partita è salvata automaticamente all'inizio di ogni turno:\npotrai riprenderla con «Continua partita».", 19, UI.MUTED))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	hb.add_child(UI.accent_button("Torna al menu", func(): quit_to_menu.emit(), 19))
	hb.add_child(UI.button("Annulla", func(): z.queue_free(), 19))
	v.add_child(hb)

func _autosave() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(game.save_text())
		f.close()

func _on_finished(won: bool, reason: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_show_end.call_deferred(won, reason)

func _show_end(won: bool, reason: String) -> void:
	await get_tree().create_timer(0.3).timeout
	_close_modal()
	var z := Control.new()
	z.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(z)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.add_child(cc)
	var pan := UI.panel(Color("1a1310"), UI.GOLD if won else UI.RED, 30)
	cc.add_child(pan)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	pan.add_child(v)
	var t := UI.label("Vittoria!" if won else "Sconfitta...", 84, UI.GOLD if won else Color("e04a3c"), "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var msg := reason
	if won:
		msg += "\n\nHitler è stato assassinato. Milioni di vite sono state salvate e la brutale oppressione\ndella Germania nazista è stata colpita duramente. La storia ricorderà questo coraggio."
	else:
		msg += "\n\nIl tentativo della Resistenza tedesca è fallito."
	var l := UI.label(msg, 21, UI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var st := UI.label("Turni giocati: %d  ·  Stadio raggiunto: %d  ·  Supporto Militare finale: %d" % [game.s.turn_no, game.s.stage, game.s.ms], 18, UI.MUTED, "head2")
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	hb.add_child(UI.accent_button("Nuova partita", func(): restart_requested.emit(), 20))
	hb.add_child(UI.button("Menu principale", func(): quit_to_menu.emit(), 20))
	hb.add_child(UI.button("Guarda il tabellone", func(): z.queue_free(), 20))
	v.add_child(hb)
