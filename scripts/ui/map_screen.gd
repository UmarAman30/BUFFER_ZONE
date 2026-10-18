extends Control
## The main (and only) play screen: the city map in the centre, team stacks in a bar underneath.
## Top-left plate: feed lamps (one per channel, lit while it has unread lines); right-click opens the feed.
## Dispatch: click an alert blip, then a team stack (either order), or drag a stack onto a blip;
## the stack's nearest ready unit goes. Teams that finished a job wait on the map as glowing chips for a
## few seconds: click / drag a chip to redeploy that unit from where it is. Shift + click a district for its file.

const AlertIconScript := preload("res://scripts/ui/alert_icon.gd")
const UnitStackScript := preload("res://scripts/ui/unit_stack.gd")
const SectorProfileScript := preload("res://scripts/ui/sector_profile.gd")
const CityScopeScript := preload("res://scripts/ui/city_scope.gd")
const FeedPanelScript := preload("res://scripts/ui/feed_panel.gd")
const RescueIconScript := preload("res://scripts/ui/rescue_icon.gd")
const C := preload("res://scripts/ui/ui_colors.gd")

const STACK_ORDER := ["quick_deploy", "earthquake", "emf"]
const STACK_Y := 962.0   # team bar along the bottom edge
const STACK_GAP := 20.0
const LAMP_CHANNELS := [["audio", "CALLS"], ["sensor", "SENS"], ["radio", "RADIO"], ["social", "SOCIAL"]]

var _alerts: Dictionary = {}         # alert id -> blip
var _stacks: Array = []
var _selected_alert: Alert = null
var _selected_type: String = ""
var _selected_unit: UnitState = null   # a standby unit picked on the map
var _banner: Label
var _scope: Control
var _feed: Panel
var _lamp_title: Label
var _lamp_view: Control
var _lamp_flash: Dictionary = {}     # channel -> time of the last new line
var _rescue_icons: Dictionary = {}     # rescue id -> marker
var _selected_rescue: int = -1
var _lock: Variant = null   # tutorial: null = everything allowed, else the Array of allowed interactions
var _profile: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_scope = CityScopeScript.new()
	_scope.profile_requested.connect(func(sector_id: String) -> void:
		if _allowed("profile"):
			_profile.open(sector_id, get_global_mouse_position()))
	_scope.background_clicked.connect(_clear_selection)
	_scope.standby_pressed.connect(_on_standby_pressed)
	add_child(_scope)

	# Feed lamps plate (top-left).
	var lamps := _plate(Vector2(20, 18), Vector2(430, 80))
	_lamp_title = _plate_label(lamps, Vector2(14, 2), 16)
	_lamp_view = Control.new()
	_lamp_view.size = lamps.size
	_lamp_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamp_view.draw.connect(_draw_lamps)
	lamps.add_child(_lamp_view)

	_feed = FeedPanelScript.new()
	_feed.position = Vector2((1920.0 - _feed.PANEL_SIZE.x) * 0.5, 112)
	add_child(_feed)
	_feed.sector_hovered.connect(func(sector_id: String) -> void: _scope.feed_highlight = sector_id)

	_profile = SectorProfileScript.new()
	add_child(_profile)

	# Big centred banner when the threat level rises.
	_banner = Label.new()
	_banner.position = Vector2(0, 380)
	_banner.size = Vector2(1920, 120)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.add_theme_color_override("font_color", C.RED)
	_banner.add_theme_color_override("font_outline_color", C.BG)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate.a = 0.0
	add_child(_banner)
	EventBus.difficulty_changed.connect(_on_difficulty_changed)

	EventBus.game_started.connect(_on_game_started)
	EventBus.feed_entry_added.connect(_on_feed_entry)
	EventBus.alert_spawned.connect(_on_alert_spawned)
	EventBus.alert_expired.connect(_on_alert_gone)
	EventBus.alert_resolved.connect(func(alert: Alert, _reward: float) -> void: _on_alert_gone(alert))
	EventBus.game_over.connect(func(_score: int) -> void:
		_feed.visible = false
		_profile.close_profile()
		_clear_selection())
	EventBus.unit_dispatched.connect(func(_unit: UnitState, _alert: Alert) -> void: _clear_selection())
	EventBus.rescue_spawned.connect(_on_rescue_spawned)
	EventBus.rescue_gone.connect(_on_rescue_gone)
	EventBus.rescue_dispatched.connect(func(_unit: UnitState, _rescue: Dictionary) -> void: _clear_selection())
	EventBus.unit_unlocked.connect(func(_unit: UnitState) -> void:
		_build_stacks()
		_update_selection())
	EventBus.banner_requested.connect(_flash_banner)
	_update_selection()


func _plate(at: Vector2, plate_size: Vector2) -> Panel:
	var plate := Panel.new()
	plate.position = at
	plate.size = plate_size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", C.box(Color(C.PANEL, 0.92), Color(0, 0, 0, 0), 0))
	add_child(plate)
	C.add_frame(plate, C.DIM.lightened(0.5))
	return plate


func _plate_label(plate: Panel, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", C.TEXT)
	plate.add_child(label)
	return label


func _process(_delta: float) -> void:
	_lamp_title.text = Loc.t("LIVE FEED  [RIGHT-CLICK]") if not _feed.visible else Loc.t("LIVE FEED  OPEN")
	# A picked standby unit that timed out (or was sent) can no longer be ordered.
	if _selected_unit != null and _selected_unit.status != UnitState.Status.STANDBY:
		_selected_unit = null
		_update_selection()
	_lamp_view.queue_redraw()


func _draw_lamps() -> void:
	var font := _lamp_view.get_theme_default_font()
	var now := Time.get_ticks_msec() / 1000.0
	# Labels change length with the language and unread counts, so space the lamps by their real widths.
	var labels: Array[String] = []
	for entry in LAMP_CHANNELS:
		var count := int(Feed.unread.get(entry[0], 0))
		labels.append(Loc.t(str(entry[1])) + ("" if count == 0 else " %d" % count))
	var font_size := 24
	var widths: Array[float] = []
	var gap := 0.0
	while true:
		widths.clear()
		var used := 0.0
		for label in labels:
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			widths.append(w)
			used += 22.0 + w
		gap = (_lamp_view.size.x - 30.0 - used) / float(labels.size() - 1)
		if gap >= 20.0 or font_size <= 16:
			break
		font_size -= 2
	var x := 26.0
	for i in LAMP_CHANNELS.size():
		var channel: String = LAMP_CHANNELS[i][0]
		var unread := int(Feed.unread.get(channel, 0))
		var center := Vector2(x, 56)
		x += 22.0 + widths[i] + gap
		var lit := unread > 0
		var fresh := now - float(_lamp_flash.get(channel, -100.0)) < 2.0
		var color := C.TEXT
		if fresh and fmod(now, 0.25) < 0.125:
			color = C.WHITE
		if lit:
			_lamp_view.draw_circle(center, 14.0, Color(color, 0.18))
			_lamp_view.draw_circle(center, 8.0, color)
		else:
			_lamp_view.draw_circle(center, 8.0, Color(C.BG, 1.0))
		_lamp_view.draw_arc(center, 8.0, 0.0, TAU, 20, C.DIM.lightened(0.4), 2.0)
		_lamp_view.draw_string(font, center + Vector2(14, 8), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				C.TEXT if lit else C.DIM.lightened(0.4))


## New feed lines light their channel lamp.
func _on_feed_entry(entry: Dictionary) -> void:
	_lamp_flash[str(entry["channel"])] = Time.get_ticks_msec() / 1000.0


## Right mouse button opens / closes the live feed (anywhere on screen); Esc also closes it.
func _input(event: InputEvent) -> void:
	if GameState.state != GameState.State.PLAYING or get_tree().paused:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			if not _allowed("feed"):
				get_viewport().set_input_as_handled()
				return
			_feed.visible = not _feed.visible
			EventBus.sfx_requested.emit("feed_open" if _feed.visible else "feed_close")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _feed.visible:
		_feed.visible = false
		EventBus.sfx_requested.emit("feed_close")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		# 1, 2, 3 pick the team stacks left to right; then click an alert to send it.
		var index := _number_key(event as InputEventKey)
		if index >= 0 and not _allowed("hotkeys"):
			get_viewport().set_input_as_handled()
			return
		if index >= 0 and index < _stacks.size():
			var stack = _stacks[index]
			if stack.idle_count() > 0 or _selected_type == stack.unit_type:
				_on_stack_pressed(stack.unit_type)
			else:
				EventBus.sfx_requested.emit("failure_buzzer")
			get_viewport().set_input_as_handled()


func _number_key(key: InputEventKey) -> int:
	match key.physical_keycode:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
	match key.keycode:
		KEY_KP_1:
			return 0
		KEY_KP_2:
			return 1
		KEY_KP_3:
			return 2
	return -1


# ---------------------------------------------------------------- tutorial helpers

## The tutorial isolates one mechanic at a time: `allowed` lists what the player may use right now
## ("feed", "profile", "ecm", "hotkeys", "stack", "alert", "chips", "casualty"); null lifts the lock.
func set_lock(allowed: Variant) -> void:
	_lock = allowed
	for blip in _alerts.values():
		blip.drops_enabled = _allowed("stack")


func _allowed(what: String) -> bool:
	return _lock == null or what in (_lock as Array)


func chip_rect() -> Rect2:
	return _scope.chip_rect()

func feed_open() -> bool:
	return _feed.visible


func set_feed_open(on: bool) -> void:
	_feed.visible = on


func feed_rect() -> Rect2:
	return Rect2(_feed.position, _feed.size)


func profile_open() -> bool:
	return _profile.visible


func close_profile() -> void:
	_profile.close_profile()


func clear_selection() -> void:
	_clear_selection()


func selected_type() -> String:
	return _selected_type


func alert_rect(alert: Alert) -> Rect2:
	return _scope.alert_pin_rect(alert.id) if alert != null else Rect2()


## Centre of a district in this screen's coordinates (used by the missile event).
func district_point(sector_id: String) -> Vector2:
	return _scope.district_center(sector_id)


func district_rect(sector_id: String) -> Rect2:
	return Rect2(_scope.district_center(sector_id) - Vector2(120, 80), Vector2(240, 160))


## Screen rectangles of the team stacks, left to right (used by the tutorial).
func stack_rects() -> Array:
	var rects: Array = []
	for stack in _stacks:
		rects.append({"type": stack.unit_type, "rect": Rect2(stack.position, stack.size)})
	return rects


func _on_difficulty_changed(level: int) -> void:
	_flash_banner(Loc.t("THREAT LEVEL %d") % (level + 1))


func _flash_banner(text: String) -> void:
	_banner.text = Loc.t(text)
	_banner.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.8)
	EventBus.sfx_requested.emit("alarm_red")


func _on_game_started() -> void:
	_feed.visible = false
	_rescue_icons.clear()
	_selected_rescue = -1
	_scope.clear_pins()
	_scope.clear_chips()
	_alerts.clear()
	_clear_selection()
	_profile.close_profile()
	_build_stacks()


## (Re)builds the team stacks from World.units; called at the start and whenever a team is unlocked.
func _build_stacks() -> void:
	for stack in _stacks:
		stack.queue_free()
	_stacks.clear()
	var total := 0.0
	var built: Array = []
	for unit_type: String in STACK_ORDER:
		var members: Array[UnitState] = []
		for unit in World.units:
			if unit.type == unit_type:
				members.append(unit)
		if members.is_empty():
			continue
		var stack = UnitStackScript.new()
		stack.setup(unit_type, members)
		stack.hotkey = str(built.size() + 1)
		stack.pressed.connect(_on_stack_clicked.bind(unit_type))
		stack.drag_state.connect(_on_stack_drag)
		built.append(stack)
		total += stack.size.x
	total += STACK_GAP * maxf(0.0, built.size() - 1.0)
	var x := (1920.0 - total) * 0.5
	for stack in built:
		stack.position = Vector2(x, STACK_Y)
		x += stack.size.x + STACK_GAP
		add_child(stack)
		_stacks.append(stack)
	move_child(_feed, -1)
	move_child(_profile, -1)


# ---------------------------------------------------------------- alerts

func _on_alert_spawned(alert: Alert) -> void:
	var blip = AlertIconScript.new()
	blip.setup(alert)
	blip.pressed.connect(_on_alert_pressed.bind(alert))
	blip.drops_enabled = _allowed("stack")
	_scope.add_pin(blip, alert)
	_alerts[alert.id] = blip


func _on_alert_gone(alert: Alert) -> void:
	_scope.remove_pin(alert.id)
	_alerts.erase(alert.id)
	if _selected_alert == alert:
		_selected_alert = null
		_update_selection()


func _on_alert_pressed(alert: Alert) -> void:
	if not _allowed("alert"):
		return
	# Alerts with a team still on the road can be picked too, so a closer team of that type can take over.
	if alert.assigned and not World.alert_reassignable(alert):
		return
	_selected_rescue = -1
	_selected_alert = null if _selected_alert == alert else alert
	_try_dispatch()


# ---------------------------------------------------------------- teams and selection

## A team card was clicked (the tutorial may forbid it; the 1, 2, 3 hotkeys call _on_stack_pressed directly).
func _on_stack_clicked(unit_type: String) -> void:
	if _allowed("stack"):
		_on_stack_pressed(unit_type)


func _on_stack_pressed(unit_type: String) -> void:
	_selected_type = "" if _selected_type == unit_type else unit_type
	_selected_unit = null
	_try_dispatch()


## A standby team on the map was clicked: pick that exact unit.
func _on_standby_pressed(unit: UnitState) -> void:
	if not _allowed("chips"):
		return
	_selected_unit = null if _selected_unit == unit else unit
	_selected_type = ""
	EventBus.sfx_requested.emit("ui_click")
	_try_dispatch()


## Dragging a stack counts as picking that team; ending the drag drops the pick.
func _on_stack_drag(unit_type: String, active: bool) -> void:
	if not _allowed("stack"):
		return
	_selected_type = unit_type if active else ""
	_update_selection()


func _try_dispatch() -> void:
	if _selected_rescue >= 0 and (_selected_type != "" or _selected_unit != null):
		var picked_type := _selected_unit.type if _selected_unit != null else _selected_type
		if picked_type != World.rescue_team_type() and _rescue_icons.has(_selected_rescue):
			# Wrong team for the stranded one: a small notice pops from the hexagon, the SOS stays selected.
			_rescue_icons[_selected_rescue].show_notice(Loc.t("HEAVY ONLY"))
			EventBus.sfx_requested.emit("failure_buzzer")
			_selected_type = ""
			_selected_unit = null
			_update_selection()
			return
		var rescue := World.get_rescue(_selected_rescue)
		var helper: UnitState = null
		if not rescue.is_empty():
			helper = _selected_unit if _selected_unit != null else World.best_unit_for_sector(_selected_type, str(rescue["sector"]))
		if helper == null or not World.dispatch_rescue(helper.id, _selected_rescue):
			EventBus.sfx_requested.emit("failure_buzzer")
		_selected_rescue = -1
		_selected_alert = null
		_selected_type = ""
		_selected_unit = null
		_update_selection()
		return
	if _selected_alert != null and (_selected_type != "" or _selected_unit != null):
		var unit := _selected_unit if _selected_unit != null else World.best_unit_of_type(_selected_type, _selected_alert)
		if unit == null or not World.dispatch(unit.id, _selected_alert.id):
			EventBus.sfx_requested.emit("failure_buzzer")   # e.g. a different team type than the one en route
		_selected_alert = null
		_selected_type = ""
		_selected_unit = null
	_update_selection()


func _clear_selection() -> void:
	_selected_rescue = -1
	_selected_alert = null
	_selected_type = ""
	_selected_unit = null
	_update_selection()


func _update_selection() -> void:
	_scope.set_chip_selection(_selected_unit, _selected_alert)
	for blip in _alerts.values():
		blip.selected = blip.alert == _selected_alert
	var picked_rescue := World.get_rescue(_selected_rescue) if _selected_rescue >= 0 else {}
	for icon_id: int in _rescue_icons:
		_rescue_icons[icon_id].selected = icon_id == _selected_rescue
	for stack in _stacks:
		stack.selected = stack.unit_type == _selected_type
		stack.preview_alert = _selected_alert
		stack.preview_sector = str(picked_rescue.get("sector", ""))
		stack.preview_rescue = picked_rescue


# ---------------------------------------------------------------- third-party rescues

func _on_rescue_spawned(rescue: Dictionary) -> void:
	var icon = RescueIconScript.new()
	icon.setup(rescue)
	icon.pressed.connect(_on_rescue_pressed.bind(int(rescue["id"])))
	_scope.add_casualty_pin(icon, rescue)   # same placement and bookkeeping as casualty markers
	_rescue_icons[int(rescue["id"])] = icon
	EventBus.sfx_requested.emit("alarm_red")


func _on_rescue_gone(rescue: Dictionary, _result: String) -> void:
	var rescue_id := int(rescue["id"])
	_scope.remove_casualty_pin(rescue_id)
	_rescue_icons.erase(rescue_id)
	if _selected_rescue == rescue_id:
		_selected_rescue = -1
		_update_selection()


func _on_rescue_pressed(rescue_id: int) -> void:
	if str(World.get_rescue(rescue_id).get("unit", "")) != "":
		return   # help is already on the way
	_selected_alert = null
	_selected_rescue = -1 if _selected_rescue == rescue_id else rescue_id
	_try_dispatch()
