extends RefCounted
class_name UI
## Stili, font e piccoli costruttori di controlli.

const BG := Color("120d0b")
const PANEL := Color("1d1613")
const PANEL2 := Color("2a201b")
const BORDER := Color("5c3d2b")
const RED := Color("b3261e")
const RED_DARK := Color("6e1712")
const GOLD := Color("d9b45a")
const TEXT := Color("efe6d8")
const MUTED := Color("a89a88")
const GREEN := Color("6fae5a")
const PCOLORS := [Color("d0452f"), Color("3a8fd6"), Color("3fae6a"), Color("d9b43a"), Color("9b59b6")]

static var _fonts := {}
static var _theme: Theme
static var _tex := {}

static func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var paths := {
		"title": "res://assets/fonts/unifrakturmaguntia-latin-400-normal.woff",
		"head": "res://assets/fonts/oswald-latin-600-normal.woff",
		"head2": "res://assets/fonts/oswald-latin-400-normal.woff",
		"body": "res://assets/fonts/crimson-text-latin-400-normal.woff",
		"bold": "res://assets/fonts/crimson-text-latin-700-normal.woff",
		"italic": "res://assets/fonts/crimson-text-latin-400-italic.woff",
	}
	var f: Font = load(paths[name])
	_fonts[name] = f
	return f

static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = load(path)
	_tex[path] = t
	return t

static func sbox(bg: Color, border: Color = BORDER, bw: int = 1, radius: int = 6, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_font("font", "Button", font("head2"))
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.4))
	t.set_stylebox("normal", "Button", sbox(Color("2b1d17"), Color("6b4532"), 1, 5, 12))
	t.set_stylebox("hover", "Button", sbox(Color("4a2a20"), GOLD, 1, 5, 12))
	t.set_stylebox("pressed", "Button", sbox(Color("5e1a14"), GOLD, 2, 5, 12))
	t.set_stylebox("disabled", "Button", sbox(Color("1e1714"), Color("3a2a22"), 1, 5, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", sbox(PANEL, BORDER, 1, 8, 10))
	t.set_stylebox("panel", "TooltipPanel", sbox(Color("201815"), GOLD, 1, 4, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", 18)
	t.set_font("font", "CheckBox", font("body"))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("5c3d2b")
	sb.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", sbox(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 4, 2))
	t.set_stylebox("grabber", "HScrollBar", sb)
	t.set_stylebox("grabber_highlight", "HScrollBar", sb)
	t.set_stylebox("scroll", "HScrollBar", sbox(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 4, 2))
	_theme = t
	return t

static func label(text: String, size: int = 20, color: Color = TEXT, fnt: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(fnt))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, cb: Callable, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

static func accent_button(text: String, cb: Callable, size: int = 20) -> Button:
	var b := button(text, cb, size)
	b.add_theme_stylebox_override("normal", sbox(RED_DARK, Color("c4483c"), 1, 5, 14))
	b.add_theme_stylebox_override("hover", sbox(RED, GOLD, 1, 5, 14))
	b.add_theme_stylebox_override("pressed", sbox(Color("8a1d17"), GOLD, 2, 5, 14))
	return b

static func panel(bg: Color = PANEL, border: Color = BORDER, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sbox(bg, border, 1, 8, margin))
	return p

static func trect(path: String, size: Vector2, keep: bool = true) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep else TextureRect.STRETCH_SCALE
	r.custom_minimum_size = size
	return r

static func face_path(f: String) -> String:
	return "res://assets/dice/%s.png" % f
