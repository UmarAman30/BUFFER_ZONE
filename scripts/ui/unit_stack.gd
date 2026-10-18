extends Button
## One team type in the dispatch bar (e.g. EARTHQUAKE TEAM x3). Picking the stack and an alert sends
## the stack's nearest idle unit. Shows fanned portraits, how many are ready, and per member a status lamp,
## callsign and a progress bar for the current trip / job / cooldown.
## While an alert is selected, the header shows the best ETA (red LATE = nobody can beat the clock).

signal drag_state(unit_type: String, active: bool)

const C := preload("res://scripts/ui/ui_colors.gd")
const STATES := ["normal", "hover", "pressed", "disabled", "focus"]
const ICON_DIR := "res://assets/images/team_icons/"
const PORTRAIT_DIR := "res://assets/images/portraits/"
const STACK_SIZE := Vector2(600, 108)
const TEXT_X := 150.0
const TEAM_COLORS := C.TEAM_COLORS

var unit_type: String = ""
var members: Array[UnitState] = []
var selected: bool = false
var preview_alert: Alert = null
var preview_sector: String = ""      # sector of a picked third-party rescue (ETA preview)
var preview_rescue: Dictionary = {}

var _style: StyleBoxFlat
var _accent: Color
var _portraits: Array[TextureRect] = []
var _title: Label
var _ready_label: Label
var _member_view: Control
var _best: UnitState = null
var _home_y: float = NAN
var _flash: float = 0.0
var _dragging: bool = false
var _frame: Control
var _hovered: bool = false
var hotkey: String = ""   # keyboard shortcut shown on the stack (set by the map screen)
var _type_name: String = ""


func setup(p_type: String, p_members: Array[UnitState]) -> void:
	unit_type = p_type
	members = p_members
	_accent = TEAM_COLORS.get(unit_type, C.TEXT)
	_type_name = Loc.upper(str(GameData.unit_types[unit_type]["name"]))
	Loc.language_changed.connect(_on_language_changed)
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	custom_minimum_size = STACK_SIZE
	size = STACK_SIZE
	focus_mode = Control.FOCUS_NONE
	_style = C.box(C.PANEL, C.DIM, 1)
	for state: String in STATES:
		add_theme_stylebox_override(state, _style)

	# Accent strip down the left edge in the team colour.
	var strip := ColorRect.new()
	strip.color = _accent
	strip.position = Vector2(3, 3)
	strip.size = Vector2(6, STACK_SIZE.y - 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	# Portraits fanned left to right, the first one on top.
	for i in range(members.size() - 1, -1, -1):
		var portrait := TextureRect.new()
		portrait.texture = C.load_texture("%sunit_%s.png" % [PORTRAIT_DIR, members[i].id])
		if portrait.texture == null:   # rescued teams share a sibling's portrait
			portrait.texture = C.load_texture("%sunit_%s.png" % [PORTRAIT_DIR, _portrait_fallback(members[i])])
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_SCALE
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.position = Vector2(18 + i * (22 if members.size() <= 3 else 16), 14)
		portrait.size = Vector2(80, 80)
		add_child(portrait)
		_portraits.push_front(portrait)

	var type_icon := TextureRect.new()
	type_icon.texture = C.load_texture("%s%s.png" % [ICON_DIR, unit_type])
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_SCALE
	type_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_icon.position = Vector2(TEXT_X, 8)
	type_icon.size = Vector2(26, 26)
	add_child(type_icon)

	_title = _make_label(Vector2(TEXT_X + 34, 4), 22, 300)
	_title.text = "%s  x%d" % [Loc.upper(str(GameData.unit_types[unit_type]["name"])), members.size()]
	_title.add_theme_color_override("font_color", _accent)
	_ready_label = _make_label(Vector2(STACK_SIZE.x - 210, 8), 18, 196)
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_member_view = Control.new()
	_member_view.position = Vector2(TEXT_X, 40)
	_member_view.size = Vector2(STACK_SIZE.x - TEXT_X - 12, 64)
	_member_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_member_view.draw.connect(_draw_members)
	add_child(_member_view)
	_frame = C.add_frame(self, _accent)
	EventBus.unit_dispatched.connect(func(unit: UnitState, _alert: Alert) -> void:
		if unit in members:
			_flash = 1.0)
	_refresh()


func _portrait_fallback(unit: UnitState) -> String:
	for other in members:
		var path := "%sunit_%s.png" % [PORTRAIT_DIR, other.id]
		if other != unit and (ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))):
			return other.id
	return members[0].id


func _make_label(at: Vector2, font_size: int, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, font_size * 1.6 + 6.0)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label


func idle_count() -> int:
	var count := 0
	for unit in members:
		if unit.status == UnitState.Status.IDLE:
			count += 1
	return count


func _process(delta: float) -> void:
	# Hovered stack rises a little; the picked one lifts clearly out of the row and glows.
	if is_nan(_home_y):
		_home_y = position.y
	var lift := 20.0 if selected else (8.0 if _hovered and idle_count() > 0 else 0.0)
	position.y = lerpf(position.y, _home_y - lift, minf(1.0, delta * 14.0))
	_flash = maxf(0.0, _flash - delta * 2.5)
	modulate = Color.WHITE.lerp(Color(1.8, 1.8, 1.8), _flash)
	_refresh()


## Drag the stack onto an alert blip to send its nearest idle unit.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if idle_count() == 0:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % Loc.upper(str(GameData.unit_types[unit_type]["name"]))
	preview.add_theme_font_size_override("font_size", 24)
	preview.add_theme_color_override("font_color", _accent)
	preview.add_theme_stylebox_override("normal", C.box(C.PANEL, _accent, 3))
	set_drag_preview(preview)
	_dragging = true
	drag_state.emit(unit_type, true)
	return {"unit_type": unit_type}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		drag_state.emit(unit_type, false)


func _on_language_changed(_lang: String) -> void:
	_type_name = Loc.upper(str(GameData.unit_types[unit_type]["name"]))
	_refresh()


func _refresh() -> void:
	var ready_count := idle_count()
	var late := false
	# The headline count is how many of this team are ready in the bar right now.
	_title.text = ("[%s] " % hotkey if hotkey != "" else "") + "%s x%d" % [_type_name, ready_count]
	_ready_label.text = Loc.t("READY %d/%d") % [ready_count, members.size()]
	_ready_label.add_theme_color_override("font_color", C.TEXT if ready_count > 0 else C.RED)

	_best = null
	if preview_alert != null and World.alert_open_for(preview_alert, unit_type):
		_best = World.best_unit_of_type(unit_type, preview_alert)
		if _best != null:
			var eta := World.eta_for(_best, preview_alert)
			late = eta >= preview_alert.time_left
			_ready_label.text = Loc.t("ETA %.1fs%s") % [eta, Loc.t("  LATE") if late else ""]
			_ready_label.add_theme_color_override("font_color", C.RED if late else C.WHITE)

	if not preview_rescue.is_empty() and preview_alert == null and unit_type != World.rescue_team_type():
		_ready_label.text = Loc.t("HEAVY ONLY")
		_ready_label.add_theme_color_override("font_color", C.RED)
		late = true
	elif not preview_rescue.is_empty() and preview_alert == null:
		_best = World.best_unit_for_sector(unit_type, preview_sector)
		if _best != null:
			var rescue_eta := World.travel_time(_best, _best.location, preview_sector)
			late = rescue_eta >= float(preview_rescue.get("time_left", 0.0))
			_ready_label.text = Loc.t("ETA %.1fs%s") % [rescue_eta, Loc.t("  LATE") if late else ""]
			_ready_label.add_theme_color_override("font_color", C.RED if late else C.WHITE)

	for i in members.size():
		# Away units fade out of the stack until they are ready again.
		_portraits[i].modulate = Color.WHITE if members[i].status == UnitState.Status.IDLE else Color(1, 1, 1, 0.12)
	_member_view.queue_redraw()

	disabled = ready_count == 0
	_style.border_color = Color(C.DIM, 0.6)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	if selected:
		_frame.accent = C.WHITE
		_frame.glow = 0.7 + 0.3 * pulse
	elif late:
		_frame.accent = C.RED
		_frame.glow = 0.0
	else:
		_frame.accent = _accent if ready_count > 0 else C.DIM
		_frame.glow = 0.6 if (_hovered and ready_count > 0) else 0.0
	var tint := 0.08 if ready_count > 0 else 0.0
	if selected:
		tint = 0.22
	elif _hovered and ready_count > 0:
		tint = 0.15
	_style.bg_color = C.PANEL.lerp(_accent, tint)


## One column per member: lamp + callsign, a thin progress bar, and a short status code.
func _draw_members() -> void:
	var font := _member_view.get_theme_default_font()
	var column := _member_view.size.x / maxf(1.0, float(members.size()))
	var calm := Color(0.45, 0.62, 0.58)
	for i in members.size():
		var unit := members[i]
		var x := i * column
		var lamp := C.TEXT
		var code := Loc.t("READY")
		var fraction := 0.0
		match unit.status:
			UnitState.Status.IDLE:
				lamp = C.TEXT
			UnitState.Status.STRANDED:
				lamp = C.RED
				code = Loc.t("STRANDED")
			UnitState.Status.TRAVELING:
				lamp = calm
				code = "> %s" % (C.sector_name(unit.alert.sector_id) if unit.alert != null else C.sector_name(unit.leg_to))
			UnitState.Status.RETURNING:
				lamp = calm
				code = Loc.t("COOLDOWN")
			UnitState.Status.STANDBY:
				lamp = _accent
				code = Loc.t("ON MAP")
			_:
				lamp = calm
				code = Loc.t("ON SITE")
		if unit.status != UnitState.Status.IDLE and unit.status_total > 0.0:
			fraction = clampf(unit.timer / unit.status_total, 0.0, 1.0)
		var name_color := C.WHITE if unit == _best else (C.TEXT if unit.status == UnitState.Status.IDLE else calm)

		_member_view.draw_circle(Vector2(x + 8, 13), 7.0, lamp)
		var name_size := 26 if members.size() <= 3 else 19
		_member_view.draw_string(font, Vector2(x + 20, 21), unit.callsign, HORIZONTAL_ALIGNMENT_LEFT, column - 24, name_size, name_color)
		var bar := Rect2(x + 2, 31, column - 14, 5)
		_member_view.draw_rect(bar, Color(C.DIM, 0.8))
		if fraction > 0.0:
			_member_view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), lamp)
		elif unit.status == UnitState.Status.IDLE:
			_member_view.draw_rect(bar, Color(C.TEXT, 0.35))
		_member_view.draw_string(font, Vector2(x + 2, 58), code, HORIZONTAL_ALIGNMENT_LEFT, column - 8, 22 if members.size() <= 3 else 17,
				Color(lamp, 0.85))
