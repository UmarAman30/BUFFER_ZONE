extends Control
## Map marker for one alert: a warning triangle. Says nothing about what is happening: the alert
## number, pulsing triangles, and a countdown that runs around the outer triangle. When the radar
## sweep first reveals it, it bursts outwards. Click it to select it, or drop a team on it.

signal pressed

const C := preload("res://scripts/ui/ui_colors.gd")
const PIN_SIZE := 84.0
const BURST_SECONDS := 1.1
const CORE := 30.0      # inner triangle "radius"
const RING := 40.0      # countdown triangle

var alert: Alert
var selected: bool = false
var drops_enabled: bool = true   # the tutorial can forbid dropping a team card on the alert

var _revealed_at: float = -100.0


func setup(p_alert: Alert) -> void:
	alert = p_alert
	custom_minimum_size = Vector2(PIN_SIZE, PIN_SIZE)
	size = Vector2(PIN_SIZE, PIN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_revealed_at = Time.get_ticks_msec() / 1000.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.shift_pressed:
			pressed.emit()
			accept_event()


func _process(_delta: float) -> void:
	queue_redraw()


## Corners of an upward triangle around the marker centre (slightly lowered so it looks centred).
static func triangle(center: Vector2, radius: float) -> PackedVector2Array:
	var c := center + Vector2(0, radius * 0.18)
	var points := PackedVector2Array()
	for k in 3:
		var angle := -PI * 0.5 + k * TAU / 3.0
		points.append(c + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


## The first `fraction` of the triangle's outline, starting at the top corner, clockwise.
func _partial(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	var remaining := fraction * 3.0
	for k in 3:
		var a := points[k]
		var b := points[(k + 1) % 3]
		if remaining >= 1.0:
			out.append(b)
			remaining -= 1.0
		else:
			if remaining > 0.0:
				out.append(a.lerp(b, remaining))
			break
	return out


func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var center := size * 0.5
	var color := C.phase_color(alert.phase)
	var responder := World.responder_for(alert) if alert.assigned else null
	var en_route := responder != null and responder.status == UnitState.Status.TRAVELING
	var settled := alert.assigned and not en_route   # unit is on site, clock stopped
	if settled:
		color = C.DIM.lightened(0.5)
	var font := get_theme_default_font()

	# Reveal burst: a flash and two expanding triangles.
	var age := now - _revealed_at
	if age < BURST_SECONDS:
		var t := age / BURST_SECONDS
		draw_colored_polygon(triangle(center, CORE + 6.0), Color(color, maxf(0.0, 0.45 - t * 1.2)))
		for k in 2:
			var tk := clampf(t - k * 0.18, 0.0, 1.0)
			if tk > 0.0:
				var radius := CORE + 160.0 * (1.0 - pow(1.0 - tk, 3.0))
				draw_polyline(_closed(triangle(center, radius)), Color(color, (1.0 - tk) * 0.9), 3.0 - k)

	# Idle pulse: triangles drifting outwards, faster when red.
	if not alert.assigned:
		var speed := 1.4 if alert.phase == Alert.Phase.RED else 0.6
		for k in 2:
			var p := fmod(now * speed + k * 0.5, 1.0)
			draw_polyline(_closed(triangle(center, CORE + 4.0 + 30.0 * p)), Color(color, (1.0 - p) * 0.45), 2.0)

	# Countdown: the outer triangle drains as the clock runs down.
	var outer := triangle(center, RING)
	draw_polyline(_closed(outer), Color(C.DIM.lightened(0.2), 0.9), 2.0)
	var fraction := clampf(alert.time_left / float(GameData.balance["green_start"]), 0.0, 1.0)
	if fraction > 0.0 and not settled:
		draw_polyline(_partial(outer, fraction), color, 5.0)

	# Core warning triangle with a pixel "!".
	var core := triangle(center, CORE)
	draw_colored_polygon(core, Color(C.BG, 0.92))
	draw_colored_polygon(core, Color(color, 0.28))
	if alert.phase == Alert.Phase.RED and not alert.assigned and fmod(now, 0.5) < 0.25:
		draw_colored_polygon(core, Color(color, 0.35))
	draw_polyline(_closed(core), color, 3.0)
	var mark := center + Vector2(0, 6)
	draw_rect(Rect2(mark + Vector2(-2.5, -13), Vector2(5, 13)), color.lightened(0.3))
	draw_rect(Rect2(mark + Vector2(-2.5, 3), Vector2(5, 5)), color.lightened(0.3))

	# Alert number tag, lower right.
	var tag := "#%d" % alert.id
	var tag_pos := center + Vector2(22, 18)
	var tag_size := Vector2(12 + 12 * tag.length(), 26)
	draw_rect(Rect2(tag_pos, tag_size), Color(C.BG, 0.9))
	draw_rect(Rect2(tag_pos, tag_size), color, false, 1.0)
	draw_string(font, tag_pos + Vector2(6, 20), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color.lightened(0.2))

	if en_route:
		draw_string(font, Vector2(-30, size.y + 18.0), Loc.t("EN ROUTE"), HORIZONTAL_ALIGNMENT_CENTER, size.x + 60.0, 24, C.TEXT)
	elif settled:
		draw_string(font, Vector2(-30, size.y + 18.0), Loc.t("ON SITE"), HORIZONTAL_ALIGNMENT_CENTER, size.x + 60.0, 24, C.TEXT)

	# Selection reticle: four rotating corner brackets.
	if selected:
		var spin := now * 1.5
		for i in 4:
			var a := spin + i * PI * 0.5
			var corner := center + Vector2(cos(a), sin(a)) * 52.0
			var along := Vector2(cos(a + PI * 0.75), sin(a + PI * 0.75)) * 12.0
			var across := Vector2(cos(a - PI * 0.75), sin(a - PI * 0.75)) * 12.0
			draw_polyline(PackedVector2Array([corner + along, corner, corner + across]), C.WHITE, 3.0)


## Drop a team stack (sends its nearest ready unit) or a standby chip (sends that unit) on this pin.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var unit := _unit_from(data)
	return drops_enabled and unit != null and World.alert_open_for(alert, unit.type)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var unit := _unit_from(data)
	if unit != null:
		World.dispatch(unit.id, alert.id)


func _unit_from(data: Variant) -> UnitState:
	if not (data is Dictionary):
		return null
	var info := data as Dictionary
	if info.has("unit_type"):
		return World.best_unit_of_type(str(info["unit_type"]), alert)
	if info.has("unit_id"):
		var unit := World.get_unit(str(info["unit_id"]))
		if unit != null and World.can_dispatch(unit):
			return unit
	return null
