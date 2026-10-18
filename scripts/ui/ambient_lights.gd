extends Node2D
## Animated lights drawn over the map: radio-tower beacon, lighthouse beam, harbour lights, the
## downtown tower pulse. Positions come from res://data/config/landmarks.json (map pixels); the parent
## scales this node to the displayed map size.

var data: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/config/landmarks.json"))
	if parsed is Dictionary:
		data = parsed
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _point(key: String) -> Vector2:
	var p: Variant = data.get(key, null)
	return Vector2(p[0], p[1]) if p != null else Vector2(-999, -999)


func _glow(p: Vector2, color: Color, radius: float, alpha: float) -> void:
	for i in 4:
		draw_circle(p, radius * (1.0 + i * 1.4), Color(color, alpha / (1.0 + i * 2.2)))


func _draw() -> void:
	if data.is_empty():
		return
	var blink := fmod(_t, 1.2) < 0.18
	_glow(_point("radio_tower"), Color(1, 0.15, 0.1), 3.0, 0.9 if blink else 0.08)
	_glow(_point("central_tower"), Color(0.75, 1, 0.95), 4.0, 0.35 + 0.3 * sin(_t * 1.6))
	_glow(_point("mansion"), Color(0.5, 0.95, 1), 2.5, 0.25 + 0.15 * sin(_t * 3.0))
	_glow(_point("market"), Color(1, 0.7, 0.35), 5.0, 0.25 + 0.08 * sin(_t * 9.0) + 0.05 * sin(_t * 23.0))
	var lighthouse := _point("lighthouse")
	var angle := _t * 0.9
	for i in 3:
		var spread := 0.16 * (1.0 - i * 0.3)
		var p1 := lighthouse + Vector2(cos(angle - spread), sin(angle - spread)) * 300.0
		var p2 := lighthouse + Vector2(cos(angle + spread), sin(angle + spread)) * 300.0
		draw_polygon(PackedVector2Array([lighthouse, p1, p2]),
			PackedColorArray([Color(1, 0.95, 0.75, 0.22), Color(1, 0.95, 0.75, 0.0), Color(1, 0.95, 0.75, 0.0)]))
	_glow(lighthouse, Color(1, 0.95, 0.75), 3.0, 0.8)
	var harbour: Array = data.get("harbour", [])
	for i in harbour.size():
		var lamp := Vector2(harbour[i][0], harbour[i][1])
		var on := fmod(_t + i * 0.37, 2.0) < 1.0
		var color := Color(0.2, 1, 0.4) if (i % 2 == 0) else Color(1, 0.25, 0.2)
		_glow(lamp, color, 2.2, 0.75 if on else 0.12)
