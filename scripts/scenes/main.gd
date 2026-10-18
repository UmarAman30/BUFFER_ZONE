extends Control
## Root scene. Holds the two screens (Map and Feed), the HUD, the game-over overlay and the CRT effect.

const C := preload("res://scripts/ui/ui_colors.gd")
const MapScreenScript := preload("res://scripts/ui/map_screen.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const BriefingScript := preload("res://scripts/ui/briefing.gd")
const MissileEventScript := preload("res://scripts/ui/missile_event.gd")
const FeedPromptScript := preload("res://scripts/ui/feed_prompt.gd")
const ShiftReportScript := preload("res://scripts/ui/shift_report.gd")
const ReportLineScript := preload("res://scripts/ui/report_line.gd")
const CRT_SHADER := preload("res://assets/shaders/crt.gdshader")
## VT323 draws smaller than the default font at the same size, so every font size is scaled up once.
const FONT_SCALE := 1.4

var _screens: Dictionary = {}
var _game_over_layer: Control
var _final_label: Label
var _tagline_label: Label
var _stars_view: Control
var _star_count: int = 0
var _star_shown: float = 0.0
var _crt: ColorRect
var _pause_layer: Control
var _team_layer: Control
var _team_text: Label
var _over_style: StyleBoxFlat
var _over_title: Label
var _over_frame: Control
var _shift_report: Control
var _quit_button: Button
var _quit_armed := false
var _pause_card: Panel
var _briefing_active: bool = false
var _flash: ColorRect
var _danger: TextureRect
var _shake_time: float = 0.0
var _shake_total: float = 0.4
var _shake_strength: float = 0.0


func _ready() -> void:
	# Language switched from the pause menu (CONTROLS tab): swap the static text in place.
	Loc.language_changed.connect(_on_language_changed)
	ThemeDB.fallback_font_size = roundi(16 * FONT_SCALE)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Control:
			_scale_font.call_deferred(node))

	var background := ColorRect.new()
	background.color = C.BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var map_screen = MapScreenScript.new()
	add_child(map_screen)
	_screens["map"] = map_screen

	add_child(HudScript.new())
	_build_game_over_layer()
	_build_pause_ui()
	_build_team_dialog()
	# Minute-four missile event: red wash, banner and the override console, above the game.
	var missile_event = MissileEventScript.new()
	missile_event.map = map_screen
	add_child(missile_event)
	# First feed report of the session: "right-click to open the live feed".
	var feed_prompt = FeedPromptScript.new()
	feed_prompt.map = map_screen
	add_child(feed_prompt)
	_build_feedback_layers()
	_build_crt_overlay()

	EventBus.screen_requested.connect(show_screen)
	EventBus.game_over.connect(_on_game_over)
	EventBus.alert_expired.connect(func(_alert: Alert) -> void: _impact(12.0, 0.4, 0.35))
	EventBus.radio_event.connect(_on_radio_event)
	EventBus.unit_unlocked.connect(func(unit: UnitState) -> void: _show_team_dialog.call_deferred(unit))
	EventBus.rescue_spawned.connect(func(_rescue: Dictionary) -> void: _impact(20.0, 0.8, 0.12))

	show_screen("map")

	# The title screen and terminal run as their own scenes before this one. The shift is set up behind the
	# briefing book and starts (timer, alerts, music) when the player closes it.
	_open_briefing.call_deferred(false)


## Opens the briefing book. At the start of a shift (reference = false) closing it starts the shift;
## from the pause menu (reference = true) it just returns to the pause card.
func _open_briefing(reference: bool) -> void:
	_briefing_active = true
	var book = BriefingScript.new()
	book.reference = reference
	book.closed.connect(func() -> void:
		_briefing_active = false
		if reference:
			_pause_card.visible = true
		else:
			GameState.start_game())
	add_child(book)
	move_child(book, _crt.get_index())   # above the game, below the CRT overlay


## Scales a control's font size overrides by FONT_SCALE, once.
func _scale_font(control: Control) -> void:
	if not is_instance_valid(control) or control.has_meta("font_scaled"):
		return
	control.set_meta("font_scaled", true)
	if control.has_theme_font_size_override("font_size"):
		control.add_theme_font_size_override("font_size", roundi(control.get_theme_font_size("font_size") * FONT_SCALE))


## Red screen flash and a short shake. Strength is in pixels, flash_alpha is the peak red opacity.
func _impact(strength: float, duration: float, flash_alpha: float) -> void:
	_shake_strength = strength
	_shake_total = duration
	_shake_time = duration
	_flash.modulate.a = flash_alpha
	create_tween().tween_property(_flash, "modulate:a", 0.0, duration + 0.2)


func _on_radio_event(kind: String, _unit: UnitState, _alert: Alert) -> void:
	match kind:
		"arrive_wrong":
			_impact(6.0, 0.3, 0.18)
		"recall":
			_impact(4.0, 0.25, 0.12)


func _process(delta: float) -> void:
	if _game_over_layer.visible:
		_stars_view.queue_redraw()
	if _shake_time > 0.0:
		_shake_time -= delta
		var falloff := clampf(_shake_time / _shake_total, 0.0, 1.0)
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * falloff
	elif position != Vector2.ZERO:
		position = Vector2.ZERO

	# Red vignette: grows as trust falls, and throbs gently while any unanswered alert is in the red.
	var playing := GameState.state == GameState.State.PLAYING
	var danger := clampf((60.0 - GameState.trust) / 60.0, 0.0, 1.0) if playing else 0.0
	var red_alert := false
	if playing:
		for alert in World.alerts:
			if not alert.assigned and alert.revealed and alert.phase == Alert.Phase.RED:
				red_alert = true
				break
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / lerpf(380.0, 160.0, danger))
	var target := danger * (0.45 + 0.4 * pulse) + (0.14 * pulse if red_alert else 0.0)
	_danger.modulate.a = lerpf(_danger.modulate.a, target, clampf(delta * 6.0, 0.0, 1.0))


func show_screen(screen_name: String) -> void:
	for key in _screens:
		_screens[key].visible = (key == screen_name)


# ---------------------------------------------------------------- pause menu

func _menu_button(parent: Control, text: String, at: Vector2, button_size: Vector2, font_size: int, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.custom_minimum_size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", C.WHITE)
	var normal := C.box(Color(C.PANEL, 1.0), color, 2)
	var hover := C.box(C.PANEL.lightened(0.15), C.WHITE, 2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	parent.add_child(button)
	return button


func _build_pause_ui() -> void:
	# No on-screen pause button: Esc (or P) pauses; the briefing's CONTROLS tab says so.

	_pause_layer = Control.new()
	_pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)
	var card_size := Vector2(700, 680)
	var card := Panel.new()
	card.size = card_size
	card.position = (Vector2(1920, 1080) - card_size) * 0.5
	card.add_theme_stylebox_override("panel", C.dialog_style(C.YELLOW, 26.0))
	_pause_layer.add_child(card)
	_pause_card = card
	C.add_frame(card, C.YELLOW)
	var title := _centered_label(card, Vector2(0, 40), 64, C.YELLOW)
	title.text = Loc.t("PAUSED")
	var column := VBoxContainer.new()
	column.position = Vector2(70, 150)
	column.size = Vector2(card_size.x - 140.0, 456)
	column.add_theme_constant_override("separation", 24)
	card.add_child(column)
	var wide := Vector2(card_size.x - 140.0, 96)
	_menu_button(column, Loc.t("RESUME"), Vector2.ZERO, wide, 32, C.TEXT).pressed.connect(_set_paused.bind(false))
	_menu_button(column, Loc.t("CONTROLS"), Vector2.ZERO, wide, 32, C.TEXT).pressed.connect(_show_controls)
	_menu_button(column, Loc.t("RESTART"), Vector2.ZERO, wide, 32, C.TEXT).pressed.connect(func() -> void:
		_set_paused(false)
		_restart())
	_quit_button = _menu_button(column, Loc.t("MAIN MENU"), Vector2.ZERO, wide, 32, C.RED)
	_quit_button.pressed.connect(_quit_game)


## MAIN MENU on the pause menu: the shift is abandoned and the monitor switches back to the title.
func _quit_game() -> void:
	# First press asks for confirmation; a second press leaves.
	if not _quit_armed:
		_quit_armed = true
		_quit_button.text = Loc.t("PRESS AGAIN FOR MAIN MENU")
		EventBus.sfx_requested.emit("ui_click")
		return
	_quit_button.disabled = true
	EventBus.sfx_requested.emit("static_burst")
	GameState.abort()   # world, feed and timers stop before the tree is unpaused
	AudioManager.stop_shift_audio()
	_pause_layer.visible = false
	get_tree().paused = false
	await Monitor.power_off()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


# ---------------------------------------------------------------- new team dialog

func _build_team_dialog() -> void:
	_team_layer = Control.new()
	_team_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_team_layer.visible = false
	_team_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_team_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_team_layer.add_child(dim)
	var card_size := Vector2(1000, 520)
	var card := Panel.new()
	card.size = card_size
	card.position = (Vector2(1920, 1080) - card_size) * 0.5
	card.add_theme_stylebox_override("panel", C.dialog_style(C.GREEN, 26.0))
	_team_layer.add_child(card)
	C.add_frame(card, C.GREEN)
	var title := _centered_label(card, Vector2(0, 36), 56, C.GREEN)
	title.text = Loc.t("NEW TEAM ADDED")
	_team_text = _centered_label(card, Vector2(50, 150), 30, C.WHITE)
	_team_text.size = Vector2(card_size.x - 100.0, 200)
	_team_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_button(card, Loc.t("CONTINUE"), Vector2((card_size.x - 400.0) * 0.5, card_size.y - 130.0), Vector2(400, 84), 32, C.GREEN).pressed.connect(_close_team_dialog)


## A rescued team joined: the game stops (so does the score timer) until the player has read this.
func _show_team_dialog(unit: UnitState) -> void:
	if GameState.state != GameState.State.PLAYING:
		return
	_team_text.text = Loc.t("%s joined %s.\nYou now command %d teams.\n\nThe city will push harder. Stay sharp.") % [
		unit.callsign, _team_name(unit.type), World.units.size()]
	_team_layer.visible = true
	get_tree().paused = true


func _close_team_dialog() -> void:
	_team_layer.visible = false
	get_tree().paused = false


func _team_name(unit_type: String) -> String:
	return Loc.upper(str(GameData.unit_types[unit_type]["name"]))


## CONTROLS on the pause menu opens the same book as the start of the shift.
func _show_controls() -> void:
	EventBus.sfx_requested.emit("ui_click")
	_pause_card.visible = false
	_open_briefing(true)


func _set_paused(on: bool) -> void:
	if on and (GameState.state != GameState.State.PLAYING or _briefing_active or _team_layer.visible):
		return
	if on:
		# Keep the pause menu above any popup (feed prompt, banners) but under the CRT overlay.
		move_child(_pause_layer, -1)
		move_child(_crt, -1)
	_pause_layer.visible = on
	get_tree().paused = on
	_quit_armed = false
	_quit_button.text = Loc.t("MAIN MENU")
	EventBus.sfx_requested.emit("ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if _team_layer.visible:
		if event.is_action_pressed("ui_accept"):
			_close_team_dialog()
		get_viewport().set_input_as_handled()
		return
	var toggle: bool = event.is_action_pressed("ui_cancel")
	if event is InputEventKey:
		var key := event as InputEventKey
		toggle = toggle or (key.pressed and not key.echo and key.physical_keycode == KEY_P)
	if toggle and not _briefing_active:
		_set_paused(not _pause_layer.visible)
		get_viewport().set_input_as_handled()


func _build_game_over_layer() -> void:
	_game_over_layer = Control.new()
	_game_over_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.visible = false
	add_child(_game_over_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_layer.add_child(dim)

	# Everything sits on one centred card.
	var card_size := Vector2(1000, 760)
	var card := Panel.new()
	card.size = card_size
	card.position = (Vector2(1920, 1080) - card_size) * 0.5
	_over_style = C.dialog_style(C.RED, 26.0)
	card.add_theme_stylebox_override("panel", _over_style)
	_game_over_layer.add_child(card)
	_over_frame = C.add_frame(card, C.RED)

	_over_title = _centered_label(card, Vector2(0, 40), 64, C.RED)
	_over_title.text = Loc.t("PUBLIC TRUST LOST")

	# Star rating for how long the shift lasted (balance.json "stars").
	_stars_view = Control.new()
	_stars_view.position = Vector2(0, 170)
	_stars_view.size = Vector2(card_size.x, 110)
	_stars_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars_view.draw.connect(_draw_stars)
	card.add_child(_stars_view)

	_final_label = _centered_label(card, Vector2(0, 310), 34, C.TEXT)
	_tagline_label = _centered_label(card, Vector2(40, 390), 22, C.DIM.lightened(0.6))
	_tagline_label.size.x = card_size.x - 80.0
	_tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var restart := Button.new()
	restart.text = Loc.t("RESTART SHIFT")
	restart.size = Vector2(400, 84)
	restart.position = Vector2((card_size.x - 400.0) * 0.5, card_size.y - 84.0 - 50.0)
	restart.focus_mode = Control.FOCUS_NONE
	restart.add_theme_font_size_override("font_size", 28)
	var normal := C.box(Color(C.PANEL, 1.0), C.TEXT, 2)
	var hover := C.box(C.PANEL.lightened(0.15), C.WHITE, 2)
	restart.add_theme_stylebox_override("normal", normal)
	restart.add_theme_stylebox_override("hover", hover)
	restart.add_theme_stylebox_override("pressed", hover)
	restart.add_theme_stylebox_override("focus", normal)
	restart.pressed.connect(_restart)
	card.add_child(restart)

	# A feed-style "incoming report" line; clicking it opens the awareness report card.
	var report_line: Control = ReportLineScript.new()
	report_line.size = Vector2(800, 80)
	report_line.position = Vector2((card_size.x - 800.0) * 0.5, 496)
	card.add_child(report_line)
	_shift_report = ShiftReportScript.new()
	_game_over_layer.add_child(_shift_report)
	report_line.pressed.connect(func() -> void: _shift_report.open())


func _centered_label(parent: Control, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(parent.size.x - at.x * 2.0, font_size * 2.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


## Full-screen red flash and the low-trust danger vignette. Both ignore the mouse.
func _build_feedback_layers() -> void:
	_danger = TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 0, 0, 0), Color(1, 0, 0, 0), Color(1, 0.05, 0.05, 0.8)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_danger.texture = texture
	_danger.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_danger.stretch_mode = TextureRect.STRETCH_SCALE
	_danger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger.modulate.a = 0.0
	add_child(_danger)

	_flash = ColorRect.new()
	_flash.color = Color(1, 0.1, 0.1, 1)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)


## Scanlines and vignette over everything. Ignores the mouse so it never blocks clicks.
func _build_crt_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_material := ShaderMaterial.new()
	crt_material.shader = CRT_SHADER
	overlay.material = crt_material
	add_child(overlay)
	_crt = overlay


func _on_game_over(final_score: int) -> void:
	_pause_layer.visible = false
	if not GameState.victory:
		_impact(22.0, 0.7, 0.5)   # a win gets no red flash or shake
	if GameState.victory:
		_final_label.text = Loc.t("SHIFT COMPLETE  -  TRUST %d%%") % roundi(GameState.trust)
	else:
		_final_label.text = Loc.t("YOU SURVIVED  %s") % HudScript.format_time(final_score)
	_star_count = stars_for(final_score)
	# 3 or 4 stars: the city held, so the card is a green "CITY SECURED"; otherwise the red failure card.
	var secured := _star_count >= 3
	var card_color := C.GREEN if secured else C.RED
	_over_title.text = Loc.t("CITY SECURED") if secured else Loc.t("PUBLIC TRUST LOST")
	_over_title.add_theme_color_override("font_color", card_color)
	_over_style.border_color = Color(card_color, 0.8)
	_over_frame.accent = card_color
	match _star_count:
		2:
			_tagline_label.text = Loc.t("You did alright. Do better next time.")
		3:
			_tagline_label.text = Loc.t("You did great. You helped the city through the night.")
		4:
			_tagline_label.text = Loc.t("Perfect score. Kiranchi owes you everything.")
		_:
			var taglines: Array = GameData.tutorial.get("game_over_taglines", [])
			_tagline_label.text = str(taglines.pick_random()) if not taglines.is_empty() else ""
	_star_shown = 0.0
	create_tween().tween_property(self, "_star_shown", float(_star_count), 0.4 * _star_count).set_delay(0.6)
	if GameState.victory:
		# A chime as each star lights up.
		for i in _star_count:
			get_tree().create_timer(0.6 + 0.4 * (i + 1) - 0.15).timeout.connect(func() -> void:
				EventBus.sfx_requested.emit("resolve_ding"))
	_game_over_layer.visible = true


## Lasting the whole shift wins all 4 stars. Losing early is 1 star, or 2 after the first
## threshold (balance.json "stars").
static func stars_for(seconds: int) -> int:
	var settings: Dictionary = GameData.balance.get("stars", {})
	if GameState.victory:
		return 4
	var thresholds: Array = settings.get("thresholds", [300.0])
	return 2 if seconds >= float(thresholds[0]) else 1


func _draw_stars() -> void:
	var spacing := 120.0
	var start := _stars_view.size.x * 0.5 - spacing * 1.5
	for i in 4:
		var center := Vector2(start + i * spacing, 55)
		var points := PackedVector2Array()
		for k in 10:
			var radius := 44.0 if k % 2 == 0 else 19.0
			var angle := -PI * 0.5 + k * PI / 5.0
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		var fill := clampf(_star_shown - i, 0.0, 1.0)
		if fill > 0.0:
			var size_mult := 0.6 + 0.4 * fill
			var scaled := PackedVector2Array()
			for point in points:
				scaled.append(center + (point - center) * size_mult)
			_stars_view.draw_colored_polygon(scaled, Color(C.YELLOW, fill))
		var outline := points.duplicate()
		outline.append(points[0])
		_stars_view.draw_polyline(outline, Color(C.YELLOW, 0.45), 3.0)


func _on_language_changed(_lang: String) -> void:
	Loc.retranslate(self)


func _restart() -> void:
	_shift_report.close()
	_game_over_layer.visible = false
	EventBus.screen_requested.emit("map")
	GameState.start_game()
