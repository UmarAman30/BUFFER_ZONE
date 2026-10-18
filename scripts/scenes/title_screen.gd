extends Control
## Start screen. Shown on the monitor with its power lamp in standby (red). A tactical-display
## shader runs behind the game's title, and four "programs" are listed like files on a terminal:
## START.EXE, LANGUAGE.EXE, CREDITS.EXE and QUIT.EXE. Mouse hover or the arrow keys highlight one;
## click / Enter runs it with a little command-line sequence. START turns the lamp green and
## switches the monitor over to the intro terminal; QUIT powers the monitor off and closes the game.

const TITLE := "BUFFER ZONE"
const SUBTITLE := "KIRANCHI  EMERGENCY  OPERATIONS  CENTER"
const BG_SHADER := preload("res://assets/shaders/title_bg.gdshader")
const CRT_SHADER := preload("res://assets/shaders/crt.gdshader")
const NEXT_SCENE := "res://scenes/intro_terminal.tscn"
const CreditsScript := preload("res://scripts/ui/credits_panel.gd")
const GREEN := Color(0.30, 0.95, 0.50)
const BRIGHT := Color(0.80, 1.0, 0.86)
const DARK := Color(0.01, 0.05, 0.03)
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.3, 0.28)
const ITEMS := [
	["START.EXE", "begin your shift", "2.4 MB"],
	["LANGUAGE.EXE", "change the language", "0.3 MB"],
	["CREDITS.EXE", "the people behind EOC-9", "0.1 MB"],
	["QUIT.EXE", "close the terminal", "0.0 MB"],
]
const ROW_W := 700.0
const ROW_H := 66.0
const ROW_GAP := 14.0
const MENU_Y := 588.0
const SCRAMBLE := "#%&@$*01X/<>?"

var _bg: ColorRect
var _bg_material: ShaderMaterial
var _title_view: Control
var _menu: Control
var _console: Control
var _credits: Control
var _flash: ColorRect
var _title_font: Font
var _body_font: Font

var _clock: float = 0.0
var _selected: int = 0
var _busy: bool = true         # booting or running a program: no menu input
var _glitch: float = 0.0
var _next_glitch: float = 4.0
var _lines: Array = []         # console lines: [text, color]
var _progress: float = -1.0    # console progress bar, -1 = hidden
var _console_show: float = 0.0
var _chip_hover: String = ""   # language chip under the mouse ("en" / "tr")
const LANG_ROW := 1
const LANGS := [["en", "ENGLISH"], ["tr", "TÜRKÇE"]]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Monitor.standby = true
	_title_font = load("res://assets/fonts/HomeVideo-Regular.ttf") as Font
	_body_font = load("res://assets/fonts/VT323-Regular.ttf") as Font

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_material = ShaderMaterial.new()
	_bg_material.shader = BG_SHADER
	_bg_material.set_shader_parameter("boot", 0.0)
	_bg.material = _bg_material
	add_child(_bg)

	_title_view = _layer(_draw_title)
	_menu = _layer(_draw_menu)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.gui_input.connect(_on_menu_input)
	_console = _layer(_draw_console)
	_credits = CreditsScript.new()
	add_child(_credits)

	var crt := ColorRect.new()
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_material := ShaderMaterial.new()
	crt_material.shader = CRT_SHADER
	crt.material = crt_material
	add_child(crt)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.8, 1.0, 0.85, 0.0)
	add_child(_flash)

	await get_tree().create_timer(1.6).timeout
	_busy = false


func _layer(painter: Callable) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(painter)
	add_child(layer)
	return layer


func _process(delta: float) -> void:
	_clock += delta
	_bg_material.set_shader_parameter("time_s", _clock)
	_bg_material.set_shader_parameter("boot", clampf(_clock / 1.0, 0.0, 1.0))
	# Now and then the title tears for a moment.
	if _clock > _next_glitch:
		_glitch = 1.0
		_next_glitch = _clock + randf_range(3.5, 7.0)
	_glitch = move_toward(_glitch, 0.0, delta * 6.0)
	_bg_material.set_shader_parameter("glitch", _glitch * 0.4)
	_console_show = move_toward(_console_show, 1.0 if not _lines.is_empty() else 0.0, delta * 6.0)
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 2.5)
	_title_view.queue_redraw()
	_menu.queue_redraw()
	_console.queue_redraw()


# ---------------------------------------------------------------- input

func _row_rect(index: int) -> Rect2:
	return Rect2((1920.0 - ROW_W) * 0.5, MENU_Y + index * (ROW_H + ROW_GAP), ROW_W, ROW_H)


func _on_menu_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		_chip_hover = _chip_at(at)
		for i in ITEMS.size():
			if _row_rect(i).has_point(at):
				_select(i)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var chip := _chip_at(mouse.position)
			if chip != "":
				_pick_language(chip)
				return
			for i in ITEMS.size():
				if _row_rect(i).has_point(mouse.position):
					_select(i)
					_run(i)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_UP or key == KEY_W:
		_select(posmod(_selected - 1, ITEMS.size()))
	elif key == KEY_DOWN or key == KEY_S:
		_select(posmod(_selected + 1, ITEMS.size()))
	elif (key == KEY_LEFT or key == KEY_A) and _selected == LANG_ROW:
		_pick_language("en")
	elif (key == KEY_RIGHT or key == KEY_D) and _selected == LANG_ROW:
		_pick_language("tr")
	elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		_run(_selected)
	get_viewport().set_input_as_handled()


func _select(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	AudioManager.play("key_clack")


# ---------------------------------------------------------------- language chips

## The two clickable language chips at the right end of the LANGUAGE.EXE row.
func _chip_rects() -> Array[Rect2]:
	var row := _row_rect(LANG_ROW)
	var rects: Array[Rect2] = []
	var x := row.end.x - 18.0
	for i in range(LANGS.size() - 1, -1, -1):
		var w := _body_font.get_string_size(str(LANGS[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 28.0
		x -= w
		rects.push_front(Rect2(x, row.position.y + 12, w, row.size.y - 24))
		x -= 10.0
	return rects


func _chip_at(point: Vector2) -> String:
	var rects := _chip_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return str(LANGS[i][0])
	return ""


## Clicking a chip switches the language at once: a small glitch and a click.
func _pick_language(code: String) -> void:
	_select(LANG_ROW)
	if code == Loc.lang:
		return
	Loc.set_language(code)
	AudioManager.play("code_accept")
	_glitch = 0.6


# ---------------------------------------------------------------- running a program

func _run(index: int) -> void:
	_busy = true
	AudioManager.play("ui_click")
	_lines.clear()
	_progress = -1.0
	var program: String = ITEMS[index][0]
	match program:
		"START.EXE":
			Monitor.standby = false   # power lamp: standby red -> on green
			AudioManager.play("code_accept")
			await _type("C:\\EOC> " + Loc.t(program), BRIGHT)
			await _type(Loc.t("Loading dispatch kernel ........ OK"), GREEN)
			await _type(Loc.t("Mounting sector map ............ OK"), GREEN)
			await _type(Loc.t("Linking field units ............ OK"), GREEN)
			await _fill_progress(1.0)
			await _type(Loc.t("LAUNCHING SHIFT"), AMBER)
			await _shutdown()
			get_tree().change_scene_to_file(NEXT_SCENE)
		"LANGUAGE.EXE":
			await _type("C:\\EOC> " + Loc.t(program), BRIGHT)
			var next_lang := "tr" if Loc.lang == "en" else "en"
			Loc.set_language(next_lang)
			AudioManager.play("code_accept")
			await _type("DİL: TÜRKÇE" if next_lang == "tr" else "LANGUAGE: ENGLISH", AMBER)
			await get_tree().create_timer(0.9).timeout
			_lines.clear()
			_busy = false
		"CREDITS.EXE":
			await _type("C:\\EOC> " + Loc.t(program), BRIGHT)
			await _type(Loc.t("Reading credits file ........... OK"), GREEN)
			AudioManager.play("code_accept")
			await get_tree().create_timer(0.25).timeout
			_credits.open()
			await _credits.closed
			_lines.clear()
			_busy = false
		"QUIT.EXE":
			await _type("C:\\EOC> " + Loc.t(program), BRIGHT)
			await _type(Loc.t("Closing secure session ......... OK"), GREEN)
			await _fill_progress(0.5)
			await _type(Loc.t("Goodbye, officer."), AMBER)
			await _shutdown()
			get_tree().quit()
		_:
			await _type("C:\\EOC> " + Loc.t(program), BRIGHT)
			AudioManager.play("failure_buzzer")
			await _type(Loc.t("ERROR: MODULE NOT INSTALLED"), RED)
			await get_tree().create_timer(1.3).timeout
			_lines.clear()
			_busy = false


## Adds a console line, typed out character by character.
func _type(text: String, color: Color) -> void:
	_lines.append(["", color])
	var line: Array = _lines.back()
	for i in text.length():
		line[0] = text.substr(0, i + 1)
		if i % 3 == 0:
			AudioManager.play("type_blip")
		await get_tree().create_timer(0.014).timeout
	await get_tree().create_timer(0.12).timeout


func _fill_progress(duration: float) -> void:
	_progress = 0.0
	var steps := 24
	for i in steps:
		_progress = float(i + 1) / steps
		if i % 4 == 0:
			AudioManager.play("key_clack")
		await get_tree().create_timer(duration / steps * randf_range(0.5, 1.5)).timeout
	await get_tree().create_timer(0.15).timeout


## Glitch, flash, then the monitor's CRT switch-off.
func _shutdown() -> void:
	_glitch = 1.0
	_bg_material.set_shader_parameter("glitch", 1.0)
	AudioManager.play("static_burst")
	await get_tree().create_timer(0.3).timeout
	_flash.color.a = 0.8
	await Monitor.power_off()


# ---------------------------------------------------------------- drawing

## ENGLISH / TÜRKÇE chips; the active language is filled. `on_green` = drawn on the highlighted row.
func _draw_chips(view: Control, on_green: bool) -> void:
	var rects := _chip_rects()
	for i in rects.size():
		var code := str(LANGS[i][0])
		var active := code == Loc.lang
		var hover := code == _chip_hover
		var ink := DARK if on_green else GREEN
		if active:
			view.draw_rect(rects[i], DARK if on_green else AMBER)
			view.draw_string(_body_font, Vector2(rects[i].position.x, rects[i].position.y + 31), str(LANGS[i][1]), HORIZONTAL_ALIGNMENT_CENTER, rects[i].size.x, 30, GREEN if on_green else DARK)
		else:
			if hover:
				view.draw_rect(rects[i], Color(ink, 0.18))
			view.draw_rect(rects[i], Color(ink, 0.9 if hover else 0.55), false, 2.0)
			view.draw_string(_body_font, Vector2(rects[i].position.x, rects[i].position.y + 31), str(LANGS[i][1]), HORIZONTAL_ALIGNMENT_CENTER, rects[i].size.x, 30, Color(ink, 1.0 if hover else 0.75))


## Right-hand column of a menu row: the file size, or the current language on LANGUAGE.EXE.
func _right_column(index: int) -> String:
	if ITEMS[index][0] == "LANGUAGE.EXE":
		return "TÜRKÇE" if Loc.is_turkish() else "ENGLISH"
	return str(ITEMS[index][2])


func _draw_title() -> void:
	var view := _title_view
	var font := _title_font if _title_font != null else view.get_theme_default_font()
	var font_size := 190
	var reveal := clampf((_clock - 0.35) / 0.9, 0.0, 1.0)
	var total := font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := (1920.0 - total) * 0.5
	var baseline := 420.0
	var jitter := _glitch * 10.0
	# Small classified tag above the title.
	var tag := Loc.t("[ EOC-9  SECURE  TERMINAL ]")
	view.draw_string(_body_font, Vector2(0, 228), tag, HORIZONTAL_ALIGNMENT_CENTER, 1920, 34, Color(AMBER, 0.85 * reveal))
	for i in TITLE.length():
		var ch := TITLE[i]
		var advance := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if ch != " ":
			var shown := ch
			var settled := reveal >= float(i + 1) / TITLE.length()
			if not settled:
				shown = SCRAMBLE[randi() % SCRAMBLE.length()] if reveal > float(i) / TITLE.length() * 0.6 else ""
			if shown != "":
				var at := Vector2(x, baseline) + Vector2(randf_range(-jitter, jitter), 0.0)
				# Soft phosphor glow.
				for k in 12:
					var offset := Vector2.RIGHT.rotated(k * TAU / 12.0) * 7.0
					view.draw_string(font, at + offset, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(GREEN, 0.05))
				# Colour fringe, wider while glitching.
				var split := 3.0 + _glitch * 9.0
				view.draw_string(font, at + Vector2(-split, 0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.2, 0.3, 0.45))
				view.draw_string(font, at + Vector2(split, 0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.2, 0.9, 1.0, 0.4))
				view.draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BRIGHT if settled else GREEN)
		x += advance
	# Rules either side of the subtitle.
	var sub_size := 34
	var subtitle := Loc.t(SUBTITLE)
	var sub_w := _body_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
	var sub_alpha := clampf((_clock - 1.1) / 0.4, 0.0, 1.0)
	var y := 478.0
	view.draw_string(_body_font, Vector2(0, y + 10), subtitle, HORIZONTAL_ALIGNMENT_CENTER, 1920, sub_size, Color(GREEN, 0.9 * sub_alpha))
	var left_end := (1920.0 - sub_w) * 0.5 - 24.0
	var right_start := (1920.0 + sub_w) * 0.5 + 24.0
	var reach := 260.0 * sub_alpha
	view.draw_line(Vector2(left_end - reach, y), Vector2(left_end, y), Color(GREEN, 0.6), 2.0)
	view.draw_line(Vector2(right_start, y), Vector2(right_start + reach, y), Color(GREEN, 0.6), 2.0)
	# Footer hints.
	var hint_alpha := clampf((_clock - 1.8) / 0.5, 0.0, 1.0)
	view.draw_string(_body_font, Vector2(0, 1010), Loc.t("ARROW KEYS OR MOUSE TO SELECT  -  ENTER OR CLICK TO RUN"), HORIZONTAL_ALIGNMENT_CENTER, 1920, 28, Color(GREEN, 0.55 * hint_alpha))
	var clock_text := Time.get_time_string_from_system()
	view.draw_string(_body_font, Vector2(60, 70), "EOC-9  -  v1.04", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(GREEN, 0.6 * hint_alpha))
	view.draw_string(_body_font, Vector2(0, 70), clock_text + "   ", HORIZONTAL_ALIGNMENT_RIGHT, 1860, 30, Color(GREEN, 0.6 * hint_alpha))


func _draw_menu() -> void:
	var view := _menu
	var blink := fmod(_clock, 0.8) < 0.5
	for i in ITEMS.size():
		var appear := clampf((_clock - 1.15 - i * 0.12) / 0.25, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var rect := _row_rect(i)
		var label: String = Loc.t(ITEMS[i][0])
		var typed := label.substr(0, ceili(label.length() * appear))
		var selected := i == _selected and not (_busy and _clock < 1.6)
		if selected:
			var pulse := 0.85 + 0.15 * sin(_clock * 6.0)
			view.draw_rect(rect, Color(GREEN, 0.9 * pulse))
			view.draw_rect(rect.grow(5.0), Color(GREEN, 0.35), false, 2.0)
			# Arrow cursor.
			var tip := Vector2(rect.position.x + 34, rect.get_center().y)
			if blink:
				view.draw_colored_polygon(PackedVector2Array([tip + Vector2(-12, -13), tip + Vector2(6, 0), tip + Vector2(-12, 13)]), DARK)
			view.draw_string(_body_font, Vector2(rect.position.x + 64, rect.position.y + 47), typed, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, DARK)
			if i == LANG_ROW:
				_draw_chips(view, true)
			else:
				view.draw_string(_body_font, Vector2(rect.position.x, rect.position.y + 43), Loc.t(str(ITEMS[i][1])) + "   ", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 28, Color(DARK, 0.8))
		else:
			view.draw_rect(rect, Color(DARK, 0.55))
			view.draw_rect(rect, Color(GREEN, 0.25), false, 1.0)
			view.draw_string(_body_font, Vector2(rect.position.x + 64, rect.position.y + 47), typed, HORIZONTAL_ALIGNMENT_LEFT, -1, 50, Color(GREEN, 0.85))
			if i == LANG_ROW:
				_draw_chips(view, false)
			else:
				view.draw_string(_body_font, Vector2(rect.position.x, rect.position.y + 43), _right_column(i) + "   ", HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x, 26, Color(GREEN, 0.35))


func _draw_console() -> void:
	if _console_show <= 0.0:
		return
	var view := _console
	var box := Rect2(510, 560, 900, 330)
	var shown := Rect2(box.position.x, box.get_center().y - box.size.y * 0.5 * _console_show, box.size.x, box.size.y * _console_show)
	view.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 0.45 * _console_show))
	view.draw_rect(shown, Color(DARK.r, DARK.g, DARK.b, 1.0))
	view.draw_rect(shown, GREEN, false, 2.0)
	if _console_show < 1.0:
		return
	view.draw_rect(Rect2(box.position, Vector2(box.size.x, 40)), GREEN)
	view.draw_string(_body_font, Vector2(box.position.x + 16, box.position.y + 30), Loc.t("EOC-9 COMMAND PROMPT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, DARK)
	var y := box.position.y + 84.0
	for line: Array in _lines:
		view.draw_string(_body_font, Vector2(box.position.x + 28, y), str(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, line[1])
		y += 40.0
	if _progress >= 0.0:
		var bar := Rect2(box.position.x + 28, y - 26, box.size.x - 56, 26)
		view.draw_rect(bar, Color(GREEN, 0.15))
		var cells := 40
		for c in int(cells * _progress):
			var cw := bar.size.x / cells
			view.draw_rect(Rect2(bar.position.x + c * cw + 1, bar.position.y + 2, cw - 2, bar.size.y - 4), GREEN)
		view.draw_rect(bar, GREEN, false, 1.0)
		view.draw_string(_body_font, Vector2(bar.position.x, bar.position.y - 6), "%d%%" % roundi(_progress * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x, 26, GREEN)
	# Block cursor on the last line.
	if fmod(_clock, 0.6) < 0.35 and not _lines.is_empty():
		var last: Array = _lines.back()
		var w := _body_font.get_string_size(str(last[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var cursor_y := box.position.y + 84.0 + (_lines.size() - 1) * 40.0
		view.draw_rect(Rect2(box.position.x + 32 + w, cursor_y - 26, 14, 30), GREEN)
