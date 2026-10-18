extends Control
## Console-style frame drawn over a panel: a thin outer line, an inner bevel (lit top-left, shaded
## bottom-right) and bright corner brackets. Ignores the mouse and follows the parent's size.

const BRACKET := 16.0
const THICK := 3.0

var accent: Color = Color(0.55, 1.0, 0.65):
	set(value):
		if value != accent:
			accent = value
			queue_redraw()

## 0..1: soft outer glow in the accent colour (used for hover / selection).
var glow: float = 0.0:
	set(value):
		if not is_equal_approx(value, glow):
			glow = value
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	if glow > 0.0:
		for i in 4:
			var grow := 3.0 + i * 4.0
			draw_rect(Rect2(Vector2(-grow, -grow), Vector2(w + grow * 2.0, h + grow * 2.0)), Color(accent, glow * (0.32 - i * 0.07)), false, 4.0)
	var line := Color(accent, 0.35)
	draw_rect(Rect2(Vector2(0.5, 0.5), Vector2(w - 1.0, h - 1.0)), line, false, 1.0)
	# Bevel, inset 4 px.
	var light := Color(accent.lightened(0.3), 0.22)
	var shade := Color(0, 0, 0, 0.45)
	draw_line(Vector2(4, 4), Vector2(w - 4, 4), light, 1.0)
	draw_line(Vector2(4, 4), Vector2(4, h - 4), light, 1.0)
	draw_line(Vector2(4, h - 4), Vector2(w - 4, h - 4), shade, 1.0)
	draw_line(Vector2(w - 4, 4), Vector2(w - 4, h - 4), shade, 1.0)
	# Corner brackets.
	var b := minf(BRACKET, minf(w, h) * 0.3)
	for corner: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		draw_rect(Rect2(corner + Vector2(0.0 if sx > 0 else -b, 0.0 if sy > 0 else -THICK), Vector2(b, THICK)), accent)
		draw_rect(Rect2(corner + Vector2(0.0 if sx > 0 else -THICK, 0.0 if sy > 0 else -b), Vector2(THICK, b)), accent)
