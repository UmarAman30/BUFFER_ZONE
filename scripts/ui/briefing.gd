extends Control
## The briefing book: three tabs (mission, dispatch, pause and controls) shown before the shift starts, and
## again from the pause menu's CONTROLS button. Text comes from data/briefing.json; the diagrams on the
## right-hand page are drawn here.
##
## Keys: left / right (or A / D) turn the page, Enter or Space goes on (and starts the shift on the
## last tab), Esc skips the briefing (or closes the book when opened from the pause menu).

signal closed

const C := preload("res://scripts/ui/ui_colors.gd")
const BOOK_POS := Vector2(170, 172)   # tabs + book centred on the 1080 screen
const BOOK_SIZE := Vector2(1580, 800)
const ART_POS := Vector2(840, 60)
const ART_SIZE := Vector2(690, 640)
const TAB_COLORS := [Color(0.55, 1.0, 0.65), Color(1.0, 0.85, 0.2), Color(0.4, 0.75, 1.0)]

## True when opened from the pause menu: no "skip", the last button just closes the book.
var reference: bool = false

var _tab: int = 0
var _pages: Array = []
var _tab_buttons: Array[Button] = []
var _title: Label
var _body: RichTextLabel
var _art: Control
var _prev: Button
var _next: Button
var _counter: Label
var _book_style: StyleBoxFlat
var _frame: Control
var _team_icons: Array[TextureRect] = []   # shown on the DISPATCH page only
var _skip: Button
var _lang_label: Label
var _lang_buttons: Dictionary = {}   # "en" / "tr" -> Button, shown on the CONTROLS page only
const LANGS := [["en", "ENGLISH"], ["tr", "TÜRKÇE"]]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while the pause menu has the tree paused
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind the book can be clicked
	_pages = _load_pages()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var book := Panel.new()
	book.position = BOOK_POS
	book.size = BOOK_SIZE
	_book_style = C.dialog_style(C.TEXT, 0.0)
	book.add_theme_stylebox_override("panel", _book_style)
	add_child(book)
	_frame = C.add_frame(book, C.TEXT)

	# The spine between the two pages.
	var spine := ColorRect.new()
	spine.color = Color(C.DIM, 0.9)
	spine.position = Vector2(BOOK_SIZE.x * 0.5 - 2.0, 36.0)
	spine.size = Vector2(4.0, BOOK_SIZE.y - 150.0)
	book.add_child(spine)

	# Tabs along the top edge, like bookmarks.
	for i in _pages.size():
		var tab := _button(self, str(_pages[i]["tab"]), BOOK_POS + Vector2(40.0 + i * 330.0, -62.0), Vector2(320, 64), 28)
		tab.pressed.connect(_select.bind(i))
		_tab_buttons.append(tab)
	var skip_text := Loc.t("CLOSE   [ESC]") if reference else Loc.t("SKIP BRIEFING   [ESC]")
	var skip := _button(self, skip_text, BOOK_POS + Vector2(BOOK_SIZE.x - 420.0, -62.0), Vector2(420, 64), 26)
	skip.add_theme_color_override("font_color", C.DIM.lightened(0.7))
	skip.pressed.connect(_finish)
	_skip = skip

	_title = Label.new()
	_title.position = Vector2(70, 36)
	_title.size = Vector2(BOOK_SIZE.x * 0.5 - 130.0, 70)
	_title.add_theme_font_size_override("font_size", 48)
	book.add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.position = Vector2(70, 120)
	_body.size = Vector2(BOOK_SIZE.x * 0.5 - 130.0, BOOK_SIZE.y - 270.0)
	_body.add_theme_font_size_override("normal_font_size", 31)
	_body.add_theme_font_size_override("bold_font_size", 31)
	_body.add_theme_constant_override("line_separation", 2)
	_body.add_theme_color_override("default_color", C.WHITE)
	book.add_child(_body)

	_art = Control.new()
	_art.position = ART_POS
	_art.size = ART_SIZE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel-art team icons
	_art.draw.connect(_draw_art)
	book.add_child(_art)
	for unit_type: String in ["quick_deploy", "earthquake", "emf"]:
		var icon := TextureRect.new()
		icon.texture = C.load_texture("res://assets/images/team_icons/%s.png" % unit_type)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(48, 48)
		icon.position = Vector2(40, 102 + _team_icons.size() * 100.0) - icon.size * 0.5
		_art.add_child(icon)
		_team_icons.append(icon)

	var footer_y := BOOK_SIZE.y - 96.0
	_prev = _button(book, Loc.t("<  BACK"), Vector2(70, footer_y), Vector2(260, 68), 30)
	_prev.pressed.connect(_step.bind(-1))
	_next = _button(book, Loc.t("NEXT  >"), Vector2(BOOK_SIZE.x - 70.0 - 360.0, footer_y), Vector2(360, 68), 30)
	_next.pressed.connect(_step.bind(1))
	_counter = Label.new()
	_counter.position = Vector2(BOOK_SIZE.x * 0.5 - 150.0, footer_y + 8.0)
	_counter.size = Vector2(300, 50)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", 30)
	_counter.add_theme_color_override("font_color", C.DIM.lightened(0.7))
	book.add_child(_counter)

	# Language switch on the CONTROLS page (bottom of the left-hand page).
	_lang_label = Label.new()
	_lang_label.position = Vector2(70, 566)
	_lang_label.size = Vector2(500, 40)
	_lang_label.add_theme_font_size_override("font_size", 22)
	_lang_label.add_theme_color_override("font_color", C.YELLOW)
	book.add_child(_lang_label)
	for i in LANGS.size():
		var code: String = LANGS[i][0]
		var chip := _button(book, str(LANGS[i][1]), Vector2(70 + i * 250.0, 612), Vector2(230, 58), 24)
		chip.pressed.connect(_set_language.bind(code))
		_lang_buttons[code] = chip
	Loc.language_changed.connect(_on_language_changed)

	_select(0, false)


func _load_pages() -> Array:
	var file := FileAccess.open(Loc.data_path("res://data/en/briefing.json"), FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and (data as Dictionary).get("tabs") is Array:
			return (data as Dictionary)["tabs"]
	return [{"tab": "BRIEFING", "title": "BRIEFING", "body": ["Keep public trust above zero for 10 minutes."]}]


func _button(parent: Control, text: String, at: Vector2, button_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", C.TEXT)
	button.add_theme_color_override("font_hover_color", C.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(C.DIM, 0.8))
	var normal := C.box(Color(C.PANEL, 1.0), C.TEXT, 2)
	var hover := C.box(C.PANEL.lightened(0.15), C.WHITE, 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", C.box(Color(C.PANEL, 0.5), Color(C.DIM, 0.6), 2))
	parent.add_child(button)
	return button


func _select(index: int, sound: bool = true) -> void:
	_tab = clampi(index, 0, _pages.size() - 1)
	var page: Dictionary = _pages[_tab]
	var accent: Color = TAB_COLORS[_tab % TAB_COLORS.size()]
	_title.text = str(page["title"])
	_title.add_theme_color_override("font_color", accent)
	_body.text = "\n".join(PackedStringArray(page["body"]))
	_book_style.border_color = Color(accent, 0.8)
	_frame.accent = accent
	for i in _tab_buttons.size():
		var active := i == _tab
		var color: Color = TAB_COLORS[i % TAB_COLORS.size()] if active else C.DIM.lightened(0.5)
		var button := _tab_buttons[i]
		button.add_theme_color_override("font_color", color)
		var style := C.box(C.PANEL.lightened(0.14) if active else C.PANEL, color, 4 if active else 2)
		button.add_theme_stylebox_override("normal", style)
	_prev.disabled = _tab == 0
	var last := _tab == _pages.size() - 1
	_next.text = (Loc.t("CLOSE") if reference else Loc.t("START SHIFT")) if last else Loc.t("NEXT  >")
	_next.add_theme_color_override("font_color", C.GREEN if last else C.TEXT)
	_counter.text = Loc.t("PAGE  %d / %d") % [_tab + 1, _pages.size()]
	for icon in _team_icons:
		icon.visible = _tab == 1
	_refresh_language_row()
	_art.queue_redraw()
	if sound:
		EventBus.sfx_requested.emit("screen_switch")


func _set_language(code: String) -> void:
	if code == Loc.lang:
		return
	EventBus.sfx_requested.emit("ui_click")
	Loc.set_language(code)


## The whole book is rebuilt in the new language, staying on the same tab.
func _on_language_changed(_lang: String) -> void:
	_pages = _load_pages()
	for i in mini(_tab_buttons.size(), _pages.size()):
		_tab_buttons[i].text = str(_pages[i]["tab"])
	_skip.text = Loc.t("CLOSE   [ESC]") if reference else Loc.t("SKIP BRIEFING   [ESC]")
	_prev.text = Loc.t("<  BACK")
	_select(_tab, false)


func _refresh_language_row() -> void:
	var on_controls := _tab == 2 and reference   # pause menu only
	_lang_label.visible = on_controls
	_lang_label.text = Loc.t("LANGUAGE")
	for code: String in _lang_buttons:
		var chip: Button = _lang_buttons[code]
		chip.visible = on_controls
		var active: bool = code == Loc.lang
		chip.add_theme_stylebox_override("normal", C.box(C.TEXT if active else C.PANEL, C.TEXT, 2))
		chip.add_theme_stylebox_override("hover", C.box(C.TEXT if active else C.PANEL.lightened(0.15), C.WHITE, 2))
		chip.add_theme_color_override("font_color", C.BG if active else C.TEXT)
		chip.add_theme_color_override("font_hover_color", C.BG if active else C.WHITE)


func _step(direction: int) -> void:
	if direction > 0 and _tab == _pages.size() - 1:
		_finish()
	else:
		_select(_tab + direction)


func _finish() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_LEFT, KEY_A:
				_step(-1)
			KEY_RIGHT, KEY_D:
				_step(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_step(1)
			KEY_ESCAPE:
				_finish()
	get_viewport().set_input_as_handled()   # the game behind the book hears no keys


# ---------------------------------------------------------------- diagrams (right-hand page)

func _text(at: Vector2, text: String, font_size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_art.draw_string(_art.get_theme_default_font(), at, text, align, width, font_size, color)


func _label(at: Vector2, text: String) -> void:
	_text(at, text, 28, C.DIM.lightened(0.7))
	_art.draw_line(at + Vector2(0, 8), at + Vector2(ART_SIZE.x, 8), Color(C.DIM, 0.8), 2.0)


func _chip(rect: Rect2, text: String, color: Color, font_size: int = 28) -> void:
	_art.draw_rect(rect, Color(color, 0.12))
	_art.draw_rect(rect, color, false, 2.0)
	_text(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + font_size * 0.3), text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _hexagon(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 7:
		var angle := PI / 6.0 + k * PI / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_art() -> void:
	match _tab:
		0:
			_draw_mission()
		1:
			_draw_dispatch()
		_:
			_draw_controls()


func _draw_mission() -> void:
	_label(Vector2(0, 30), Loc.t("YOUR TOP BAR"))
	var hud := Rect2(0, 60, ART_SIZE.x, 150)
	_art.draw_rect(hud, Color(C.PANEL, 0.9))
	_art.draw_rect(hud, C.TEXT, false, 2.0)
	_text(Vector2(20, 96), Loc.t("PUBLIC TRUST"), 26, C.TEXT)
	var bar := Rect2(20, 108, 400, 34)
	_art.draw_rect(bar, C.PANEL)
	_art.draw_rect(Rect2(bar.position, Vector2(bar.size.x * 0.72, bar.size.y)), C.GREEN)
	_art.draw_rect(bar, C.DIM, false, 3.0)
	_text(Vector2(20, 184), Loc.t("zero trust = shift over"), 26, C.DIM.lightened(0.7))
	_text(Vector2(450, 96), Loc.t("SURVIVED"), 26, C.TEXT)
	_text(Vector2(450, 150), "00:00", 52, C.WHITE)
	_text(Vector2(450, 192), Loc.t("goal: 10:00"), 26, C.YELLOW)

	_label(Vector2(0, 270), Loc.t("ALERTS GET WORSE OVER TIME"))
	var xs := [110.0, 345.0, 580.0]
	var colors := [C.GREEN, C.YELLOW, C.RED]
	var names := [Loc.t("GREEN"), Loc.t("YELLOW"), Loc.t("RED")]
	var pays := [Loc.t("most trust"), Loc.t("less trust"), Loc.t("least trust")]
	for i in 3:
		var center := Vector2(xs[i], 345)
		_alert_marker(center, 34.0, colors[i])
		_text(Vector2(center.x - 100, 415), names[i], 30, colors[i], HORIZONTAL_ALIGNMENT_CENTER, 200.0)
		_text(Vector2(center.x - 110, 445), pays[i], 24, C.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 220.0)
		if i < 2:
			var from_x := center.x + 56.0
			var to_x: float = xs[i + 1] - 56.0
			_art.draw_line(Vector2(from_x, 345), Vector2(to_x, 345), C.DIM.lightened(0.6), 3.0)
			_art.draw_colored_polygon(PackedVector2Array([Vector2(to_x, 345), Vector2(to_x - 14, 335), Vector2(to_x - 14, 355)]), C.DIM.lightened(0.6))
	_text(Vector2(0, 482), Loc.t("a red alert left alone runs out and costs trust"), 24, C.RED, HORIZONTAL_ALIGNMENT_CENTER, ART_SIZE.x)

	_label(Vector2(0, 530), Loc.t("THE LIVE FEED  (RIGHT-CLICK)"))
	var left := Rect2(0, 548, 200, 40)
	var right := Rect2(210, 548, ART_SIZE.x - 210, 40)
	_chip(left, Loc.t("SECTOR"), C.TEXT, 24)
	_chip(right, Loc.t("REPORT"), C.TEXT, 24)
	_art.draw_rect(Rect2(0, 596, 200, 44), C.TEXT)
	_text(Vector2(0, 627), "SHORELINE", 26, C.BG, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	_text(Vector2(222, 627), Loc.t("Water over the Harbour Piers!"), 26, C.WHITE)


## Small alert marker like the ones on the map (a triangle with an exclamation mark).
func _alert_marker(center: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 1.05, r * 0.8), center + Vector2(-r * 1.05, r * 0.8)])
	_art.draw_colored_polygon(points, Color(color, 0.22))
	var outline := points.duplicate()
	outline.append(points[0])
	_art.draw_polyline(outline, color, 3.0)
	_art.draw_rect(Rect2(center + Vector2(-2.5, -r * 0.4), Vector2(5, r * 0.6)), color)
	_art.draw_rect(Rect2(center + Vector2(-2.5, r * 0.32), Vector2(5, 5)), color)


## A team's map icon inside a ring of its colour.
func _team_icon(center: Vector2, r: float, unit_type: String) -> void:
	var color: Color = C.TEAM_COLORS.get(unit_type, C.TEXT)
	_art.draw_circle(center, r, Color(C.BG, 0.95))
	_art.draw_arc(center, r, 0.0, TAU, 40, color, 4.0)   # the icon itself is a TextureRect on top (see _ready)


func _draw_dispatch() -> void:
	_label(Vector2(0, 30), Loc.t("YOUR TEAMS AND WHAT THEY HANDLE"))
	var teams := [
		[Loc.t("RAPID RESPONSE"), Loc.t("wildfires, riots, crashes,"), Loc.t("evacuations"), "quick_deploy"],
		[Loc.t("HEAVY RESCUE"), Loc.t("earthquakes, landslides, floods,"), Loc.t("storms, eruptions"), "earthquake"],
		[Loc.t("HAZMAT & GRID"), Loc.t("chemical leaks, reactor trouble,"), Loc.t("power surges"), "emf"],
	]
	for i in 3:
		var y := 60.0 + i * 100.0
		var color: Color = C.TEAM_COLORS.get(teams[i][3], C.TEXT)
		_team_icon(Vector2(40, y + 42), 36.0, teams[i][3])
		_text(Vector2(96, y + 28), teams[i][0], 34, color)
		_text(Vector2(96, y + 58), teams[i][1], 25, C.WHITE)
		_text(Vector2(96, y + 84), teams[i][2], 25, C.WHITE)

	_label(Vector2(0, 392), Loc.t("WHEN THE TEAM ARRIVES"))
	var rows := [
		[C.GREEN, Loc.t("RIGHT TEAM"), Loc.t("fixes it at once, full trust")],
		[C.DIM.lightened(0.5), Loc.t("CLOSE TEAM"), Loc.t("marker turns gray while they work, slower, half trust")],
		[C.RED, Loc.t("WRONG TEAM"), Loc.t("they fail and get stuck, trust lost, alert stays open")],
	]
	for i in 3:
		var y := 432.0 + i * 70.0
		var color: Color = rows[i][0]
		_alert_marker(Vector2(26, y + 12), 20.0, color)
		if i == 0:
			_art.draw_polyline(PackedVector2Array([Vector2(44, y + 6), Vector2(52, y + 16), Vector2(68, y - 4)]), C.GREEN, 4.0)
		elif i == 2:
			_art.draw_line(Vector2(46, y - 4), Vector2(66, y + 16), C.RED, 4.0)
			_art.draw_line(Vector2(66, y - 4), Vector2(46, y + 16), C.RED, 4.0)
		_text(Vector2(84, y + 10), rows[i][1], 30, color)
		_text(Vector2(84, y + 40), rows[i][2], 24, C.WHITE)


## A keyboard key cap with a label.
func _key(rect: Rect2, label: String, color: Color = C.WHITE) -> void:
	_art.draw_rect(Rect2(rect.position + Vector2(0, 6), rect.size), Color(0, 0, 0, 0.5))
	_art.draw_rect(rect, Color(C.PANEL.lightened(0.12), 1.0))
	_art.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), Color(1, 1, 1, 0.12))
	_art.draw_rect(rect, color, false, 2.0)
	_text(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 10.0), label, 30, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


## A small mouse with one button lit (right = true lights the right button).
func _mouse(center: Vector2, right: bool) -> void:
	var body := Rect2(center - Vector2(22, 32), Vector2(44, 64))
	_art.draw_rect(body, C.PANEL)
	var lit := Rect2(body.position + Vector2(22 if right else 0, 0), Vector2(22, 26))
	_art.draw_rect(lit, Color(C.YELLOW, 0.7))
	_art.draw_rect(body, C.TEXT, false, 2.0)
	_art.draw_line(body.position + Vector2(0, 26), body.position + Vector2(44, 26), C.TEXT, 2.0)
	_art.draw_line(body.position + Vector2(22, 0), body.position + Vector2(22, 26), C.TEXT, 2.0)


func _draw_controls() -> void:
	_label(Vector2(0, 30), Loc.t("THE PAUSE MENU"))
	var card := Rect2(150, 54, 390, 262)
	_art.draw_rect(card, Color(C.BG, 0.95))
	_art.draw_rect(card, C.YELLOW, false, 2.0)
	_text(Vector2(card.position.x, 98), Loc.t("PAUSED"), 36, C.YELLOW, HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	var names := [Loc.t("RESUME"), Loc.t("CONTROLS"), Loc.t("RESTART"), Loc.t("MAIN MENU")]
	for i in names.size():
		var row := Rect2(card.position.x + 40, 116 + i * 48, card.size.x - 80, 40)
		var active := i == 1
		_art.draw_rect(row, Color(C.YELLOW, 0.18) if active else C.PANEL)
		var ink: Color = C.YELLOW if active else (C.RED if i == 3 else C.TEXT)
		_art.draw_rect(row, ink, false, 3.0 if active else 2.0)
		_text(Vector2(row.position.x, row.position.y + 30), names[i], 26, ink, HORIZONTAL_ALIGNMENT_CENTER, row.size.x)
	var arrow := Vector2(card.end.x + 14, 184)
	_art.draw_colored_polygon(PackedVector2Array([arrow, arrow + Vector2(22, -14), arrow + Vector2(22, 14)]), C.YELLOW)
	_text(Vector2(card.end.x + 42, 193), Loc.t("this book"), 26, C.YELLOW)

	_label(Vector2(0, 350), Loc.t("QUICK KEYS"))
	var rows := [
		["ESC", Loc.t("pause the shift")],
		["", Loc.t("open or close the live feed")],
		["1  2  3", Loc.t("pick a team")],
		["SHIFT", Loc.t("+ click a sector: landmarks")],
	]
	for i in rows.size():
		var y := 372.0 + i * 68.0
		if i == 1:
			_mouse(Vector2(70, y + 28), true)
		else:
			_key(Rect2(0, y, 140, 52), rows[i][0], C.YELLOW if i == 0 else C.WHITE)
		_text(Vector2(170, y + 36), rows[i][1], 28, C.WHITE)
