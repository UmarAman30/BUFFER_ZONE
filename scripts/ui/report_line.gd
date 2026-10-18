extends Control
## One clickable "incoming report" row on the game-over card, styled like a live feed line:
## a REPORT chip, a short line of text and an OPEN tag. Emits `pressed` when clicked.

signal pressed

const C := preload("res://scripts/ui/ui_colors.gd")

var _hover := false
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		EventBus.sfx_requested.emit("ui_click")
		pressed.emit()
		accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	var ink := C.WHITE if _hover else C.TEXT
	draw_rect(Rect2(Vector2.ZERO, size), Color(C.TEXT, 0.16) if _hover else Color(C.PANEL, 0.9))
	# Dashed outline, like the NEW marker in the feed.
	var dash := 10.0
	var x := 0.0
	while x < size.x:
		var w := minf(dash, size.x - x)
		draw_rect(Rect2(x, 0, w, 2), Color(ink, 0.7))
		draw_rect(Rect2(x, size.y - 2, w, 2), Color(ink, 0.7))
		x += dash * 2.0
	draw_rect(Rect2(0, 0, 2, size.y), Color(ink, 0.7))
	draw_rect(Rect2(size.x - 2, 0, 2, size.y), Color(ink, 0.7))

	# Blinking chip on the left.
	var chip_text := Loc.t("REPORT")
	var chip_w := font.get_string_size(chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 28.0
	var chip := Rect2(12, 12, chip_w, size.y - 24)
	var blink := fmod(_time, 1.2) < 0.8
	draw_rect(chip, C.TEXT if blink or _hover else Color(C.TEXT, 0.35))
	draw_string(font, Vector2(chip.position.x, chip.position.y + chip.size.y * 0.5 + 10), chip_text, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 28, C.BG)

	# OPEN tag on the right, the line itself in between (shrunk to fit in either language).
	var tag := Loc.t("[ OPEN ]")
	var tag_w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	draw_string(font, Vector2(size.x - 18 - tag_w, size.y * 0.5 + 10), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var text := Loc.t("Shift report: how aware were you?")
	var room := size.x - chip.end.x - 16.0 - tag_w - 32.0
	var font_size := 32
	while font_size > 14 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		font_size -= 1
	draw_string(font, Vector2(chip.end.x + 18, size.y * 0.5 + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
