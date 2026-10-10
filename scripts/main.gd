extends Control
## Menu principale, preparazione della partita e avvio della schermata di gioco.

const SAVE_PATH := "user://blackorchestra_save.txt"

var screen: Control
var selected: Array = []
var n_consp := 2
var n_btns: Array = []
var title_lbl: Label
var diff := 1
var variants := {"urgency": false, "no_docs": false, "promo_plot": true}
var preview: TextureRect
var preview_txt: RichTextLabel
var start_btn: Button
var card_panels := {}
var diff_btns: Array = []

func _ready() -> void:
	theme = UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_menu()

func _clear() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)

func _bg(dark: float = 0.0) -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	var tr := TextureRect.new()
	tr.texture = UI.tex("res://assets/ui/menu_bg.jpg")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = Vector2(0, -815)
	tr.size = Vector2(1920, 2270)
	tr.modulate = Color(1, 1, 1, 1.0 - dark)
	screen.add_child(tr)

# ---------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------
func show_menu() -> void:
	_clear()
	_bg()
	var v := VBoxContainer.new()
	v.position = Vector2(760, 530)
	v.size = Vector2(400, 400)
	v.add_theme_constant_override("separation", 14)
	screen.add_child(v)
	var sub := UI.label("Adattamento digitale – Solitario e cooperativo (2–5 cospiratori)", 22, Color("d8c7b0"), "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 450)
	sub.size = Vector2(1920, 40)
	screen.add_child(sub)
	var b1 := UI.accent_button("Nuova partita", show_setup, 24)
	b1.custom_minimum_size = Vector2(400, 58)
	v.add_child(b1)
	if FileAccess.file_exists(SAVE_PATH):
		var b2 := UI.button("Continua partita", continue_game, 22)
		b2.custom_minimum_size = Vector2(400, 52)
		v.add_child(b2)
	var b3 := UI.button("Scheda riassuntiva delle regole", func(): _zoom("res://assets/ui/aid_front.jpg"), 20)
	b3.custom_minimum_size = Vector2(400, 50)
	v.add_child(b3)
	var b4 := UI.button("Come si gioca (interfaccia)", _show_help, 20)
	b4.custom_minimum_size = Vector2(400, 50)
	v.add_child(b4)
	var b5 := UI.button("Esci", func(): get_tree().quit(), 20)
	b5.custom_minimum_size = Vector2(400, 50)
	v.add_child(b5)
	var cr := UI.label("Black Orchestra © Philip duBarry – Starling Games. Conversione digitale per uso personale.", 14, Color(1, 1, 1, 0.45), "italic")
	cr.position = Vector2(0, 1046)
	cr.size = Vector2(1920, 24)
	cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(cr)

func _zoom(path: String) -> void:
	var z := Control.new()
	z.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(z)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(dim)
	var tx := UI.tex(path)
	var asp: float = float(tx.get_width()) / tx.get_height()
	var h := 1000.0
	var tr := UI.trect(path, Vector2(h * asp, h))
	tr.position = Vector2((1920 - h * asp) / 2, 40)
	tr.size = Vector2(h * asp, h)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	z.add_child(tr)
	if path.ends_with("aid_front.jpg"):
		var back_cb := func():
			z.queue_free()
			_zoom("res://assets/ui/aid_back.jpg")
		var b := UI.button("Retro della scheda →", back_cb, 18)
		b.position = Vector2(1580, 980)
		z.add_child(b)
	var hint := UI.label("Clicca per chiudere", 16, UI.MUTED, "italic")
	hint.position = Vector2(20, 1045)
	z.add_child(hint)
	z.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: z.queue_free())

func _show_help() -> void:
	var z := Control.new()
	z.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(z)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z.add_child(dim)
	var pan := UI.panel(Color("1f1714"), UI.GOLD.darkened(0.3), 24)
	pan.position = Vector2(360, 90)
	pan.size = Vector2(1200, 880)
	z.add_child(pan)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.add_theme_font_size_override("normal_font_size", 20)
	r.add_theme_font_size_override("bold_font_size", 20)
	r.text = """[font_size=34][color=#d9b45a][b]Come si gioca[/b][/color][/font_size]

Giochi da solo controllando [b]due cospiratori[/b] che si alternano a turno. L'obiettivo è [b]assassinare Hitler[/b] riuscendo in un tentativo di complotto prima che finiscano le carte evento.

[color=#d9b45a][b]Il tuo turno[/b][/color]
1. Si applicano le penalità di Hitler e dei delegati presenti nella tua casella.
2. Esegui fino a 3 azioni con i pulsanti del pannello a destra. Puoi anche [b]cliccare una casella evidenziata[/b] sul tabellone per muoverti.
3. Premi [b]«Fine azioni → pesca evento»[/b]: viene pescata e risolta la carta evento.

[color=#d9b45a][b]Interfaccia[/b][/color]
• Passa il mouse sulle caselle del tabellone per vedere effetti, consegne e chi è presente.
• Clicca le carte del dossier, l'evento attuale/chiave o il ritratto di un cospiratore per ingrandirli.
• Le carte ⚡ vengono proposte automaticamente nel momento giusto (durante i complotti, quando un evento muove Hitler…). «Comunicato Urgente» e «Niente di Nuovo» compaiono tra le azioni, senza costo.
• I complotti tentabili compaiono come pulsanti rossi «★ TENTA». Prima del tiro potrai scartare oggetti per i requisiti facoltativi e scegliere quanti dadi tirare.
• La partita viene salvata automaticamente all'inizio di ogni turno.

[color=#d9b45a][b]Promemoria[/b][/color]
• Per riuscire servono tanti ⊕ quanto il Supporto Militare di Hitler, e meno aquile del limite dato dal tuo sospetto (Basso 3, Medio 2, Alto/Estremo 1).
• Per tentare un complotto serve motivazione [b]Devoto[/b] (alcuni richiedono Temerario). Da [b]Determinato[/b] si attiva la capacità del cospiratore.
• Si perde se entrambi i cospiratori sono in prigione, se non si può pescare un evento o se esce «Documenti Compromettenti».

[i]Clicca ovunque per chiudere.[/i]"""
	pan.add_child(r)
	z.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: z.queue_free())
	r.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: z.queue_free())

# ---------------------------------------------------------------------
# Preparazione
# ---------------------------------------------------------------------
func show_setup() -> void:
	_clear()
	_bg(0.82)
	selected = []
	card_panels = {}
	var title := UI.label("Scegli i tuoi due cospiratori", 52, UI.GOLD, "title")
	title_lbl = title
	title.position = Vector2(0, 14)
	title.size = Vector2(1920, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.position = Vector2(40, 96)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	screen.add_child(grid)
	for k in range(BOData.CONSPIRATORS.size()):
		grid.add_child(_consp_card(k))
	# anteprima
	preview = UI.trect("res://assets/sheets/s00.jpg", Vector2(640, 468))
	preview.position = Vector2(40, 590)
	preview.size = Vector2(640, 468)
	screen.add_child(preview)
	var right := VBoxContainer.new()
	right.position = Vector2(720, 584)
	right.size = Vector2(1160, 470)
	right.add_theme_constant_override("separation", 7)
	screen.add_child(right)
	preview_txt = RichTextLabel.new()
	preview_txt.bbcode_enabled = true
	preview_txt.fit_content = true
	preview_txt.scroll_active = false
	preview_txt.add_theme_font_size_override("normal_font_size", 20)
	preview_txt.add_theme_font_size_override("bold_font_size", 20)
	right.add_child(preview_txt)
	_preview(0)
	right.add_child(UI.label("Numero di cospiratori (2 = solitario; da 3 a 5 si gioca a turno sullo stesso computer)", 20, UI.GOLD, "head"))
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 10)
	n_btns = []
	for k in range(2, 6):
		var kk := k
		var b := UI.button("%d" % k, func(): _set_n(kk), 20)
		b.custom_minimum_size = Vector2(70, 44)
		b.toggle_mode = true
		n_btns.append(b)
		nh.add_child(b)
	right.add_child(nh)
	right.add_child(UI.label("Difficoltà (valore iniziale del Supporto Militare di Hitler)", 20, UI.GOLD, "head"))
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 10)
	diff_btns = []
	for k in range(3):
		var kk := k
		var b := UI.button(["Facile (2)", "Normale (3)", "Difficile (4)"][k], func(): _set_diff(kk), 19)
		b.custom_minimum_size = Vector2(200, 46)
		b.toggle_mode = true
		diff_btns.append(b)
		dh.add_child(b)
	right.add_child(dh)
	_set_diff(diff)
	right.add_child(UI.label("Varianti", 20, UI.GOLD, "head"))
	right.add_child(_check("Senso di Urgenza – scarta 1 carta aggiuntiva da ogni mazzo evento", "urgency"))
	right.add_child(_check("Documenti Sorvegliati – rimuovi «Documenti Compromettenti» (e scarta 1 sola carta dello Stadio 7)", "no_docs"))
	right.add_child(_check("Includi il complotto promo «P – Trasmissione della Resistenza»", "promo_plot"))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	var bk := UI.button("← Indietro", show_menu, 20)
	bk.custom_minimum_size = Vector2(170, 52)
	bh.add_child(bk)
	var rnd := UI.button("Scelta casuale", _random_pick, 20)
	rnd.custom_minimum_size = Vector2(200, 52)
	bh.add_child(rnd)
	start_btn = UI.accent_button("Inizia la partita", _start_new, 24)
	start_btn.custom_minimum_size = Vector2(320, 52)
	start_btn.disabled = true
	bh.add_child(start_btn)
	_update_sel.call_deferred()
	right.add_child(bh)

func _check(text: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = variants[key]
	c.add_theme_font_size_override("font_size", 19)
	c.toggled.connect(func(on): variants[key] = on)
	return c

func _set_diff(k: int) -> void:
	diff = k
	for j in range(diff_btns.size()):
		diff_btns[j].button_pressed = j == k

func _consp_card(k: int) -> Control:
	var cd = BOData.CONSPIRATORS[k]
	var pan := UI.panel(UI.PANEL, UI.BORDER, 6)
	pan.custom_minimum_size = Vector2(194, 232)
	pan.mouse_filter = Control.MOUSE_FILTER_STOP
	pan.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(v)
	var tr := UI.trect("res://assets/sheets/p%02d.jpg" % k, Vector2(180, 150))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)
	var n := UI.label(cd.name, 16, UI.TEXT, "head")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(180, 0)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var a := UI.label(cd.aff.to_upper(), 14, BOGameView.AFF_COLORS[cd.aff], "head2")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(a)
	var click_cb := func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_toggle(k)
	pan.gui_input.connect(click_cb)
	pan.mouse_entered.connect(func(): _preview(k))
	card_panels[k] = pan
	return pan

func _preview(k: int) -> void:
	var cd = BOData.CONSPIRATORS[k]
	preview.texture = UI.tex("res://assets/sheets/s%02d.jpg" % k)
	preview_txt.text = "[font_size=28][b][color=#d9b45a]%s[/color][/b][/font_size]  [color=#a89a88]%s – %s[/color]\n[b]Capacità (da Determinato):[/b] %s" % [cd.name, cd.aff, cd.role, cd.text]

func _toggle(k: int) -> void:
	if k in selected:
		selected.erase(k)
	else:
		if selected.size() >= n_consp:
			selected.pop_front()
		selected.append(k)
	_update_sel()

func _update_sel() -> void:
	for k in card_panels:
		var on: bool = k in selected
		var idx := selected.find(k)
		card_panels[k].add_theme_stylebox_override("panel", UI.sbox(Color("3a2218") if on else UI.PANEL, UI.PCOLORS[idx] if on else UI.BORDER, 3 if on else 1, 8, 6))
	start_btn.disabled = selected.size() != n_consp
	var miss := n_consp - selected.size()
	start_btn.text = "Inizia la partita" if miss == 0 else "Scegli ancora %d cospirator%s" % [miss, "e" if miss == 1 else "i"]
	for j in range(n_btns.size()):
		n_btns[j].button_pressed = j + 2 == n_consp
	var nomi := ["", "", "due", "tre", "quattro", "cinque"]
	if title_lbl:
		title_lbl.text = "Scegli i tuoi %s cospiratori" % nomi[n_consp]

func _set_n(k: int) -> void:
	n_consp = k
	while selected.size() > n_consp:
		selected.pop_front()
	_update_sel()

func _random_pick() -> void:
	selected = []
	while selected.size() < n_consp:
		var k := randi() % BOData.CONSPIRATORS.size()
		if not (k in selected):
			selected.append(k)
	_update_sel()
	_preview(selected[0])

# ---------------------------------------------------------------------
# Avvio
# ---------------------------------------------------------------------
func _start_new() -> void:
	if selected.size() != n_consp:
		return
	var g := BOGame.new()
	g.new_game(selected.duplicate(), diff, variants.duplicate(), 0)
	_launch(g)

func continue_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var g := BOGame.new()
	if not g.load_text(txt):
		return
	if g.s.log.size() > 0 and str(g.s.log[-1]).begins_with("────"):
		g.s.log.pop_back()
	_launch(g)

func _launch(g: BOGame) -> void:
	_clear()
	var gv := BOGameView.new()
	screen.add_child(gv)
	gv.quit_to_menu.connect(show_menu)
	gv.restart_requested.connect(show_setup)
	gv.start(g)
