extends Control
## Mystery event at minute four (balance.json "missile"). EventBus.missile_event_started runs the scene:
##   STRIKE    a missile streaks in and hits a district (no trust loss; casualties there)
##   ANNOUNCE  red wash, klaxon, "MISSILE DEPOT MALFUNCTION" banner; the fear index appears
##   CONSOLE   manual override: three codes (ARM / TARGET / FIRE) typed through a cipher key
##   WON/LOST  an interceptor downs the second missile, or it hits another district
## The rest of the game is paused for the whole scene; this node keeps running.

const C := preload("res://scripts/ui/ui_colors.gd")
const TINT_SHADER := preload("res://assets/shaders/red_alert.gdshader")
const CONSOLE_SIZE := Vector2(1560, 860)
const CONSOLE_POS := Vector2(180, 150)
const CONSOLE_HIDDEN := Vector2(180, 1120)
const SKY_RIGHT := Vector2(2060, -140)
const SKY_LEFT := Vector2(-140, -140)
const TRACK_FROM := 150.0
const TRACK_TO := 1040.0
const TRACK_Y := 172.0
const AMBER := Color(1.0, 0.62, 0.15)
const DEEP := Color(0.05, 0.015, 0.015, 0.97)
const LINE := Color(0.75, 0.18, 0.18)
const SYMBOL_COLOR := Color(1.0, 0.92, 0.7)

enum Stage { IDLE, STRIKE, ANNOUNCE, CONSOLE, WON, LOST, OUTRO }

var map: Control   # map_screen: district positions and closing its panels

var _stage: Stage = Stage.IDLE
var _t: float = 0.0       # seconds in the current stage
var _clock: float = 0.0   # seconds since the event began
var _first: String = ""
var _second: String = ""
var _settings: Dictionary = {}
var _fear_cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# Effects
var _tint: ColorRect
var _tint_material: ShaderMaterial
var _tint_amount: float = 0.0
var _tint_target: float = 0.0
var _flash: ColorRect
var _blocker: Control
var _dim: ColorRect
var _fx: Control
var _missiles: Array[Dictionary] = []   # {from, to, t0, dur, hit (Callable), done}
var _blasts: Array[Dictionary] = []     # {at, t0, size, sparks}
var _shake_time: float = 0.0
var _shake_total: float = 0.0
var _shake_strength: float = 0.0
var _klaxon_on: bool = false

# Banner
var _banner: Control
var _banner_title: Label
var _banner_line: Label
var _banner_sub: Label
var _typed: String = ""
var _type_shown: int = 0

# Console
var _console: Control
var _keypad: Array[Button] = []
var _time_left: float = 0.0
var _time_total: float = 0.0
var _code_index: int = 0
var _code: Array[int] = []        # symbol ids to decode
var _key: Array[int] = []         # symbol id -> digit
var _key_order: Array[int] = []   # order the symbols are listed in the cipher key
var _entry: Array[int] = []       # digits typed for the current code
var _lock: float = 0.0
var _error_flash: float = 0.0
var _accept_flash: float = 0.0
var _between: float = 0.0         # short beat after a code is accepted
var _glitch: Dictionary = {}      # symbol id -> {digit, until}
var _glitch_timer: float = 0.0
var _last_tick: int = -1
var _status: String = ""
var _status_color: Color = C.TEXT
var _intercept_hit: bool = false
var _second_launched: bool = false
var _flight: float = 3.0           # seconds the first missile takes to land


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_rng.randomize()

	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint_material = ShaderMaterial.new()
	_tint_material.shader = TINT_SHADER
	_tint.material = _tint_material
	_tint.visible = false
	add_child(_tint)

	_blocker = Control.new()   # nothing on the map can be clicked during the event
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)

	_dim = ColorRect.new()   # below the HUD only, so trust and fear stay readable
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.position = Vector2(0, 104)
	_dim.size = Vector2(1920, 976)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	add_child(_dim)

	_build_console()
	_build_banner()

	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.97, 0.9, 0.0)
	add_child(_flash)

	EventBus.missile_event_started.connect(_begin)
	EventBus.game_started.connect(_reset)
	EventBus.game_over.connect(func(_score: int) -> void: _set_klaxon(false))


# ---------------------------------------------------------------- flow

func _begin(first: String, second: String) -> void:
	_settings = GameData.balance["missile"]
	_fear_cfg = _settings["fear"]
	_first = first
	_second = second
	_reset()
	visible = true
	_blocker.visible = true
	get_tree().paused = true
	if map != null:
		map.set_feed_open(false)
		map.close_profile()
		map.clear_selection()
	_enter(Stage.STRIKE)
	_flight = float(_settings.get("first_flight", 3.0))
	_launch(SKY_RIGHT, _point(first), _flight, _first_impact)
	EventBus.sfx_requested.emit("missile_whistle")


func _reset() -> void:
	_stage = Stage.IDLE
	_clock = 0.0
	_missiles.clear()
	_blasts.clear()
	_tint_amount = 0.0
	_tint_target = 0.0
	_tint.visible = false
	_flash.color.a = 0.0
	_dim.modulate.a = 0.0
	_banner.visible = false
	_console.visible = false
	_console.position = CONSOLE_HIDDEN
	_blocker.visible = false
	_shake_time = 0.0
	_second_launched = false
	_set_klaxon(false)
	visible = false


func _enter(stage: Stage) -> void:
	_stage = stage
	_t = 0.0


func _first_impact() -> void:
	_explode(_point(_first), 1.0)
	World.missile_first_impact(_first)
	GameState.set_fear(float(_fear_cfg["first_hit"]))
	_tint_target = 1.0


func _second_impact() -> void:
	_explode(_point(_second), 1.45)
	GameState.add_fear(float(_fear_cfg["hit"]))


func _process(delta: float) -> void:
	if _stage == Stage.IDLE:
		return
	_clock += delta
	_t += delta
	_tick_effects(delta)
	match _stage:
		Stage.STRIKE:
			if _t >= _flight + 0.5 and not _klaxon_on:
				_set_klaxon(true)
			if _t >= _flight + 1.2:
				_show_banner()
		Stage.ANNOUNCE:
			_tick_banner()
			if _t >= 4.0:
				_hide_banner()
				_open_console()
		Stage.CONSOLE:
			_tick_console(delta)
		Stage.WON:
			_tick_won()
		Stage.LOST:
			_tick_lost()
		Stage.OUTRO:
			if _tint_amount <= 0.0 and _blasts.is_empty() and _shake_time <= 0.0:
				_stage = Stage.IDLE
				visible = false
	_fx.queue_redraw()
	if _console.visible:
		_console.queue_redraw()
	if _banner.visible:
		_banner.queue_redraw()


func _tick_effects(delta: float) -> void:
	_tint_amount = move_toward(_tint_amount, _tint_target, delta * 1.4)
	_tint.visible = _tint_amount > 0.001
	_tint_material.set_shader_parameter("amount", _tint_amount)
	_tint_material.set_shader_parameter("time_s", _clock)
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.5)
	for missile in _missiles:
		if not missile["done"] and _clock >= float(missile["t0"]) + float(missile["dur"]):
			missile["done"] = true
			(missile["hit"] as Callable).call()
	_missiles = _missiles.filter(func(m: Dictionary) -> bool: return not m["done"])
	_blasts = _blasts.filter(func(b: Dictionary) -> bool: return _clock - float(b["t0"]) < 2.6)
	var parent := get_parent() as Control
	if _shake_time > 0.0:
		_shake_time -= delta
		var falloff := clampf(_shake_time / _shake_total, 0.0, 1.0)
		parent.position = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake_strength * falloff
	elif parent.position != Vector2.ZERO:
		parent.position = Vector2.ZERO


func _outro(intercepted: bool) -> void:
	_enter(Stage.OUTRO)
	_tint_target = 0.0
	_set_klaxon(false)
	_console.visible = false
	_banner.visible = false
	_blocker.visible = false
	create_tween().tween_property(_dim, "modulate:a", 0.0, 0.4)
	get_tree().paused = false
	GameState.release_fear(float(_fear_cfg["decay_saved"] if intercepted else _fear_cfg["decay_hit"]))
	World.missile_result(_second, intercepted)


# ---------------------------------------------------------------- effects

func _point(sector_id: String) -> Vector2:
	if map != null and map.has_method("district_point"):
		return map.district_point(sector_id)
	return Vector2(960, 560)


func _launch(from: Vector2, to: Vector2, duration: float, on_hit: Callable) -> void:
	_missiles.append({"from": from, "to": to, "t0": _clock, "dur": duration, "hit": on_hit, "done": false})


func _explode(at: Vector2, power: float) -> void:
	EventBus.sfx_requested.emit("missile_impact")
	_flash.color.a = 0.95
	_shake(24.0 * power, 0.9 * power)
	var sparks: Array = []
	for i in 34:
		sparks.append({"dir": Vector2.RIGHT.rotated(_rng.randf() * TAU), "speed": _rng.randf_range(160.0, 520.0) * power, "life": _rng.randf_range(0.6, 1.6)})
	_blasts.append({"at": at, "t0": _clock, "size": power, "sparks": sparks})


func _shake(strength: float, duration: float) -> void:
	if strength < _shake_strength * clampf(_shake_time / maxf(_shake_total, 0.01), 0.0, 1.0):
		return   # a bigger shake is still running
	_shake_strength = strength
	_shake_total = duration
	_shake_time = duration


func _set_klaxon(on: bool) -> void:
	_klaxon_on = on
	if AudioManager.has_method("set_klaxon"):
		AudioManager.set_klaxon(on)


func _draw_fx() -> void:
	for missile in _missiles:
		var progress := clampf((_clock - float(missile["t0"])) / float(missile["dur"]), 0.0, 1.0)
		var from: Vector2 = missile["from"]
		var to: Vector2 = missile["to"]
		# Target reticle on the district.
		var blink := 0.5 + 0.5 * sin(_clock * 18.0)
		var ring := 70.0 - 30.0 * progress
		_fx.draw_arc(to, ring, 0.0, TAU, 48, Color(C.RED, 0.5 + 0.5 * blink), 3.0)
		for k in 4:
			var dir := Vector2.RIGHT.rotated(k * PI * 0.5)
			_fx.draw_line(to + dir * (ring + 8.0), to + dir * (ring + 30.0), C.RED, 3.0)
		if progress <= 0.0:
			continue
		# Smoke trail, then the burning head.
		var head := from.lerp(to, progress * progress)
		var previous := head
		for i in range(1, 18):
			var back := maxf(0.0, progress - i * 0.03)
			var at := from.lerp(to, back * back)
			var fade := 1.0 - i / 18.0
			_fx.draw_line(previous, at, Color(0.55, 0.5, 0.5, 0.35 * fade), 18.0 * fade + 4.0)
			_fx.draw_line(previous, at, Color(1.0, 0.55, 0.15, 0.85 * fade), 8.0 * fade + 1.0)
			previous = at
		_fx.draw_circle(head, 22.0, Color(1.0, 0.35, 0.05, 0.35))
		_fx.draw_circle(head, 9.0, Color(1.0, 0.95, 0.75))
		# Countdown tag on the target while it falls.
		var left := maxf(0.0, float(missile["dur"]) * (1.0 - progress))
		if fmod(_clock, 0.4) < 0.28:
			var font := _fx.get_theme_default_font()
			_fx.draw_string_outline(font, to + Vector2(-160, -ring - 46), Loc.t("INCOMING  %.1f") % left, HORIZONTAL_ALIGNMENT_CENTER, 320, 34, 8, Color(0, 0, 0))
			_fx.draw_string(font, to + Vector2(-160, -ring - 46), Loc.t("INCOMING  %.1f") % left, HORIZONTAL_ALIGNMENT_CENTER, 320, 34, C.RED)
	for blast in _blasts:
		var age := _clock - float(blast["t0"])
		var power := float(blast["size"])
		var at: Vector2 = blast["at"]
		var grow := 1.0 - pow(1.0 - clampf(age * 3.0, 0.0, 1.0), 3.0)
		_fx.draw_circle(at, 190.0 * power * clampf(age * 5.0, 0.0, 1.0), Color(1.0, 0.3, 0.05, 0.3 * maxf(0.0, 1.0 - age / 2.2)))
		for j in 3:   # shock rings
			var ring_age := age - j * 0.12
			if ring_age > 0.0:
				_fx.draw_arc(at, ring_age * 560.0 * power, 0.0, TAU, 72, Color(1.0, 0.85, 0.6, maxf(0.0, 0.7 - ring_age * 0.9)), 7.0 * power)
		if age > 0.25:   # smoke
			var smoke := clampf((age - 0.25) / 2.0, 0.0, 1.0)
			for k in 6:
				var drift := Vector2.RIGHT.rotated(k * TAU / 6.0) * 60.0 * power * smoke + Vector2(0, -90.0 * smoke * power)
				_fx.draw_circle(at + drift, (40.0 + 30.0 * smoke) * power, Color(0.12, 0.08, 0.08, 0.45 * (1.0 - smoke)))
		_fx.draw_circle(at, 100.0 * power * grow, Color(1.0, 0.65, 0.2, maxf(0.0, 0.95 - age * 0.75)))
		_fx.draw_circle(at, 55.0 * power * grow, Color(1.0, 1.0, 0.85, maxf(0.0, 1.0 - age * 1.5)))
		for spark: Dictionary in blast["sparks"]:
			var life := float(spark["life"])
			if age > life:
				continue
			var pos := at + (spark["dir"] as Vector2) * float(spark["speed"]) * age + Vector2(0, 260.0 * age * age)
			var tail := pos - (spark["dir"] as Vector2) * 16.0
			_fx.draw_line(tail, pos, Color(1.0, 0.75, 0.3, 1.0 - age / life), 3.0)


# ---------------------------------------------------------------- banner

func _build_banner() -> void:
	_banner = Control.new()
	_banner.position = Vector2(0, 360)
	_banner.size = Vector2(1920, 300)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.draw.connect(_draw_banner)
	_banner.visible = false
	add_child(_banner)
	_banner_title = _banner_label(Vector2(0, 66), 66, Color(1.0, 0.3, 0.28))
	_banner_title.text = Loc.t("MISSILE DEPOT MALFUNCTION")
	_banner_line = _banner_label(Vector2(0, 168), 32, C.WHITE)
	_banner_sub = _banner_label(Vector2(0, 214), 28, C.YELLOW)
	_banner_sub.text = Loc.t("MANUAL OVERRIDE REQUIRED")


func _banner_label(at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(1920, font_size * 1.6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(label)
	return label


func _show_banner() -> void:
	_enter(Stage.ANNOUNCE)
	_typed = Loc.t("AUTO-DEFENSE OFFLINE  -  SECOND MISSILE INBOUND")
	_type_shown = 0
	_banner_line.text = ""
	_banner_sub.visible = false
	_banner.visible = true
	_banner.scale = Vector2(1.5, 1.5)
	_banner.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_banner, "modulate:a", 1.0, 0.12)
	_shake(12.0, 0.35)
	EventBus.sfx_requested.emit("alarm_red")


func _tick_banner() -> void:
	var want := clampi(int((_t - 0.45) * 42.0), 0, _typed.length())
	if want > _type_shown:
		if want % 2 == 0:
			EventBus.sfx_requested.emit("type_blip")
		_type_shown = want
		_banner_line.text = _typed.substr(0, _type_shown)
	_banner_sub.visible = _t >= 2.1 and fmod(_t, 0.5) < 0.32


func _hide_banner() -> void:
	var tween := create_tween()
	tween.tween_property(_banner, "scale", Vector2(1.0, 0.0), 0.16)
	tween.tween_callback(func() -> void: _banner.visible = false)


func _draw_banner() -> void:
	var top := 40.0
	var bottom := 270.0
	_banner.draw_rect(Rect2(0, top, 1920, bottom - top), Color(0.06, 0.0, 0.0, 0.93))
	_banner.draw_rect(Rect2(0, top + 30, 1920, bottom - top - 60), Color(0.35, 0.0, 0.0, 0.25 + 0.15 * sin(_clock * 6.0)))
	for y: float in [top, bottom - 26.0]:   # moving hazard stripes
		_banner.draw_rect(Rect2(0, y, 1920, 26), Color(0.08, 0.02, 0.0))
		var offset := fmod(_clock * 90.0, 80.0)
		var x := -80.0 + offset
		while x < 1960.0:
			_banner.draw_colored_polygon(PackedVector2Array([Vector2(x, y + 26), Vector2(x + 26, y), Vector2(x + 52, y), Vector2(x + 26, y + 26)]), Color(1.0, 0.25, 0.15))
			x += 80.0


# ---------------------------------------------------------------- console

func _build_console() -> void:
	_console = Control.new()
	_console.position = CONSOLE_HIDDEN
	_console.size = CONSOLE_SIZE
	_console.mouse_filter = Control.MOUSE_FILTER_STOP
	_console.draw.connect(_draw_console)
	_console.visible = false
	add_child(_console)
	var labels := ["7", "8", "9", "4", "5", "6", "1", "2", "3", Loc.t("CLR"), "0", "<"]
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i]
		button.position = Vector2(1180 + (i % 3) * 116, 378 + floori(i / 3.0) * 108)
		button.size = Vector2(104, 96)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 38 if labels[i].length() == 1 else 26)
		button.add_theme_color_override("font_color", SYMBOL_COLOR)
		button.add_theme_color_override("font_hover_color", C.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(1.0, 0.3, 0.3, 0.7))
		button.add_theme_stylebox_override("normal", C.box(Color(0.12, 0.03, 0.03), LINE, 2))
		button.add_theme_stylebox_override("hover", C.box(Color(0.25, 0.06, 0.05), AMBER, 3))
		button.add_theme_stylebox_override("pressed", C.box(Color(0.45, 0.1, 0.05), C.WHITE, 3))
		button.add_theme_stylebox_override("disabled", C.box(Color(0.2, 0.0, 0.0), Color(1.0, 0.2, 0.2, 0.6), 2))
		button.add_theme_stylebox_override("focus", C.box(Color(0.12, 0.03, 0.03), LINE, 2))
		var label: String = labels[i]
		if label == Loc.t("CLR") or label == "<":
			button.pressed.connect(_clear_entry)
		else:
			button.pressed.connect(_press.bind(int(label)))
		_console.add_child(button)
		_keypad.append(button)


func _open_console() -> void:
	_enter(Stage.CONSOLE)
	_time_total = float(_settings["time"])
	_time_left = _time_total
	_code_index = 0
	_intercept_hit = false
	_last_tick = -1
	_new_code()
	_console.visible = true
	_console.position = CONSOLE_HIDDEN
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_console, "position", CONSOLE_POS, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_dim, "modulate:a", 1.0, 0.3)
	EventBus.sfx_requested.emit("screen_switch")


func _new_code() -> void:
	var codes: Array = _settings["codes"]
	var length := int(codes[_code_index])
	var digits: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	digits.shuffle()
	_key = digits
	var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	order.shuffle()
	_key_order = order
	_code.clear()
	for i in length:
		var symbol := _rng.randi_range(0, 9)
		while not _code.is_empty() and symbol == _code.back():
			symbol = _rng.randi_range(0, 9)
		_code.append(symbol)
	_entry.clear()
	_glitch.clear()
	_status = Loc.t("ENTER %s CODE") % _stage_name(_code_index)
	_status_color = AMBER


func _stage_name(index: int) -> String:
	var names: Array = _settings.get("stage_names", [Loc.t("ARM"), Loc.t("TARGET"), Loc.t("FIRE")])
	return Loc.t(str(names[mini(index, names.size() - 1)]))


func _tick_console(delta: float) -> void:
	if _t < 0.4:
		return   # sliding in
	_time_left = maxf(0.0, _time_left - delta)
	GameState.add_fear(float(_fear_cfg["per_second"]) * delta)
	_lock = maxf(0.0, _lock - delta)
	_error_flash = maxf(0.0, _error_flash - delta)
	_accept_flash = maxf(0.0, _accept_flash - delta)
	for button in _keypad:
		button.disabled = _lock > 0.0 or _between > 0.0
	if _between > 0.0:
		_between -= delta
		if _between <= 0.0:
			_code_index += 1
			_new_code()
	var whole := ceili(_time_left)
	if whole <= 5 and whole != _last_tick and _time_left > 0.0:
		_last_tick = whole
		EventBus.sfx_requested.emit("countdown_tick")
	_tick_glitches(delta)
	# A frightened operator's console shakes.
	var panic := clampf((GameState.fear - 60.0) / 40.0, 0.0, 1.0)
	_console.position = CONSOLE_POS + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * panic * 4.0
	if _time_left <= 0.0:
		_lose()


## Fear makes the cipher key lie for a moment: random entries flash a wrong digit.
func _tick_glitches(delta: float) -> void:
	for symbol in _glitch.keys():
		if float(_glitch[symbol]["until"]) <= _clock:
			_glitch.erase(symbol)
	_glitch_timer -= delta
	if _glitch_timer > 0.0:
		return
	_glitch_timer = 0.22
	var from := float(_fear_cfg["glitch_from"])
	var chance := clampf((GameState.fear - from) / (100.0 - from), 0.0, 1.0) * 0.85
	if _rng.randf() < chance:
		var symbol := _rng.randi_range(0, 9)
		var wrong := (_key[symbol] + _rng.randi_range(1, 9)) % 10
		_glitch[symbol] = {"digit": wrong, "until": _clock + _rng.randf_range(0.25, 0.5)}


func _press(digit: int) -> void:
	if _stage != Stage.CONSOLE or _t < 0.4 or _lock > 0.0 or _between > 0.0:
		return
	var want := _key[_code[_entry.size()]]
	if digit != want:
		_reject()
		return
	_entry.append(digit)
	EventBus.sfx_requested.emit("key_clack")
	if _entry.size() >= _code.size():
		_accept()


func _clear_entry() -> void:
	if _stage == Stage.CONSOLE and _lock <= 0.0:
		_entry.clear()


func _accept() -> void:
	EventBus.sfx_requested.emit("code_accept")
	_accept_flash = 0.6
	GameState.add_fear(float(_fear_cfg["per_stage"]))
	_status = Loc.t("%s CODE ACCEPTED") % _stage_name(_code_index)
	_status_color = C.GREEN
	if _code_index >= (_settings["codes"] as Array).size() - 1:
		_win()
	else:
		_between = 0.45


func _reject() -> void:
	EventBus.sfx_requested.emit("failure_buzzer")
	_error_flash = 0.5
	_lock = float(_settings["error_lock"])
	_entry.clear()
	GameState.add_fear(float(_fear_cfg["per_error"]))
	_shake(7.0, 0.25)
	_status = Loc.t("WRONG DIGIT  -  KEYPAD LOCKED")
	_status_color = C.RED


func _win() -> void:
	_enter(Stage.WON)
	_status = Loc.t("INTERCEPTOR AWAY")
	_status_color = C.GREEN
	for button in _keypad:
		button.disabled = true
	EventBus.sfx_requested.emit("intercept_launch")


func _tick_won() -> void:
	if _t >= 0.7 and not _intercept_hit:
		_intercept_hit = true
		EventBus.sfx_requested.emit("intercept_hit")
		_flash.color.a = 0.35
		_shake(8.0, 0.4)
		_tint_target = 0.0
		_set_klaxon(false)
		GameState.add_fear(-30.0)
		_status = Loc.t("COUNTER-DEFENSE RESTORED")
	if _t >= 2.8:
		_outro(true)


func _lose() -> void:
	_enter(Stage.LOST)
	_status = Loc.t("DEFENSE BREACHED")
	_status_color = C.RED
	_error_flash = 1.0
	for button in _keypad:
		button.disabled = true
	EventBus.sfx_requested.emit("failure_buzzer")


func _tick_lost() -> void:
	if _t >= 0.8 and not _second_launched:
		_second_launched = true
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_console, "position", CONSOLE_HIDDEN, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_dim, "modulate:a", 0.0, 0.35)
		_launch(SKY_LEFT, _point(_second), 1.1, _second_impact)
		EventBus.sfx_requested.emit("missile_whistle")
	if _t >= 4.0:
		_outro(false)


func _input(event: InputEvent) -> void:
	if _stage == Stage.IDLE or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and _stage == Stage.CONSOLE:
		var code := key.physical_keycode
		if code >= KEY_0 and code <= KEY_9:
			_press(code - KEY_0)
		elif code >= KEY_KP_0 and code <= KEY_KP_9:
			_press(code - KEY_KP_0)
		elif code == KEY_BACKSPACE or code == KEY_DELETE:
			_clear_entry()
	get_viewport().set_input_as_handled()   # no game hotkeys during the event


# ---------------------------------------------------------------- console drawing

func _text(at: Vector2, text: String, font_size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_console.draw_string(_console.get_theme_default_font(), at, text, align, width, font_size, color)


func _draw_console() -> void:
	var w := CONSOLE_SIZE.x
	var h := CONSOLE_SIZE.y
	var won := _stage == Stage.WON
	var border := C.GREEN if won else (C.RED if _error_flash > 0.0 and fmod(_clock, 0.16) < 0.08 else LINE)
	_console.draw_rect(Rect2(0, 0, w, h), DEEP)
	# Header strip.
	var header := Color(0.1, 0.55, 0.25) if won else Color(0.7, 0.08, 0.08, 0.8 + 0.2 * sin(_clock * 8.0))
	_console.draw_rect(Rect2(0, 0, w, 64), header)
	_text(Vector2(26, 46), Loc.t("COUNTER-DEFENSE  -  MANUAL OVERRIDE"), 40, Color(0.02, 0.0, 0.0))
	var right := Loc.t("SYSTEM ONLINE") if won else Loc.t("AUTO-DEFENSE: OFFLINE")
	if won or fmod(_clock, 0.8) < 0.55:
		_text(Vector2(0, 46), right + "   ", 32, Color(0.02, 0.0, 0.0), HORIZONTAL_ALIGNMENT_RIGHT, w)
	_console.draw_rect(Rect2(0, 0, w, h), border, false, 3.0)

	_draw_track()
	_draw_timer()
	_draw_stages()
	_draw_code()
	_draw_key()
	_draw_static()

	if won and _intercept_hit:
		var band := Rect2(40, 560, 640, 120)
		_console.draw_rect(band, Color(0.05, 0.3, 0.12, 0.9))
		_console.draw_rect(band, C.GREEN, false, 3.0)
		_text(Vector2(band.position.x, band.position.y + 56), Loc.t("COUNTER-DEFENSE"), 52, C.GREEN, HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
		_text(Vector2(band.position.x, band.position.y + 102), Loc.t("RESTORED"), 52, C.GREEN, HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
	elif _stage == Stage.LOST:
		var band := Rect2(40, 560, 640, 120)
		_console.draw_rect(band, Color(0.3, 0.0, 0.0, 0.9))
		_console.draw_rect(band, C.RED, false, 3.0)
		_text(Vector2(band.position.x, band.position.y + 80), Loc.t("DEFENSE BREACHED"), 56, C.RED, HORIZONTAL_ALIGNMENT_CENTER, band.size.x)
	else:
		_text(Vector2(60, 640), _status, 34, _status_color)
		_text(Vector2(60, 700), Loc.t("Find each symbol in the cipher key and type its digit."), 24, Color(1.0, 0.75, 0.7, 0.75))
		_text(Vector2(60, 732), Loc.t("Keys 0-9 or the keypad.  A wrong digit locks the keypad."), 24, Color(1.0, 0.75, 0.7, 0.75))


func _draw_track() -> void:
	_text(Vector2(60, 106), Loc.t("MISSILE 2  -  INBOUND TRACK"), 26, Color(1.0, 0.5, 0.45))
	var progress := 1.0 - _time_left / maxf(_time_total, 0.01)
	if _stage == Stage.LOST:
		progress = 1.0
	# Range ticks.
	for i in 11:
		var x := lerpf(TRACK_FROM, TRACK_TO, i / 10.0)
		_console.draw_line(Vector2(x, TRACK_Y + 14), Vector2(x, TRACK_Y + 24), Color(LINE, 0.8), 2.0)
	_console.draw_dashed_line(Vector2(TRACK_FROM, TRACK_Y), Vector2(TRACK_TO, TRACK_Y), Color(LINE, 0.7), 2.0, 10.0)
	# Depot (left) and city skyline (right).
	_console.draw_rect(Rect2(64, TRACK_Y - 30, 50, 40), Color(0.35, 0.1, 0.08))
	_console.draw_colored_polygon(PackedVector2Array([Vector2(64, TRACK_Y - 30), Vector2(89, TRACK_Y - 52), Vector2(114, TRACK_Y - 30)]), Color(0.45, 0.12, 0.1))
	_text(Vector2(56, TRACK_Y + 52), Loc.t("DEPOT"), 24, Color(1.0, 0.6, 0.5))
	var heights := [34.0, 56.0, 42.0, 70.0, 38.0, 50.0]
	for i in heights.size():
		var bh: float = heights[i]
		_console.draw_rect(Rect2(1066 + i * 13, TRACK_Y + 10 - bh, 11, bh), Color(0.3, 0.75, 0.5) if _stage == Stage.WON else Color(0.55, 0.6, 0.62))
	_text(Vector2(1070, TRACK_Y + 52), Loc.t("CITY"), 24, C.WHITE)
	# The missile, unless it has been shot down.
	var mx := lerpf(TRACK_FROM, TRACK_TO, progress)
	if not _intercept_hit:
		for i in 10:
			var tx := mx - 10.0 - i * 9.0
			if tx > TRACK_FROM - 10.0:
				_console.draw_circle(Vector2(tx, TRACK_Y + _rng.randf_range(-2, 2)), 7.0 - i * 0.6, Color(1.0, 0.5 + i * 0.03, 0.1, 0.8 - i * 0.07))
		_console.draw_colored_polygon(PackedVector2Array([Vector2(mx + 24, TRACK_Y), Vector2(mx - 6, TRACK_Y - 9), Vector2(mx - 12, TRACK_Y), Vector2(mx - 6, TRACK_Y + 9)]), C.WHITE)
	# Interceptor from the city to the missile, then the airburst.
	if _stage == Stage.WON:
		var flight := clampf(_t / 0.7, 0.0, 1.0)
		var ix := lerpf(1060.0, mx + 20.0, flight)
		if not _intercept_hit:
			_console.draw_line(Vector2(1060, TRACK_Y), Vector2(ix, TRACK_Y), Color(0.5, 1.0, 0.7, 0.7), 4.0)
			_console.draw_circle(Vector2(ix, TRACK_Y), 8.0, C.GREEN)
		else:
			var age := _t - 0.7
			_console.draw_circle(Vector2(mx + 20, TRACK_Y), 70.0 * minf(1.0, age * 4.0), Color(1.0, 0.8, 0.35, maxf(0.0, 0.9 - age)))
			_console.draw_arc(Vector2(mx + 20, TRACK_Y), age * 260.0, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, maxf(0.0, 0.8 - age)), 4.0)


func _draw_timer() -> void:
	var box := Rect2(1180, 84, 336, 150)
	_console.draw_rect(box, Color(0.1, 0.02, 0.02))
	var color := C.WHITE
	if _time_left <= 5.0:
		color = C.RED if fmod(_clock, 0.3) < 0.18 else Color(1.0, 0.6, 0.6)
	elif _time_left <= 10.0:
		color = C.YELLOW
	if _stage == Stage.WON:
		color = C.GREEN
	_console.draw_rect(box, color, false, 2.0)
	_text(Vector2(box.position.x, 122), Loc.t("INTERCEPTED") if _stage == Stage.WON else Loc.t("IMPACT IN"), 30, color, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_text(Vector2(box.position.x, 214), "%04.1f" % _time_left, 88, color, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)


func _draw_stages() -> void:
	var codes: Array = _settings.get("codes", [4, 5, 6])
	for i in codes.size():
		var rect := Rect2(60 + i * 260, 252, 230, 58)
		var done := i < _code_index or (i == _code_index and (_stage == Stage.WON or _between > 0.0))
		var current := i == _code_index and not done
		var color := Color(LINE, 0.6)
		if done:
			color = C.GREEN
			_console.draw_rect(rect, Color(C.GREEN, 0.18))
		elif current:
			color = AMBER.lerp(C.WHITE, 0.5 + 0.5 * sin(_clock * 6.0))
			_console.draw_rect(rect, Color(AMBER, 0.12))
		_console.draw_rect(rect, color, false, 3.0 if current else 2.0)
		_text(Vector2(rect.position.x, rect.position.y + 40), "%s  %d" % [_stage_name(i), int(codes[i])], 32, color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		if i < codes.size() - 1:
			var ax := rect.end.x + 8.0
			_console.draw_colored_polygon(PackedVector2Array([Vector2(ax, 268), Vector2(ax + 14, 281), Vector2(ax, 294)]), Color(LINE, 0.9))


func _draw_code() -> void:
	_text(Vector2(60, 360), Loc.t("ENCRYPTED CODE"), 28, Color(1.0, 0.5, 0.45))
	var jitter := clampf((GameState.fear - 50.0) / 50.0, 0.0, 1.0) * 3.0
	for i in _code.size():
		var box := Rect2(60 + i * 102, 378, 92, 92)
		var typed := i < _entry.size()
		var current := i == _entry.size() and _stage == Stage.CONSOLE
		_console.draw_rect(box, Color(0.12, 0.03, 0.03))
		var edge := C.GREEN if typed else (AMBER if current else Color(LINE, 0.8))
		if _error_flash > 0.0:
			edge = C.RED
		_console.draw_rect(box, edge, false, 4.0 if current else 2.0)
		var offset := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * jitter
		_draw_symbol(_console, _code[i], box.get_center() + offset, 30.0, Color(SYMBOL_COLOR, 0.35) if typed else SYMBOL_COLOR)
		if current:
			_console.draw_colored_polygon(PackedVector2Array([box.get_center() + Vector2(-10, 56), box.get_center() + Vector2(10, 56), box.get_center() + Vector2(0, 44)]), AMBER)
	_text(Vector2(60, 518), Loc.t("DIGITS"), 24, Color(1.0, 0.5, 0.45))
	for i in _code.size():
		var box := Rect2(60 + i * 102, 528, 92, 66)
		var edge := Color(LINE, 0.6)
		if _error_flash > 0.0:
			edge = C.RED
		elif i < _entry.size():
			edge = C.GREEN
		_console.draw_rect(box, Color(0.08, 0.02, 0.02))
		_console.draw_rect(box, edge, false, 2.0)
		if i < _entry.size():
			_text(Vector2(box.position.x, box.position.y + 54), str(_entry[i]), 58, C.GREEN, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
		elif i == _entry.size() and _stage == Stage.CONSOLE and fmod(_clock, 0.6) < 0.35:
			_console.draw_rect(Rect2(box.position.x + 26, box.position.y + 50, 40, 5), AMBER)
	if _accept_flash > 0.0:
		_console.draw_rect(Rect2(52, 370, _code.size() * 102 + 6, 232), Color(C.GREEN, _accept_flash * 0.5), false, 4.0)


func _draw_key() -> void:
	_text(Vector2(740, 360), Loc.t("CIPHER KEY"), 28, Color(1.0, 0.5, 0.45))
	for slot in 10:
		var symbol := _key_order[slot] if slot < _key_order.size() else slot
		var rect := Rect2(740 + (slot % 2) * 202, 378 + floori(slot / 2.0) * 88, 190, 80)
		_console.draw_rect(rect, Color(0.1, 0.03, 0.03))
		_console.draw_rect(rect, Color(LINE, 0.7), false, 2.0)
		_draw_symbol(_console, symbol, rect.position + Vector2(48, 40), 25.0, SYMBOL_COLOR)
		_text(Vector2(rect.position.x + 92, rect.position.y + 54), "=", 40, Color(1.0, 0.6, 0.5))
		if symbol >= _key.size():
			continue
		var digit := _key[symbol]
		var at := Vector2(rect.position.x + 128, rect.position.y + 60)
		if _glitch.has(symbol):
			var fake := int(_glitch[symbol]["digit"])
			var wobble := Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-2, 2))
			_text(at + wobble + Vector2(3, 0), str(fake), 62, Color(0.2, 0.9, 1.0, 0.5))
			_text(at + wobble, str(fake), 62, Color(1.0, 0.75, 0.85))
		else:
			_text(at, str(digit), 62, C.WHITE)


## Interference lines across the console as fear rises.
func _draw_static() -> void:
	var ratio := clampf((GameState.fear - 30.0) / 70.0, 0.0, 1.0)
	var lines := int(ratio * 10.0)
	for i in lines:
		var y := _rng.randf_range(70.0, CONSOLE_SIZE.y - 10.0)
		_console.draw_rect(Rect2(0, y, CONSOLE_SIZE.x, _rng.randf_range(1.0, 4.0)), Color(1.0, 0.3, 0.3, _rng.randf_range(0.04, 0.14)))


## Ten easy-to-tell-apart glyphs, drawn rather than taken from the font.
func _draw_symbol(canvas: CanvasItem, id: int, center: Vector2, r: float, color: Color) -> void:
	match id:
		0:   # filled triangle
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.95, r * 0.75), center + Vector2(-r * 0.95, r * 0.75)]), color)
		1:   # hollow triangle, pointing down
			var points := PackedVector2Array([center + Vector2(-r * 0.95, -r * 0.75), center + Vector2(r * 0.95, -r * 0.75), center + Vector2(0, r), center + Vector2(-r * 0.95, -r * 0.75)])
			canvas.draw_polyline(points, color, 4.0)
		2:   # filled diamond
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.8, 0), center + Vector2(0, r), center + Vector2(-r * 0.8, 0)]), color)
		3:   # ring with a dot
			canvas.draw_arc(center, r * 0.85, 0.0, TAU, 32, color, 4.0)
			canvas.draw_circle(center, r * 0.22, color)
		4:   # hollow square
			canvas.draw_rect(Rect2(center - Vector2(r, r) * 0.78, Vector2(r, r) * 1.56), color, false, 4.0)
		5:   # plus
			canvas.draw_rect(Rect2(center - Vector2(r * 0.22, r), Vector2(r * 0.44, r * 2.0)), color)
			canvas.draw_rect(Rect2(center - Vector2(r, r * 0.22), Vector2(r * 2.0, r * 0.44)), color)
		6:   # X
			canvas.draw_line(center + Vector2(-r, -r) * 0.8, center + Vector2(r, r) * 0.8, color, 7.0)
			canvas.draw_line(center + Vector2(r, -r) * 0.8, center + Vector2(-r, r) * 0.8, color, 7.0)
		7:   # filled star
			var star := PackedVector2Array()
			for k in 10:
				var radius := r if k % 2 == 0 else r * 0.42
				var angle := -PI * 0.5 + k * PI / 5.0
				star.append(center + Vector2(cos(angle), sin(angle)) * radius)
			canvas.draw_colored_polygon(star, color)
		8:   # hollow hexagon
			var hex := PackedVector2Array()
			for k in 7:
				var angle := k * PI / 3.0
				hex.append(center + Vector2(cos(angle), sin(angle)) * r * 0.9)
			canvas.draw_polyline(hex, color, 4.0)
		_:   # half-filled circle
			var half := PackedVector2Array()
			for k in 17:
				var angle := PI + k * PI / 16.0
				half.append(center + Vector2(cos(angle), sin(angle)) * r * 0.85)
			canvas.draw_colored_polygon(half, color)
			canvas.draw_arc(center, r * 0.85, 0.0, TAU, 32, color, 3.0)
