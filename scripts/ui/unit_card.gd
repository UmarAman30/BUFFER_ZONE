extends Button
## Character card for one response unit, in the unit bar under the map: portrait, callsign, team and
## status. Only idle units can be picked or dragged. While an alert is selected, idle cards show their
## ETA to it (red LATE = cannot beat the clock).

signal drag_state(unit: UnitState, active: bool)

const C := preload("res://scripts/ui/ui_colors.gd")
const STATES := ["normal", "hover", "pressed", "disabled", "focus"]
const ICON_DIR := "res://assets/images/team_icons/"
const PORTRAIT_DIR := "res://assets/images/portraits/"
const CARD_SIZE := Vector2(250, 104)
const TEXT_X := 96.0

var unit: UnitState
var selected: bool = false
var preview_alert: Alert = null

var _style: StyleBoxFlat
var _portrait: TextureRect
var _name_label: Label
var _role_label: Label
var _status_label: Label
var _extra_label: Label
var _last_color := Color(0, 0, 0, 0)
var _dragging: bool = false


func setup(p_unit: UnitState) -> void:
	unit = p_unit
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	focus_mode = Control.FOCUS_NONE
	_style = C.box(C.PANEL, C.DIM, 3)
	for state: String in STATES:
		add_theme_stylebox_override(state, _style)

	_portrait = TextureRect.new()
	_portrait.texture = C.load_texture("%sunit_%s.png" % [PORTRAIT_DIR, unit.id])
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2(8, 12)
	_portrait.size = Vector2(80, 80)
	add_child(_portrait)

	_add_icon()
	_name_label = _make_label(Vector2(TEXT_X, 6), 22, 126)
	_role_label = _make_label(Vector2(TEXT_X, 32), 13, 148)
	_status_label = _make_label(Vector2(TEXT_X, 52), 15, 148)
	_extra_label = _make_label(Vector2(TEXT_X, 74), 14, 148)
	_refresh()


func _make_label(at: Vector2, font_size: int, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, font_size + 8)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


## Small team-type icon in the top-right corner of the card (skipped if the art is missing).
func _add_icon() -> void:
	var texture := C.load_texture("%s%s.png" % [ICON_DIR, unit.type])
	if texture == null:
		return
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = Vector2(22, 22)
	art.position = Vector2(CARD_SIZE.x - 28, 4)
	add_child(art)


func _process(_delta: float) -> void:
	_refresh()


## Drag an idle card onto an alert blip to dispatch.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if unit.status != UnitState.Status.IDLE:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % unit.callsign
	preview.add_theme_font_size_override("font_size", 24)
	preview.add_theme_color_override("font_color", C.YELLOW)
	preview.add_theme_stylebox_override("normal", C.box(C.PANEL, C.YELLOW, 3))
	set_drag_preview(preview)
	_dragging = true
	drag_state.emit(unit, true)
	return unit


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		drag_state.emit(unit, false)


func _refresh() -> void:
	var type_name: String = GameData.unit_types[unit.type]["name"]
	var color := C.YELLOW
	match unit.status:
		UnitState.Status.IDLE:
			color = C.GREEN
		UnitState.Status.STRANDED:
			color = C.RED

	var status_text := "%s  %d s" % [unit.status_name(), ceili(unit.timer)]
	var extra := ""
	if unit.status == UnitState.Status.IDLE:
		status_text = Loc.t("READY @ %s") % unit.location
		if preview_alert != null and not preview_alert.assigned:
			var eta := World.eta_for(unit, preview_alert)
			var late := eta >= preview_alert.time_left
			extra = Loc.t("ETA %.1f s%s") % [eta, Loc.t("  LATE") if late else ""]
			if late:
				color = C.RED
	elif unit.alert != null:
		extra = "-> %s  #%d" % [unit.alert.sector_id, unit.alert.id]

	_name_label.text = unit.callsign
	_role_label.text = Loc.upper(type_name)
	_status_label.text = status_text
	_extra_label.text = extra
	disabled = unit.status != UnitState.Status.IDLE
	_style.border_color = C.WHITE if selected else color
	_style.bg_color = C.PANEL.lerp(color, 0.15)
	_portrait.modulate = Color.WHITE if unit.status == UnitState.Status.IDLE else Color(0.55, 0.55, 0.55)
	if color != _last_color:
		_last_color = color
		for label: Label in [_name_label, _status_label, _extra_label]:
			label.add_theme_color_override("font_color", color)
		_role_label.add_theme_color_override("font_color", C.TEXT)
