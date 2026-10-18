extends Control
## CREDITS.EXE on the title screen: a terminal-style window listing the team and every third-party
## asset with its license. Text comes from data/credits.json (Turkish: data/tr/credits.json).
## It scrolls slowly on its own; the mouse wheel / arrow keys scroll by hand. Esc, Enter or a click
## on BACK closes it.

signal closed

const GREEN := Color(0.30, 0.95, 0.50)
const BRIGHT := Color(0.80, 1.0, 0.86)
const DIM := Color(0.30, 0.95, 0.50, 0.55)
const AMBER := Color(1.0, 0.72, 0.25)
const DARK := Color(0.01, 0.05, 0.03)

const PANEL := Rect2(260, 90, 1400, 900)
const HEADER_H := 96.0
const FOOTER_H := 84.0
const PAD := 56.0
const AUTO_SPEED := 26.0   # pixels per second

var _title_font: Font
var _body_font: Font
var _view: Control
var _rows: Array[Dictionary] = []   # {text, size, color, gap}
var _content_h := 0.0
var _scroll := 0.0
var _auto_wait := 0.0
var _show := 0.0
var _back_hover := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_title_font = load("res://assets/fonts/HomeVideo-Regular.ttf") as Font
	_body_font = load("res://assets/fonts/VT323-Regular.ttf") as Font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_panel)
	add_child(_view)


func open() -> void:
	_build()
	_scroll = 0.0
	_auto_wait = 2.0
	_show = 0.0
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play("ui_click")
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_show = move_toward(_show, 1.0, delta * 5.0)
	if _auto_wait > 0.0:
		_auto_wait -= delta
	else:
		_scroll = minf(_scroll + AUTO_SPEED * delta, _max_scroll())
	_view.queue_redraw()


func _max_scroll() -> float:
	return maxf(0.0, _content_h - (PANEL.size.y - HEADER_H - FOOTER_H) + 30.0)


func _nudge(amount: float) -> void:
	_scroll = clampf(_scroll + amount, 0.0, _max_scroll())
	_auto_wait = 4.0   # the reader took over; pause the auto-scroll for a moment


func _back_rect() -> Rect2:
	return Rect2(PANEL.end.x - PAD - 260.0, PANEL.end.y - FOOTER_H + 16.0, 260.0, 54.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_back_hover = _back_rect().has_point((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				_nudge(60.0)
			MOUSE_BUTTON_WHEEL_UP:
				_nudge(-60.0)
			MOUSE_BUTTON_LEFT:
				if _back_rect().has_point(mouse.position) or not PANEL.has_point(mouse.position):
					close()
	accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var key := (event as InputEventKey).physical_keycode
	match key:
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_BACKSPACE:
			if not event.echo:
				close()
		KEY_DOWN, KEY_S:
			_nudge(50.0)
		KEY_UP, KEY_W:
			_nudge(-50.0)
		KEY_PAGEDOWN:
			_nudge(400.0)
		KEY_PAGEUP:
			_nudge(-400.0)
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- content

func _build() -> void:
	_rows.clear()
	var data: Dictionary = {}
	var file := FileAccess.open(Loc.data_path("res://data/en/credits.json"), FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			data = parsed
	var width := PANEL.size.x - PAD * 2.0
	_add(str(data.get("subtitle", "")), 30, DIM, 0.0, width)
	for section: Dictionary in data.get("sections", []):
		_add(Loc.upper(str(section.get("heading", ""))), 40, AMBER, 34.0, width)
		for entry: Dictionary in section.get("entries", []):
			_add(str(entry.get("name", "")), 36, BRIGHT, 12.0, width)
			_add(str(entry.get("detail", "")), 30, GREEN, 0.0, width - 30.0, 30.0)
			var link := str(entry.get("link", ""))
			if link != "":
				_add(link, 26, DIM, 0.0, width - 30.0, 30.0)
	_add(str(data.get("footer", "")), 34, AMBER, 48.0, width)
	_content_h = 0.0
	for row in _rows:
		_content_h += float(row["gap"]) + float(row["size"]) * 1.05


## Adds one or more wrapped lines.
func _add(text: String, font_size: int, color: Color, gap: float, width: float, indent: float = 0.0) -> void:
	if text == "":
		return
	var first := true
	for line in _wrap(text, width, font_size):
		_rows.append({"text": line, "size": font_size, "color": color, "gap": gap if first else 0.0, "indent": indent})
		first = false


func _wrap(text: String, width: float, font_size: int) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if _body_font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
			lines.append(line)
			line = word
		else:
			line = trial
	if line != "":
		lines.append(line)
	return lines


# ---------------------------------------------------------------- drawing

func _draw_panel() -> void:
	var a := _show
	_view.draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color(0, 0, 0, 0.72 * a))
	var panel := PANEL
	_view.draw_rect(panel, Color(DARK, 0.97 * a))
	_view.draw_rect(panel, Color(GREEN, 0.8 * a), false, 3.0)

	# Header bar, like a terminal window.
	var header := Rect2(panel.position, Vector2(panel.size.x, HEADER_H))
	_view.draw_rect(header, Color(GREEN, a))
	var title := Loc.t("CREDITS")
	var data_title := title
	_view.draw_string(_title_font, Vector2(panel.position.x + PAD, panel.position.y + 66), data_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(DARK, a))
	var tag := "C:\\EOC\\CREDITS.EXE"
	var tag_w := _body_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_view.draw_string(_body_font, Vector2(panel.end.x - PAD - tag_w, panel.position.y + 60), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(DARK, 0.8 * a))

	# Scrolling list, clipped to the body area by skipping rows outside it.
	var top := panel.position.y + HEADER_H + 24.0
	var bottom := panel.end.y - FOOTER_H - 6.0
	var y := top - _scroll
	for row in _rows:
		y += float(row["gap"])
		var font_size := int(row["size"])
		var baseline := y + font_size * 0.8
		if baseline > top + font_size * 0.6 and baseline < bottom:
			var color: Color = row["color"]
			_view.draw_string(_body_font, Vector2(panel.position.x + PAD + float(row["indent"]), baseline), str(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, color.a * a))
		y += font_size * 1.05

	# Fade bands at the top and bottom of the list.
	for k in 6:
		var t := float(k) / 6.0
		_view.draw_rect(Rect2(panel.position.x + 3, top - 24.0 + k * 6.0, panel.size.x - 6, 6), Color(DARK, (1.0 - t) * a))
		_view.draw_rect(Rect2(panel.position.x + 3, bottom - k * 6.0, panel.size.x - 6, 6), Color(DARK, (1.0 - t) * a))

	# Scroll bar.
	var max_scroll := _max_scroll()
	if max_scroll > 0.0:
		var track := Rect2(panel.end.x - 22, top, 6, bottom - top)
		_view.draw_rect(track, Color(GREEN, 0.15 * a))
		var visible_frac := (bottom - top) / (bottom - top + max_scroll)
		var thumb_h := maxf(40.0, track.size.y * visible_frac)
		var thumb_y := track.position.y + (track.size.y - thumb_h) * (_scroll / max_scroll)
		_view.draw_rect(Rect2(track.position.x, thumb_y, 6, thumb_h), Color(GREEN, 0.8 * a))

	# Footer: hint and BACK button.
	_view.draw_line(Vector2(panel.position.x + PAD, panel.end.y - FOOTER_H), Vector2(panel.end.x - PAD, panel.end.y - FOOTER_H), Color(GREEN, 0.3 * a), 2.0)
	var hint := Loc.t("SCROLL: MOUSE WHEEL OR ARROW KEYS")
	_view.draw_string(_body_font, Vector2(panel.position.x + PAD, panel.end.y - FOOTER_H + 52), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(DIM, DIM.a * a))
	var back := _back_rect()
	_view.draw_rect(back, Color(GREEN, (0.9 if _back_hover else 0.12) * a))
	_view.draw_rect(back, Color(GREEN, a), false, 2.0)
	_view.draw_string(_body_font, Vector2(back.position.x, back.position.y + 38), Loc.t("BACK  [ESC]"), HORIZONTAL_ALIGNMENT_CENTER, back.size.x, 32, Color(DARK if _back_hover else BRIGHT, a))
