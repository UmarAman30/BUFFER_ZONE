extends Control
## The city map. A radar sweep rotates over it; an alert's blip only appears once the sweep passes
## over it. Districts light up with their worst open alert, brighten on hover (mouse or feed line),
## and Shift + click opens a district's file. Static thickens as public trust falls.

signal profile_requested(sector_id: String)
signal background_clicked
signal standby_pressed(unit: UnitState)

const C := preload("res://scripts/ui/ui_colors.gd")
const MapLayout := preload("res://scripts/ui/map_layout.gd")
const MAP_SHADER := preload("res://assets/shaders/map.gdshader")
const AmbientScript := preload("res://scripts/ui/ambient_lights.gd")
const StandbyChipScript := preload("res://scripts/ui/standby_chip.gd")
const SWEEP_PERIOD := 3.0
const DIM_COLOR := Color(0.5, 0.55, 0.58)
const HIGHLIGHT_COLOR := Color(0.55, 1.0, 0.9)

var hover_sector: String = ""      # district under the mouse
var feed_highlight: String = ""    # district of the feed line under the mouse

var _material: ShaderMaterial
var _view: TextureRect
var _pin_layer: Control
var _pins: Dictionary = {}          # alert id -> pin
var _districts: Dictionary = {}     # sector id -> {reveal, tint, outline, tag, focus}
var _sweep: float = -PI * 0.5       # start pointing up
var _unit_layer: Control
var _unit_icons: Dictionary = {}    # unit type -> texture
var _last_pin: Dictionary = {}      # unit id -> map-local position of the alert it was last sent to
var _chip_layer: Control
var _chips: Dictionary = {}         # unit id -> standby chip
var _casualty_pins: Dictionary = {} # casualty id -> marker
var _crater_layer: Control
var _crater_count := 0


func _ready() -> void:
	position = MapLayout.MAP_POS
	size = MapLayout.MAP_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var noise := FastNoiseLite.new()
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var clouds := NoiseTexture2D.new()
	clouds.width = 512
	clouds.height = 512
	clouds.seamless = true
	clouds.noise = noise
	_material = ShaderMaterial.new()
	_material.shader = MAP_SHADER
	_material.set_shader_parameter("water_mask", C.load_texture(MapLayout.WATER_MASK))
	_material.set_shader_parameter("cloud_noise", clouds)

	var art: Texture2D = C.load_texture(MapLayout.MAP_ART)
	if art == null:
		push_warning("CityScope: could not load %s" % MapLayout.MAP_ART)
	_view = TextureRect.new()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture = art
	_view.size = size
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.material = _material
	add_child(_view)

	# Full-brightness copy of each district; fades in over the dimmed map when the district is focused.
	for sector_id: String in MapLayout.sector_ids():
		var outline := MapLayout.polygon(sector_id)
		var reveal := Polygon2D.new()
		reveal.polygon = _scaled(outline)
		reveal.texture = art
		reveal.uv = outline
		reveal.material = _material
		reveal.modulate.a = 0.0
		add_child(reveal)
		_districts[sector_id] = {"reveal": reveal, "focus": 0.0}

	var ambient := AmbientScript.new()
	ambient.scale = Vector2(MapLayout.MAP_SCALE, MapLayout.MAP_SCALE)
	add_child(ambient)

	for sector_id: String in MapLayout.sector_ids():
		var scaled := _scaled(MapLayout.polygon(sector_id))
		var tint := Polygon2D.new()
		tint.polygon = scaled
		tint.color = Color(0, 0, 0, 0)
		add_child(tint)
		var line := Line2D.new()
		line.points = scaled
		line.closed = true
		line.width = 3.0
		line.default_color = Color(HIGHLIGHT_COLOR, 0.0)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.antialiased = true
		add_child(line)
		var tag := Label.new()
		tag.text = str(MapLayout.SECTOR_KEY[sector_id]).to_upper()
		tag.size = Vector2(320, 36)
		tag.position = MapLayout.label_position(sector_id) - tag.size * 0.5
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 24)
		tag.add_theme_color_override("font_color", Color(0.92, 1, 0.97))
		tag.add_theme_color_override("font_outline_color", C.BG)
		tag.add_theme_constant_override("outline_size", 8)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.modulate.a = 0.0
		add_child(tag)
		var entry: Dictionary = _districts[sector_id]
		entry["tint"] = tint
		entry["outline"] = line
		entry["tag"] = tag

	# Missile scorch marks (World.craters), under the alert pins.
	_crater_layer = Control.new()
	_crater_layer.size = size
	_crater_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crater_layer.draw.connect(_draw_craters)
	add_child(_crater_layer)

	_pin_layer = Control.new()
	_pin_layer.size = size
	_pin_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pin_layer)

	# Dispatched teams: their icon travels to the alert, sits beside it while working, and drives home.
	_unit_layer = Control.new()
	_unit_layer.size = size
	_unit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_unit_layer.draw.connect(_draw_units)
	add_child(_unit_layer)

	# Teams on standby: clickable glowing chips, above the alerts.
	_chip_layer = Control.new()
	_chip_layer.size = size
	_chip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip_layer)

	mouse_exited.connect(func() -> void: hover_sector = "")


func _scaled(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * MapLayout.MAP_SCALE)
	return result


# ---------------------------------------------------------------- pins

## Places an alert's pin at a random spot in its district. It stays hidden until the sweep reaches it.
func add_pin(pin: Control, alert: Alert) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = alert.id * 7919
	var best := MapLayout.random_point_in(alert.sector_id, rng)
	var best_gap := -1.0
	for attempt in 12:
		var candidate := MapLayout.random_point_in(alert.sector_id, rng)
		var gap := INF
		for other: Control in _pins.values():
			gap = minf(gap, candidate.distance_to(other.position + other.size * 0.5))
		if gap > best_gap:
			best_gap = gap
			best = candidate
		if gap > 80.0:
			break
	pin.position = best - pin.size * 0.5
	pin.visible = false
	_pin_layer.add_child(pin)
	_pins[alert.id] = pin


## Casualty markers are always visible (no sweep), placed away from other markers in their district.
func add_casualty_pin(pin: Control, casualty: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(casualty["id"]) * 104729
	var best := MapLayout.random_point_in(str(casualty["sector"]), rng)
	var best_gap := -1.0
	for attempt in 12:
		var candidate := MapLayout.random_point_in(str(casualty["sector"]), rng)
		var gap := INF
		for other: Control in _pins.values() + _casualty_pins.values():
			gap = minf(gap, candidate.distance_to(other.position + other.size * 0.5))
		if gap > best_gap:
			best_gap = gap
			best = candidate
		if gap > 90.0:
			break
	pin.position = best - pin.size * 0.5
	_pin_layer.add_child(pin)
	_casualty_pins[int(casualty["id"])] = pin


func remove_casualty_pin(casualty_id: int) -> void:
	if _casualty_pins.has(casualty_id):
		_casualty_pins[casualty_id].queue_free()
		_casualty_pins.erase(casualty_id)


func casualty_pin_center(casualty_id: int) -> Vector2:
	if _casualty_pins.has(casualty_id):
		var pin: Control = _casualty_pins[casualty_id]
		return position + pin.position + pin.size * 0.5
	return position + size * 0.5


## Screen rectangle of an alert's marker (empty until the sweep has revealed it). Used by the tutorial.
func alert_pin_rect(alert_id: int) -> Rect2:
	if _pins.has(alert_id) and _pins[alert_id].visible:
		var pin: Control = _pins[alert_id]
		return Rect2(position + pin.position, pin.size)
	return Rect2()


## Screen rectangle of the first standby tag on the map (empty if none).
func chip_rect() -> Rect2:
	for chip: Control in _chips.values():
		return Rect2(position + chip.position, chip.size)
	return Rect2()


func district_center(sector_id: String) -> Vector2:
	return position + MapLayout.label_position(sector_id)


func remove_pin(alert_id: int) -> void:
	if _pins.has(alert_id):
		_pins[alert_id].queue_free()
		_pins.erase(alert_id)


func clear_pins() -> void:
	for pin in _pins.values():
		pin.queue_free()
	_pins.clear()
	for pin in _casualty_pins.values():
		pin.queue_free()
	_casualty_pins.clear()


# ---------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	var previous := _sweep
	_sweep = fposmod(_sweep + TAU * delta / SWEEP_PERIOD, TAU)
	_reveal_swept_pins(fposmod(previous, TAU), _sweep)
	_unit_layer.queue_redraw()
	if not World.craters.is_empty() or _crater_count > 0:   # also clears old scorch marks on restart
		_crater_layer.queue_redraw()
	_crater_count = World.craters.size()
	_update_chips()

	var trust_loss := 1.0 - GameState.trust / GameState.MAX_TRUST
	_material.set_shader_parameter("sweep_angle", _sweep)
	_material.set_shader_parameter("static_amount", clampf(0.1 + pow(trust_loss, 1.3) * 0.9, 0.0, 1.0))

	var highlight := feed_highlight if feed_highlight != "" else hover_sector
	_view.modulate = _view.modulate.lerp(DIM_COLOR if highlight != "" else Color.WHITE, minf(1.0, delta * 10.0))

	var worst := {}
	for alert in World.alerts:
		if alert.assigned or not alert.revealed:
			continue
		worst[alert.sector_id] = maxi(int(worst.get(alert.sector_id, -1)), int(alert.phase))

	for sector_id: String in _districts:
		var entry: Dictionary = _districts[sector_id]
		var focus: float = move_toward(float(entry["focus"]), 1.0 if sector_id == highlight else 0.0, delta * 6.0)
		entry["focus"] = focus
		(entry["reveal"] as Polygon2D).modulate.a = focus
		(entry["tag"] as Label).modulate.a = focus
		var tint := entry["tint"] as Polygon2D
		var line := entry["outline"] as Line2D
		if worst.has(sector_id):
			var phase: int = worst[sector_id]
			var color := C.phase_color(phase)
			var pulse := 1.0
			if phase == Alert.Phase.RED:
				pulse = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 150.0))
			tint.color = Color(color, 0.14 * pulse)
			line.default_color = Color(color, 0.9 * pulse)
			line.width = 4.0 + focus * 2.0
		else:
			tint.color = Color(HIGHLIGHT_COLOR, 0.07 * focus)
			line.default_color = Color(HIGHLIGHT_COLOR, focus)
			line.width = 3.0


func _unit_texture(unit_type: String) -> Texture2D:
	if not _unit_icons.has(unit_type):
		_unit_icons[unit_type] = C.load_texture("res://assets/images/team_icons/%s.png" % unit_type)
	return _unit_icons[unit_type]


## Map-local anchor for a sector on a unit's leg: the alert's pin if the leg ends/starts there.
func _anchor(unit: UnitState, sector_id: String) -> Vector2:
	if unit.alert != null and unit.alert.sector_id == sector_id and _pins.has(unit.alert.id):
		var pin: Control = _pins[unit.alert.id]
		var at := pin.position + pin.size * 0.5
		_last_pin[unit.id] = {"sector": sector_id, "at": at}
		return at
	if unit.rescue_id != 0 and unit.leg_to == sector_id and _casualty_pins.has(unit.rescue_id):
		var rescue_pin: Control = _casualty_pins[unit.rescue_id]
		var rescue_at := rescue_pin.position + rescue_pin.size * 0.5
		_last_pin[unit.id] = {"sector": sector_id, "at": rescue_at}
		return rescue_at
	var last: Dictionary = _last_pin.get(unit.id, {})
	if not last.is_empty() and last["sector"] == sector_id:
		return last["at"]
	return MapLayout.label_position(sector_id)


## Keeps one chip per standby unit, placed at the spot it finished its job (stacked if several).
func _update_chips() -> void:
	var per_sector: Dictionary = {}
	for unit in World.units:
		var standing := unit.status == UnitState.Status.STANDBY
		if not standing:
			if _chips.has(unit.id):
				_chips[unit.id].queue_free()
				_chips.erase(unit.id)
			continue
		var chip: Control = _chips.get(unit.id)
		if chip == null:
			chip = StandbyChipScript.new()
			chip.setup(unit)
			chip.pressed.connect(func() -> void: standby_pressed.emit(unit))
			_chip_layer.add_child(chip)
			_chips[unit.id] = chip
		var index: int = per_sector.get(unit.location, 0)
		per_sector[unit.location] = index + 1
		var at := _anchor(unit, unit.location) + Vector2(-chip.size.x * 0.5, 52.0 + index * 50.0)
		at.x = clampf(at.x, 4.0, size.x - chip.size.x - 4.0)
		at.y = clampf(at.y, 26.0, size.y - chip.size.y - 4.0)
		chip.position = at


## Selection highlight and ETA preview on the standby chips.
func set_chip_selection(selected_unit: UnitState, preview_alert: Alert) -> void:
	for unit_id: String in _chips:
		var chip: Control = _chips[unit_id]
		chip.selected = chip.unit == selected_unit
		chip.preview_alert = preview_alert


func clear_chips() -> void:
	for chip in _chips.values():
		chip.queue_free()
	_chips.clear()
	_last_pin.clear()


func _draw_craters() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var seen: Dictionary = {}
	for sector_id in World.craters:
		if seen.has(sector_id):
			continue
		seen[sector_id] = true
		var at := MapLayout.label_position(sector_id) + Vector2(-70, 46)
		var offset := float(sector_id.unicode_at(0))
		_crater_layer.draw_circle(at, 46.0, Color(0, 0, 0, 0.35))
		_crater_layer.draw_circle(at, 32.0, Color(0.08, 0.03, 0.02, 0.75))
		for k in 7:   # cracks
			var angle := offset + k * TAU / 7.0
			var reach := 40.0 + 14.0 * sin(offset * 3.0 + k)
			_crater_layer.draw_line(at + Vector2(cos(angle), sin(angle)) * 26.0, at + Vector2(cos(angle + 0.15), sin(angle + 0.15)) * reach, Color(0.05, 0.02, 0.02, 0.8), 3.0)
		var glow := 0.55 + 0.45 * sin(now * 3.0 + offset)
		_crater_layer.draw_arc(at, 22.0, 0.0, TAU, 28, Color(1.0, 0.45, 0.1, 0.55 * glow), 4.0)
		for k in 5:   # embers
			var angle := offset * 1.7 + k * 1.3
			var ember := at + Vector2(cos(angle), sin(angle)) * (8.0 + 10.0 * fmod(k * 0.37 + offset, 1.0))
			_crater_layer.draw_circle(ember, 3.0, Color(1.0, 0.6 + 0.3 * sin(now * 5.0 + k), 0.2, glow))


func _draw_units() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for unit in World.units:
		if unit.status == UnitState.Status.IDLE or unit.status == UnitState.Status.RETURNING:
			_last_pin.erase(unit.id)
			continue
		if unit.status == UnitState.Status.STANDBY:
			continue
		var accent: Color = C.TEAM_COLORS.get(unit.type, C.TEXT)
		var at := Vector2.ZERO
		var target := Vector2.INF
		match unit.status:
			UnitState.Status.WORKING, UnitState.Status.STRANDED:
				at = _anchor(unit, unit.location) + Vector2(30, -30)
			_:
				if unit.leg_time <= 0.0:
					continue
				var elapsed := unit.status_total - unit.timer
				if elapsed > unit.leg_time:
					continue   # back at base, cooling down
				var progress := unit.leg_t0 + (1.0 - unit.leg_t0) * clampf(elapsed / unit.leg_time, 0.0, 1.0)
				var from := _anchor(unit, unit.leg_from)
				target = _anchor(unit, unit.leg_to)
				at = from.lerp(target, progress)
		if target != Vector2.INF:
			# Faint dashed line to where the team is heading.
			var length := at.distance_to(target)
			var step := 14.0
			var dir := (target - at) / maxf(length, 0.001)
			var d := 18.0
			while d < length - 8.0:
				_unit_layer.draw_line(at + dir * d, at + dir * minf(d + 7.0, length), Color(accent, 0.45), 2.0)
				d += step
		var ring := accent
		if unit.status == UnitState.Status.STRANDED:
			ring = C.RED if fmod(now, 0.5) < 0.25 else Color(C.RED, 0.4)
		_unit_layer.draw_circle(at, 17.0, Color(C.BG, 0.9))
		_unit_layer.draw_arc(at, 17.0, 0.0, TAU, 32, ring, 3.0)
		var texture := _unit_texture(unit.type)
		if texture != null:
			_unit_layer.draw_texture_rect(texture, Rect2(at - Vector2(12, 12), Vector2(24, 24)), false)
		if unit.status == UnitState.Status.STRANDED:
			_unit_layer.draw_string(get_theme_default_font(), at + Vector2(14, -10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C.RED)


func _reveal_swept_pins(from_angle: float, to_angle: float) -> void:
	for alert_id: int in _pins:
		var pin: Control = _pins[alert_id]
		if pin.visible:
			continue
		var offset := pin.position + pin.size * 0.5 - size * 0.5
		var angle := fposmod(atan2(offset.y, offset.x), TAU)
		var swept := (angle >= from_angle and angle < to_angle) if to_angle >= from_angle \
				else (angle >= from_angle or angle < to_angle)
		if swept:
			pin.visible = true
			pin.alert.revealed = true
			EventBus.alert_revealed.emit(pin.alert)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover_sector = MapLayout.district_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var sector_id := MapLayout.district_at(mouse.position)
		if mouse.shift_pressed and sector_id != "":
			profile_requested.emit(sector_id)
		else:
			background_clicked.emit()
		accept_event()
