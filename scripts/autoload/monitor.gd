extends Node
## Draws the whole game as if on a monitor inside the game: every scene (title, terminal, shift)
## is moved into a 1920x1080 SubViewport shown slightly smaller, framed by a moulded bezel with an
## engraved label and a power LED (green / amber / blinking red with public trust). Each new scene
## switches on with a short CRT power-on squeeze. Works with plain change_scene_to_file calls.

const SCREEN_SCALE := 0.93
const SCREEN_POS := Vector2(67, 24)
const BASE_SIZE := Vector2(1920, 1080)
const BEZEL_SHADER := preload("res://assets/shaders/bezel.gdshader")

var _layer: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _led: Control
var _led_color := Color(0.3, 0.95, 0.45)
## Title screen: the power lamp shows red (standby) until the player starts the game.
var standby: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 0
	add_child(_layer)

	var backing := ColorRect.new()
	backing.color = Color(0, 0, 0)
	backing.size = BASE_SIZE
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(backing)

	_container = SubViewportContainer.new()
	_container.stretch = false
	_container.focus_mode = Control.FOCUS_NONE   # keyboard is forwarded by _input below, never twice
	_container.size = BASE_SIZE
	# Pivot on the vertical centre line so the power-on squeeze opens from the middle; position is
	# shifted to compensate so the scaled screen's top-left lands exactly on SCREEN_POS.
	_container.pivot_offset = BASE_SIZE * 0.5   # switch-on / switch-off squeeze toward the centre
	_container.position = SCREEN_POS - BASE_SIZE * 0.5 * (1.0 - SCREEN_SCALE)
	_container.scale = Vector2(SCREEN_SCALE, SCREEN_SCALE)
	_layer.add_child(_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(BASE_SIZE)
	_viewport.handle_input_locally = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.audio_listener_enable_2d = false
	_container.add_child(_viewport)

	var bezel := ColorRect.new()
	bezel.size = BASE_SIZE
	bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BEZEL_SHADER
	material.set_shader_parameter("screen_rect", Vector4(SCREEN_POS.x, SCREEN_POS.y, BASE_SIZE.x * SCREEN_SCALE, BASE_SIZE.y * SCREEN_SCALE))
	bezel.material = material
	_layer.add_child(bezel)

	var label := Label.new()
	label.text = Loc.t("EOC-9   -   KIRANCHI MUNICIPAL EMERGENCY OPERATIONS")
	label.position = Vector2(0, BASE_SIZE.y - 46)
	label.size = Vector2(BASE_SIZE.x, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.32, 0.32, 0.34))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 1)
	var font := load("res://assets/fonts/HomeVideo-Bold.ttf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	_layer.add_child(label)
	Loc.language_changed.connect(func(_lang: String) -> void: label.text = Loc.t("EOC-9   -   KIRANCHI MUNICIPAL EMERGENCY OPERATIONS"))

	_led = Control.new()
	_led.position = Vector2(BASE_SIZE.x - 150, BASE_SIZE.y - 44)
	_led.size = Vector2(110, 36)
	_led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_led.draw.connect(_draw_led)
	_layer.add_child(_led)

	get_tree().node_added.connect(_on_node_added)
	_capture.call_deferred()


## The SubViewportContainer only passes mouse input through by position; keyboard (and other
## non-mouse) input would only reach the game while the container had focus. Forward it ourselves.
func _input(event: InputEvent) -> void:
	# F11 (or Alt+Enter) toggles fullscreen / windowed anywhere in the game.
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_F11 or (key.alt_pressed and key.physical_keycode == KEY_ENTER):
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return
	_viewport.push_input(event)
	get_viewport().set_input_as_handled()


## A new scene lands on the root when change_scene_to_file runs; move it onto the monitor.
func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root:
		_capture.call_deferred()


func _capture() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.get_parent() == _viewport:
		return
	# Godot only frees the old scene when it is still under the root, so the previous scene (which
	# lives on the monitor) has to be cleared here, or it would keep drawing over the new one.
	for old in _viewport.get_children():
		_viewport.remove_child(old)
		old.queue_free()
	scene.reparent(_viewport, false)
	_power_on()


## CRT switch-on: the picture opens from a bright horizontal line.
func _power_on() -> void:
	_container.scale = Vector2(SCREEN_SCALE, 0.004)
	_container.modulate = Color(3, 3, 3)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(_container, "scale", Vector2(SCREEN_SCALE, SCREEN_SCALE), 0.35)
	tween.tween_property(_container, "modulate", Color.WHITE, 0.5)
	EventBus.sfx_requested.emit("static_burst")


## CRT switch-off: the picture flares, collapses to a bright line, then to a dot, then goes dark.
## Await the returned signal before changing scene or quitting.
func power_off(duration: float = 0.55) -> Signal:
	var tween := create_tween()
	tween.tween_property(_container, "modulate", Color(2.6, 2.6, 2.6), duration * 0.15)
	tween.tween_property(_container, "scale", Vector2(SCREEN_SCALE, 0.004), duration * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(_container, "scale", Vector2(0.002, 0.004), duration * 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(_container, "modulate:a", 0.0, duration * 0.2)
	tween.tween_interval(0.25)
	return tween.finished


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var color := Color(0.3, 0.95, 0.45)
	if standby:
		color = Color(1.0, 0.18, 0.15) if fmod(now, 2.4) < 2.0 else Color(0.55, 0.08, 0.07)
	elif GameState.state == GameState.State.PLAYING:
		if GameState.trust <= 25.0:
			color = Color(1.0, 0.2, 0.2) if fmod(now, 0.6) < 0.3 else Color(0.25, 0.05, 0.05)
		elif GameState.trust <= 50.0:
			color = Color(1.0, 0.7, 0.15)
	elif GameState.state == GameState.State.GAME_OVER:
		color = Color(1.0, 0.2, 0.2)
	if color != _led_color:
		_led_color = color
		_led.queue_redraw()


func _draw_led() -> void:
	var center := Vector2(14, 18)
	_led.draw_circle(center, 13.0, Color(_led_color, 0.18))
	_led.draw_circle(center, 7.0, _led_color)
	_led.draw_circle(center + Vector2(-2, -2), 2.5, Color(1, 1, 1, 0.5))
	_led.draw_string(_led.get_theme_default_font(), Vector2(32, 26), "PWR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.35, 0.35, 0.37))
