extends Control
## A team that has finished a job and is waiting on the map. Drawn as a glowing rectangle with the
## team icon and callsign; the bar underneath runs down the standby time (after which the team goes
## back to the team bar). Click it then an alert (or drag it onto an alert) to redeploy it from here.

signal pressed

const C := preload("res://scripts/ui/ui_colors.gd")
const CHIP_SIZE := Vector2(112, 40)

var unit: UnitState
var selected: bool = false
var preview_alert: Alert = null

var _icon: Texture2D
var _hovered: bool = false


func setup(p_unit: UnitState) -> void:
	unit = p_unit
	custom_minimum_size = CHIP_SIZE
	size = CHIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon = C.load_texture("res://assets/images/team_icons/%s.png" % unit.type)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if unit.status != UnitState.Status.STANDBY:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % unit.callsign
	preview.add_theme_font_size_override("font_size", 24)
	preview.add_theme_color_override("font_color", C.TEAM_COLORS.get(unit.type, C.TEXT))
	preview.add_theme_stylebox_override("normal", C.box(C.PANEL, C.TEAM_COLORS.get(unit.type, C.TEXT), 3))
	set_drag_preview(preview)
	return {"unit_id": unit.id}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var accent: Color = C.TEAM_COLORS.get(unit.type, C.TEXT)
	var rect := Rect2(Vector2.ZERO, size)
	# Glow: soft pulse so it reads as "available"; stronger when hovered / selected.
	var pulse := 0.5 + 0.5 * sin(now * 4.0)
	var strength := 1.0 if selected else (0.75 if _hovered else 0.35 + 0.25 * pulse)
	for i in 4:
		var grow := 2.0 + i * 3.5
		draw_rect(rect.grow(grow), Color(accent, strength * (0.35 - i * 0.08)), false, 3.0)
	draw_rect(rect, Color(C.BG, 0.92))
	draw_rect(rect, C.WHITE if selected else accent, false, 2.0)
	if _icon != null:
		draw_texture_rect(_icon, Rect2(Vector2(6, 6), Vector2(24, 24)), false)
	var font := get_theme_default_font()
	draw_string(font, Vector2(36, 24), unit.callsign, HORIZONTAL_ALIGNMENT_LEFT, size.x - 40, 20, C.WHITE if selected else accent)
	# Standby time left.
	var fraction := clampf(unit.timer / maxf(unit.status_total, 0.01), 0.0, 1.0)
	draw_rect(Rect2(Vector2(4, size.y - 7), Vector2((size.x - 8) * fraction, 3)), accent)
	# With an alert selected, show how long this team would take from here.
	if preview_alert != null and World.alert_open_for(preview_alert, unit.type):
		var eta := World.eta_for(unit, preview_alert)
		var late := eta >= preview_alert.time_left
		var text := Loc.t("ETA %.1fs%s") % [eta, Loc.t(" LATE") if late else ""]
		draw_rect(Rect2(Vector2(0, -24), Vector2(size.x, 22)), Color(C.BG, 0.9))
		draw_string(font, Vector2(4, -7), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 18, C.RED if late else C.WHITE)
