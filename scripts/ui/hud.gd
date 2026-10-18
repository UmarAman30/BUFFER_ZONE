extends Control
## Always-visible top bar: the Public Trust bar (centre-left, title centred above it), the survival
## timer and threat level (right end). During the missile event the fear index slides in above the
## trust bar, replacing its title.

const C := preload("res://scripts/ui/ui_colors.gd")
const TOP := 14.0                            # gap between the monitor edge and the top bar
const BAR_RECT := Rect2(494, 38 + TOP, 820, 40)    # trust bar, screen pixels
const PIXEL := 4.0                           # size of one "pixel" step on the rounded corners
const RIGHT_X := 1340.0                      # timer / threat block: from here to RIGHT_END
const RIGHT_END := 1880.0

var _trust_view: Control
var _trust_shown: float = GameState.MAX_TRUST   # eases toward the real value
var _trust_ghost: float = GameState.MAX_TRUST   # pale trail left behind when trust drops
var _ghost_hold: float = 0.0
var _score_label: Label
var _threat_label: Label
var _trust_title: Label
var _fear_bar: Control
var _fear_value: float = 0.0     # shown value (eases toward GameState.fear)
var _fear_show: float = 0.0      # 0 hidden .. 1 fully slid in
var _fear_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the fear bar animates while the missile event pauses the game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := Panel.new()
	bar.position = Vector2(470, TOP)
	bar.size = Vector2(1430, 86)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", C.box(Color(C.PANEL, 0.9), Color(0, 0, 0, 0), 0))
	add_child(bar)
	C.add_frame(bar)

	_trust_title = Label.new()
	_trust_title.text = Loc.t("PUBLIC TRUST")
	_trust_title.position = Vector2(BAR_RECT.position.x, 2 + TOP)
	_trust_title.size = Vector2(BAR_RECT.size.x, 34)
	_trust_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trust_title.add_theme_font_size_override("font_size", 22)
	_trust_title.add_theme_color_override("font_color", C.TEXT)
	add_child(_trust_title)

	_trust_view = Control.new()
	_trust_view.position = BAR_RECT.position
	_trust_view.size = BAR_RECT.size
	_trust_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trust_view.draw.connect(_draw_trust)
	add_child(_trust_view)

	_score_label = Label.new()
	_score_label.position = Vector2(RIGHT_X, -2 + TOP)
	_score_label.size = Vector2(RIGHT_END - RIGHT_X, 50)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_size_override("font_size", 38)
	_score_label.add_theme_color_override("font_color", C.TEXT)
	add_child(_score_label)
	_on_score_changed(0)

	_threat_label = Label.new()
	_threat_label.position = Vector2(RIGHT_X, 46 + TOP)
	_threat_label.size = Vector2(RIGHT_END - RIGHT_X, 34)
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_threat_label.add_theme_font_size_override("font_size", 24)
	add_child(_threat_label)
	_on_difficulty_changed(0)

	# Fear index: slides in on top of the trust bar during the missile event (replacing its title).
	_fear_bar = Control.new()
	_fear_bar.position = Vector2(BAR_RECT.position.x, 5 + TOP)
	_fear_bar.size = Vector2(BAR_RECT.size.x, 28)
	_fear_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fear_bar.draw.connect(_draw_fear)
	_fear_bar.visible = false
	add_child(_fear_bar)
	EventBus.fear_changed.connect(func(_value: float, active: bool) -> void: _fear_active = active)

	EventBus.trust_changed.connect(_on_trust_changed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.difficulty_changed.connect(_on_difficulty_changed)
	Loc.language_changed.connect(_on_language_changed)
	EventBus.game_started.connect(func() -> void:
		_on_difficulty_changed(0)
		_trust_shown = GameState.MAX_TRUST
		_trust_ghost = GameState.MAX_TRUST)


func _process(delta: float) -> void:
	_fear_show = move_toward(_fear_show, 1.0 if _fear_active else 0.0, delta * 3.0)
	_fear_value = lerpf(_fear_value, GameState.fear, clampf(delta * 6.0, 0.0, 1.0))
	_fear_bar.visible = _fear_show > 0.0
	_trust_title.modulate.a = 1.0 - _fear_show
	if _fear_bar.visible:
		_fear_bar.queue_redraw()
	# Trust bar: the fill eases to the new value; a pale ghost of lost trust lingers, then drains.
	_trust_shown = lerpf(_trust_shown, GameState.trust, clampf(delta * 8.0, 0.0, 1.0))
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
	else:
		_trust_ghost = move_toward(_trust_ghost, _trust_shown, delta * 40.0)
	_trust_ghost = maxf(_trust_ghost, _trust_shown)
	_trust_view.queue_redraw()


## A rectangle with stepped ("pixel rounded") corners, two steps of `p` per corner.
static func pixel_rect(r: Rect2, p: float) -> PackedVector2Array:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	return PackedVector2Array([
		Vector2(x + 2 * p, y), Vector2(x + w - 2 * p, y), Vector2(x + w - 2 * p, y + p), Vector2(x + w - p, y + p),
		Vector2(x + w - p, y + 2 * p), Vector2(x + w, y + 2 * p), Vector2(x + w, y + h - 2 * p), Vector2(x + w - p, y + h - 2 * p),
		Vector2(x + w - p, y + h - p), Vector2(x + w - 2 * p, y + h - p), Vector2(x + w - 2 * p, y + h), Vector2(x + 2 * p, y + h),
		Vector2(x + 2 * p, y + h - p), Vector2(x + p, y + h - p), Vector2(x + p, y + h - 2 * p), Vector2(x, y + h - 2 * p),
		Vector2(x, y + 2 * p), Vector2(x + p, y + 2 * p), Vector2(x + p, y + p), Vector2(x + 2 * p, y + p),
	])


func _trust_color(value: float) -> Color:
	if value <= 25.0:
		return C.RED
	if value <= 50.0:
		return C.YELLOW.lerp(C.RED, clampf((50.0 - value) / 25.0, 0.0, 1.0) * 0.3)
	return C.GREEN


func _draw_trust() -> void:
	var view := _trust_view
	var now := Time.get_ticks_msec() / 1000.0
	var full := Rect2(Vector2.ZERO, view.size)
	var inner := full.grow(-PIXEL)
	var ratio := clampf(_trust_shown / GameState.MAX_TRUST, 0.0, 1.0)
	var color := _trust_color(_trust_shown)
	# Frame and well.
	view.draw_colored_polygon(pixel_rect(full, PIXEL), C.DIM.lightened(0.25))
	view.draw_colored_polygon(pixel_rect(inner, PIXEL * 0.75), Color(0.02, 0.06, 0.04))
	# Ghost of trust just lost.
	var ghost_w := inner.size.x * clampf(_trust_ghost / GameState.MAX_TRUST, 0.0, 1.0)
	if ghost_w > inner.size.x * ratio + 1.0:
		view.draw_colored_polygon(pixel_rect(Rect2(inner.position, Vector2(ghost_w, inner.size.y)), PIXEL * 0.75), Color(1.0, 0.95, 0.85, 0.55))
	# Fill: base colour, a bright band on top, a darker band at the bottom (chunky pixel shading).
	var fill_w := inner.size.x * ratio
	if fill_w >= PIXEL * 4.0:
		var fill := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		var pulse := 1.0
		if _trust_shown <= 25.0:
			pulse = 0.75 + 0.25 * sin(now * 8.0)
		view.draw_colored_polygon(pixel_rect(fill, PIXEL * 0.75), Color(color.darkened(0.15), pulse))
		view.draw_rect(Rect2(fill.position + Vector2(PIXEL * 1.5, PIXEL), Vector2(fill.size.x - PIXEL * 3.0, PIXEL * 2.0)), Color(color.lightened(0.45), pulse))
		view.draw_rect(Rect2(fill.position + Vector2(PIXEL * 1.5, fill.size.y - PIXEL * 2.0), Vector2(fill.size.x - PIXEL * 3.0, PIXEL)), Color(color.darkened(0.45), pulse))
		# A slow glint sliding along the fill.
		var glint_x := fmod(now * 160.0, fill.size.x + 200.0) - 100.0
		if glint_x > PIXEL * 2.0 and glint_x < fill.size.x - PIXEL * 4.0:
			view.draw_rect(Rect2(fill.position + Vector2(glint_x, PIXEL), Vector2(PIXEL * 2.0, fill.size.y - PIXEL * 2.0)), Color(1, 1, 1, 0.18))
	# Pixel ticks every 10%.
	for i in range(1, 10):
		var x := inner.position.x + inner.size.x * i / 10.0
		view.draw_rect(Rect2(x - 1.0, inner.end.y - PIXEL * 1.5, 2.0, PIXEL * 1.5), Color(0, 0, 0, 0.45))
	# The number: bold, outlined and centred.
	var font := view.get_theme_default_font()
	var text := "%d%%" % roundi(GameState.trust)
	var font_size := 34
	var baseline := Vector2(0, view.size.y * 0.5 + 11.0)
	view.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, view.size.x, font_size, 9, Color(0.01, 0.05, 0.02))
	view.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, view.size.x, font_size, C.WHITE)
	view.draw_string(font, baseline + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_CENTER, view.size.x, font_size, C.WHITE)


func _draw_fear() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var width := _fear_bar.size.x * _fear_show
	var height := _fear_bar.size.y
	var ratio := _fear_value / 100.0
	# Heartbeat: faster and stronger as fear climbs.
	var beat := pow(absf(sin(now * lerpf(2.0, 6.0, ratio))), 6.0)
	var fill := Color(0.75, 0.05, 0.25).lerp(Color(1.0, 0.1, 0.1), ratio)
	if width >= PIXEL * 4.0:
		_fear_bar.draw_colored_polygon(pixel_rect(Rect2(0, 0, width, height), PIXEL * 0.75), Color(1.0, 0.25, 0.3, 0.6 + 0.4 * beat))
		_fear_bar.draw_colored_polygon(pixel_rect(Rect2(2, 2, width - 4, height - 4), PIXEL * 0.5), Color(0.12, 0.0, 0.03, 0.97))
		var fill_w := (width - 4.0) * ratio
		if fill_w >= PIXEL * 2.0:
			_fear_bar.draw_colored_polygon(pixel_rect(Rect2(2, 2, fill_w, height - 4), PIXEL * 0.5), Color(fill, 0.75 + 0.25 * beat))
	if _fear_show >= 1.0:
		var font := get_theme_default_font()
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * maxf(0.0, ratio - 0.6) * 5.0
		_fear_bar.draw_string_outline(font, Vector2(12, 22) + shake, Loc.t("FEAR INDEX"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0.1, 0.0, 0.02))
		_fear_bar.draw_string(font, Vector2(12, 22) + shake, Loc.t("FEAR INDEX"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C.WHITE)
		_fear_bar.draw_string_outline(font, Vector2(0, 22) + shake, "%d%%  " % roundi(_fear_value), HORIZONTAL_ALIGNMENT_RIGHT, _fear_bar.size.x - 6.0, 26, 6, Color(0.1, 0.0, 0.02))
		_fear_bar.draw_string(font, Vector2(0, 22) + shake, "%d%%  " % roundi(_fear_value), HORIZONTAL_ALIGNMENT_RIGHT, _fear_bar.size.x - 6.0, 26, C.WHITE)


func _on_trust_changed(value: float) -> void:
	if value < _trust_shown - 0.5:
		_ghost_hold = 0.45   # let the lost chunk register before it drains away
	elif value > _trust_ghost:
		_trust_ghost = value


func _on_difficulty_changed(level: int) -> void:
	_threat_label.text = Loc.t("THREAT LEVEL  %d") % (level + 1)
	var color := C.TEXT
	if level >= 3:
		color = C.RED
	elif level >= 2:
		color = C.YELLOW
	_threat_label.add_theme_color_override("font_color", color)


## Language switched mid-shift from the pause menu: refresh the labels that are only set on change.
func _on_language_changed(_lang: String) -> void:
	_trust_title.text = Loc.t("PUBLIC TRUST")
	_on_difficulty_changed(World.difficulty_level)
	_on_score_changed(int(GameState.survival_time))


func _on_score_changed(seconds: int) -> void:
	_score_label.text = Loc.t("SURVIVED  %s") % format_time(seconds)


static func format_time(total_seconds: int) -> String:
	return "%02d:%02d" % [floori(total_seconds / 60.0), total_seconds % 60]
