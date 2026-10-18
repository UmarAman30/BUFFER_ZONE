extends Control
## Map marker for a stranded third-party team: an amber HEXAGON with the team's badge and a countdown
## that runs around its edge. Click it, then a team (or the other way round) to send help. Using the wrong
## team pops a small notice out of the hexagon (show_notice).

signal pressed

const C := preload("res://scripts/ui/ui_colors.gd")
const PIN_SIZE := 84.0
const AMBER := Color(1.0, 0.68, 0.15)
const NOTICE_SECONDS := 1.6

var rescue: Dictionary = {}
var selected: bool = false
var _born: float = 0.0
var _badge: Texture2D
var _notice: String = ""
var _notice_at: float = -100.0


func setup(p_rescue: Dictionary) -> void:
	rescue = p_rescue
	custom_minimum_size = Vector2(PIN_SIZE, PIN_SIZE)
	size = Vector2(PIN_SIZE, PIN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_born = Time.get_ticks_msec() / 1000.0
	_badge = C.load_texture("res://assets/images/team_icons/%s.png" % str(rescue["reserve"]["type"]))


## A short message that pops out of the hexagon and fades (e.g. "HEAVY ONLY").
func show_notice(text: String) -> void:
	_notice = text
	_notice_at = Time.get_ticks_msec() / 1000.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.shift_pressed:
			pressed.emit()
			accept_event()


func _process(_delta: float) -> void:
	queue_redraw()


## Pointy-top hexagon outline (closed), `radius` from the centre to a corner.
static func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 7:
		var angle := -PI * 0.5 + k * PI / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## The part of the hexagon outline that is left, starting at the top and running clockwise.
static func _hex_progress(center: Vector2, radius: float, fraction: float) -> PackedVector2Array:
	var corners := _hex_points(center, radius)
	var out := PackedVector2Array([corners[0]])
	var remaining := clampf(fraction, 0.0, 1.0) * 6.0
	for k in 6:
		if remaining <= 0.0:
			break
		var step := minf(1.0, remaining)
		out.append(corners[k].lerp(corners[k + 1], step))
		remaining -= 1.0
	return out


func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var center := size * 0.5
	var age := now - _born
	if age < 1.0:
		draw_polyline(_hex_points(center, 34.0 + 140.0 * age), Color(AMBER, 1.0 - age), 3.0)
	# Fast distress pulse.
	for k in 2:
		var p := fmod(now * 1.4 + k * 0.5, 1.0)
		draw_polyline(_hex_points(center, 34.0 + 24.0 * p), Color(AMBER, (1.0 - p) * 0.6), 2.0)

	var body := _hex_points(center, 33.0)
	body.remove_at(body.size() - 1)
	draw_colored_polygon(body, Color(0.2, 0.12, 0.02, 0.95))
	draw_colored_polygon(body, Color(AMBER, 0.3))
	var fraction := clampf(float(rescue.get("time_left", 0.0)) / maxf(float(rescue.get("total", 1.0)), 0.01), 0.0, 1.0)
	draw_polyline(_hex_points(center, 39.0), Color(C.DIM, 0.8), 2.0)
	if fraction > 0.0:
		draw_polyline(_hex_progress(center, 39.0, fraction), AMBER if fraction > 0.3 else C.RED, 5.0)

	if _badge != null:
		draw_texture_rect(_badge, Rect2(center - Vector2(18, 18), Vector2(36, 36)), false)
	# SOS badge.
	var badge := center + Vector2(26, -26)
	draw_circle(badge, 11.0, AMBER)
	draw_string(get_theme_default_font(), badge + Vector2(-8, 5), "SOS", HORIZONTAL_ALIGNMENT_LEFT, 20, 12, C.BG)

	if selected:
		draw_polyline(_hex_points(center, 48.0), C.WHITE, 3.0)

	# Popping notice: rises out of the hexagon and fades.
	var notice_age := now - _notice_at
	if notice_age >= 0.0 and notice_age < NOTICE_SECONDS:
		var t := notice_age / NOTICE_SECONDS
		var pop := minf(1.0, notice_age / 0.15)                       # quick pop-in
		var alpha := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)         # fades over the last 40%
		var font := get_theme_default_font()
		var text_size := font.get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var box := Rect2(Vector2(center.x - (text_size.x + 24.0) * 0.5 * pop, center.y - 58.0 - 34.0 * t - 18.0 * pop),
				Vector2((text_size.x + 24.0) * pop, 36.0 * pop))
		draw_rect(box, Color(C.BG, 0.95 * alpha))
		draw_rect(box, Color(AMBER, alpha), false, 3.0)
		if pop > 0.9:
			draw_string(font, box.position + Vector2(12, 27), _notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(C.WHITE, alpha))
