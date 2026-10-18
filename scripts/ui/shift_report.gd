extends Control
## End-of-shift report card: how the player used the live feed. Opened from the report line on the
## game-over card. Shows rumors ignored, reports read before dispatch and informed dispatches, with
## an awareness verdict. Everything is drawn with measured text so long Turkish labels still fit.

const C := preload("res://scripts/ui/ui_colors.gd")

const CARD := Vector2(900, 800)
const PAD := 44.0
const VALUE_W := 200.0
const ROW_Y := [182.0, 322.0, 462.0]

var _card: Panel
var _art: Control
var _close: Button
var _pop := 1.0
var _rows: Array[Dictionary] = []
var _verdict := ""
var _verdict_color := C.TEXT
var _takeaway := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)

	_card = Panel.new()
	_card.size = CARD
	_card.position = (Vector2(1920, 1080) - CARD) * 0.5
	_card.pivot_offset = CARD * 0.5
	_card.add_theme_stylebox_override("panel", C.dialog_style(C.TEXT, 0.0))
	add_child(_card)
	C.add_frame(_card, C.TEXT)

	_art = Control.new()
	_art.size = CARD
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_card)
	_card.add_child(_art)

	_close = Button.new()
	_close.size = Vector2(300, 64)
	_close.position = Vector2((CARD.x - 300.0) * 0.5, CARD.y - 64.0 - 28.0)
	_close.focus_mode = Control.FOCUS_NONE
	_close.add_theme_font_size_override("font_size", 20)
	var normal := C.box(Color(C.PANEL, 1.0), C.TEXT, 2)
	var hover := C.box(C.PANEL.lightened(0.15), C.WHITE, 2)
	_close.add_theme_stylebox_override("normal", normal)
	_close.add_theme_stylebox_override("hover", hover)
	_close.add_theme_stylebox_override("pressed", hover)
	_close.add_theme_stylebox_override("focus", normal)
	_close.pressed.connect(close)
	_card.add_child(_close)


func open() -> void:
	_build_rows()
	_close.text = Loc.t("CLOSE  [ESC]")
	_pop = 0.0
	visible = true
	EventBus.sfx_requested.emit("feed_open")
	_art.queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	EventBus.sfx_requested.emit("feed_close")


func _process(delta: float) -> void:
	if not visible or _pop >= 1.0:
		return
	_pop = minf(1.0, _pop + delta * 6.0)
	var eased := 1.0 - pow(1.0 - _pop, 3.0)
	_card.scale = Vector2.ONE * lerpf(0.94, 1.0, eased)
	_card.modulate.a = eased


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- stats

func _build_rows() -> void:
	var s: Dictionary = Feed.stats
	var seen := int(s.get("rumors_seen", 0))
	var followed := int(s.get("rumors_followed", 0))
	var ignored := maxi(0, seen - followed)
	var dispatches := int(s.get("dispatches", 0))
	var read := int(s.get("reports_read", 0))
	var informed := int(s.get("informed", 0))
	_rows = []
	_rows.append({
		"label": Loc.t("RUMORS IGNORED"),
		"value": "%d/%d" % [ignored, seen] if seen > 0 else "-",
		"hint": Loc.t("Unverified posts you did not act on") if seen > 0 else Loc.t("No rumors reached your screen"),
		"ratio": float(ignored) / float(seen) if seen > 0 else -1.0,
	})
	_rows.append({
		"label": Loc.t("REPORTS READ BEFORE DISPATCH"),
		"value": str(read),
		"hint": (Loc.t("Average %s per dispatch") % ("%.1f" % (float(read) / float(dispatches)))) if dispatches > 0 else Loc.t("No teams were dispatched"),
		"ratio": -1.0,
	})
	_rows.append({
		"label": Loc.t("INFORMED DISPATCHES"),
		"value": "%d/%d" % [informed, dispatches] if dispatches > 0 else "-",
		"hint": Loc.t("Teams sent after reading at least one report"),
		"ratio": float(informed) / float(dispatches) if dispatches > 0 else -1.0,
	})

	# Verdict: the average of the two ratios that exist.
	var parts: Array[float] = []
	if seen > 0:
		parts.append(float(ignored) / float(seen))
	if dispatches > 0:
		parts.append(float(informed) / float(dispatches))
	if parts.is_empty():
		_verdict = Loc.t("NOT ENOUGH DATA")
		_verdict_color = C.TEXT
		_takeaway = Loc.t("Dispatch a team after reading the feed to get a rating.")
		return
	var score := 0.0
	for p in parts:
		score += p
	score /= parts.size()
	if score >= 0.8:
		_verdict = Loc.t("SHARP")
		_verdict_color = C.GREEN
		_takeaway = Loc.t("You checked the facts before acting. That is what preparedness looks like.")
	elif score >= 0.5:
		_verdict = Loc.t("STEADY")
		_verdict_color = C.YELLOW
		_takeaway = Loc.t("Good instincts. Read one more report before you commit a team.")
	else:
		_verdict = Loc.t("RECKLESS")
		_verdict_color = C.RED
		_takeaway = Loc.t("Rumors moved faster than facts. Check official sources first.")


# ---------------------------------------------------------------- drawing

func _draw_card() -> void:
	var font := _art.get_theme_default_font()
	var inner := CARD.x - PAD * 2.0

	# Header band, like the sector cards.
	_art.draw_rect(Rect2(0, 0, CARD.x, 92), C.TEXT)
	var chip_text := Loc.t("AWARENESS")
	var chip_size := 28
	var chip_w := font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_size).x + 28.0
	var chip := Rect2(CARD.x - PAD - chip_w, 22, chip_w, 48)
	_art.draw_rect(chip, C.BG)
	_art.draw_string(font, Vector2(chip.position.x, chip.position.y + 35), chip_text, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, chip_size, C.TEXT)
	var title := Loc.t("SHIFT REPORT")
	_art.draw_string(font, Vector2(PAD, 64), title, HORIZONTAL_ALIGNMENT_LEFT, -1, _fit(font, title, inner - chip_w - 20.0, 48), C.BG)

	var sub := Loc.t("Operator %s: how you used the live feed this shift") % Loc.upper(PlayerData.player_name)
	_art.draw_string(font, Vector2(PAD, 138), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, _fit(font, sub, inner, 28), C.DIM.lightened(0.7))
	_art.draw_line(Vector2(PAD, 156), Vector2(CARD.x - PAD, 156), Color(C.TEXT, 0.25), 2.0)

	for i in _rows.size():
		_draw_row(font, _rows[i], ROW_Y[i], inner)

	# Verdict and takeaway.
	var vy := 612.0
	var head := Loc.t("AWARENESS RATING")
	var head_size := _fit(font, head, inner * 0.6, 28)
	_art.draw_string(font, Vector2(PAD, vy), head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size, C.DIM.lightened(0.6))
	var head_w := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size).x
	_art.draw_string(font, Vector2(PAD + head_w + 18.0, vy + 3), _verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, _fit(font, _verdict, inner - head_w - 18.0, 42), _verdict_color)
	var lines := _wrap(font, _takeaway, inner, 26)
	for k in mini(lines.size(), 2):
		_art.draw_string(font, Vector2(PAD, vy + 40 + k * 32), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C.WHITE)


func _draw_row(font: Font, row: Dictionary, y: float, inner: float) -> void:
	var label_w := inner - VALUE_W - 16.0
	var label: String = row["label"]
	# Accent tick, label, value on the right, hint underneath, then the ratio bar.
	_art.draw_rect(Rect2(PAD, y - 6, 6, 82), Color(C.TEXT, 0.8))
	_art.draw_string(font, Vector2(PAD + 20, y + 30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, _fit(font, label, label_w - 20.0, 34), C.TEXT)
	var hint: String = row["hint"]
	_art.draw_string(font, Vector2(PAD + 20, y + 66), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, _fit(font, hint, label_w - 20.0, 26), C.DIM.lightened(0.8))
	var value: String = row["value"]
	var ratio: float = row["ratio"]
	var value_color := C.WHITE
	if ratio >= 0.0:
		value_color = C.GREEN if ratio >= 0.8 else (C.YELLOW if ratio >= 0.5 else C.RED)
	_art.draw_string(font, Vector2(CARD.x - PAD - VALUE_W, y + 56), value, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_W, _fit(font, value, VALUE_W, 64), value_color)
	if ratio >= 0.0:
		# Segmented pixel bar, matching the trust bar.
		var segments := 20
		var bar_x := PAD + 20.0
		var bar_w := inner - 20.0
		var seg_w := bar_w / segments
		var lit := roundi(ratio * segments)
		for k in segments:
			var rect := Rect2(bar_x + k * seg_w + 1.0, y + 84, seg_w - 3.0, 12)
			_art.draw_rect(rect, value_color if k < lit else Color(C.DIM, 0.8))


## Largest size (down to 14) at which the text fits the width.
func _fit(font: Font, text: String, width: float, max_size: int) -> int:
	var s := max_size
	while s > 14 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


func _wrap(font: Font, text: String, width: float, font_size: int) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and line != "":
			lines.append(line)
			line = word
		else:
			line = trial
	if line != "":
		lines.append(line)
	return lines
