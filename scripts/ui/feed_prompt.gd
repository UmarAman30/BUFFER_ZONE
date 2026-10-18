extends Control
## First live feed report of the session: the game pauses and a card asks the player to right-click
## to open the feed. The right-click opens it and the shift carries on. Shown once per launch.

const C := preload("res://scripts/ui/ui_colors.gd")
const CARD_SIZE := Vector2(980, 380)

var map: Control   # map_screen, to open the feed

var _card: Control
var _clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_card = Panel.new()
	_card.size = CARD_SIZE
	_card.position = (Vector2(1920, 1080) - CARD_SIZE) * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", C.dialog_style(C.YELLOW, 26.0))
	add_child(_card)
	C.add_frame(_card, C.YELLOW)

	var art := Control.new()
	art.size = CARD_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_mouse.bind(art))
	_card.add_child(art)

	_label(Loc.t("INCOMING REPORT"), Vector2(300, 40), 46, C.YELLOW)
	_label(Loc.t("Reports are arriving in the live feed."), Vector2(300, 130), 28, C.WHITE)
	_label(Loc.t("RIGHT-CLICK anywhere to open it."), Vector2(300, 180), 28, C.YELLOW)
	_label(Loc.t("Right-click again to close it."), Vector2(300, 230), 24, C.DIM.lightened(0.7))
	_label(Loc.t("Reports often arrive before the alert does."), Vector2(300, 290), 24, C.DIM.lightened(0.7))

	EventBus.feed_entry_added.connect(_on_feed_entry)


func _label(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_card.add_child(label)


func _on_feed_entry(_entry: Dictionary) -> void:
	if PlayerData.feed_prompt_done or GameState.state != GameState.State.PLAYING or get_tree().paused:
		return
	PlayerData.feed_prompt_done = true
	visible = true
	get_tree().paused = true
	EventBus.sfx_requested.emit("feed_ping")


func _process(delta: float) -> void:
	if visible:
		_clock += delta
		for child in _card.get_children():
			if child is Control and not (child is Label):
				child.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			visible = false
			get_tree().paused = false
			if map != null:
				map.set_feed_open(true)
			EventBus.sfx_requested.emit("feed_open")
	get_viewport().set_input_as_handled()   # nothing else reacts until the feed is opened


## A mouse with its right button lit up.
func _draw_mouse(art: Control) -> void:
	var center := Vector2(150, 190)
	var body := Rect2(center - Vector2(70, 100), Vector2(140, 200))
	var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
	art.draw_rect(body, Color(C.PANEL, 1.0))
	# Right button, glowing.
	art.draw_rect(Rect2(body.position + Vector2(70, 0), Vector2(70, 80)), Color(C.YELLOW, 0.35 + 0.5 * pulse))
	art.draw_rect(body, C.TEXT, false, 4.0)
	art.draw_line(body.position + Vector2(0, 80), body.position + Vector2(140, 80), C.TEXT, 3.0)
	art.draw_line(body.position + Vector2(70, 0), body.position + Vector2(70, 80), C.TEXT, 3.0)
	art.draw_rect(Rect2(center + Vector2(-8, -78), Vector2(16, 34)), C.TEXT)
	# Click ripples off the right button.
	var at := body.position + Vector2(105, 40)
	for k in 2:
		var p := fmod(_clock * 1.2 + k * 0.5, 1.0)
		art.draw_arc(at, 20.0 + 50.0 * p, -PI * 0.5, PI * 0.25, 20, Color(C.YELLOW, 1.0 - p), 3.0)
