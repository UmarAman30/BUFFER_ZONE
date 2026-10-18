extends Panel
## Live feed window, opened and closed with the right mouse button. One scrolling list in time order
## (oldest at the top, newest at the bottom, so lines never move while you read them),
## mixing calls, sensors, radio field reports and social. Column tabs mark the sector (left) and the report
## (right); a dashed NEW line sits above the newest report. TRENDING rows (a group of people saying the same thing) are highlighted as reliable;
## single social posts are marked UNVERIFIED. Hovering a row lights its district on the map.
## As public trust falls, new lines arrive increasingly corrupted.

signal sector_hovered(sector_id: String)

const C := preload("res://scripts/ui/ui_colors.gd")
const PANEL_SIZE := Vector2(1240, 720)
const MAX_ROWS := 60
const TAG_WIDTH := 270.0
const HEADER_Y := 60.0
const SOURCE_WIDTH := 240.0
const GLITCH_GLYPHS := ["#", "%", "&", "@", "$", "*", "?", "/", "!"]
const CHANNEL_COLORS := {
	"audio": Color(0.55, 1.0, 0.65),
	"sensor": Color(0.45, 0.9, 1.0),
	"radio": Color(0.9, 0.95, 0.9),
	"social": Color(0.75, 0.7, 0.85),
	"trend": Color(0.95, 0.85, 1.0),
	"unit": Color(0.8, 0.9, 0.85),
}
const SOURCE_NAMES := {"audio": "CALL", "sensor": "SENSOR", "radio": "RADIO", "social": "POST", "unit": "UNIT"}

var _list: VBoxContainer
var _scroll: ScrollContainer
var _count_label: Label
var _new_marker: Control   # dashed Loc.t("NEW") line above the newest report


func _ready() -> void:
	size = PANEL_SIZE
	visible = false
	add_theme_stylebox_override("panel", C.box(Color(C.BG, 0.97), C.DIM, 1))

	var title := Label.new()
	title.text = Loc.t("LIVE FEED")
	title.position = Vector2(24, 10)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C.TEXT)
	add_child(title)

	_count_label = Label.new()
	_count_label.position = Vector2(220, 20)
	_count_label.add_theme_font_size_override("font_size", 18)
	_count_label.add_theme_color_override("font_color", C.DIM.lightened(0.6))
	add_child(_count_label)

	var close := Label.new()
	close.text = Loc.t("RIGHT-CLICK OR ESC TO CLOSE")
	close.position = Vector2(PANEL_SIZE.x - 300, 20)
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_color_override("font_color", C.DIM.lightened(0.6))
	add_child(close)

	var legend := Label.new()
	legend.text = Loc.t("TRENDING = reliable     POST = unverified     SENSOR, RADIO = official")
	legend.position = Vector2(24, PANEL_SIZE.y - 34)
	legend.add_theme_font_size_override("font_size", 16)
	legend.add_theme_color_override("font_color", C.DIM.lightened(0.5))
	add_child(legend)

	# Column tabs: where a report comes from (left) and what it says (right).
	_header_tab(Loc.t("SECTOR"), Vector2(22, HEADER_Y), Vector2(TAG_WIDTH, 40))
	_header_tab(Loc.t("LIVE FEED INFORMATION"), Vector2(22 + TAG_WIDTH + 12, HEADER_Y), Vector2(PANEL_SIZE.x - 66 - TAG_WIDTH - 12, 40))

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(16, HEADER_Y + 48)
	_scroll.size = Vector2(PANEL_SIZE.x - 32, PANEL_SIZE.y - HEADER_Y - 48 - 42)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(_scroll.size.x - 16, 0)
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	C.add_frame(self)
	EventBus.feed_entry_added.connect(func(entry: Dictionary) -> void:
		if visible:
			_append(_make_row(entry), true))
	EventBus.game_started.connect(_rebuild)
	EventBus.feed_cleared.connect(func(_alert_id: int) -> void:
		if visible:
			_rebuild())
	visibility_changed.connect(func() -> void:
		if visible:
			_rebuild())


func _header_tab(text: String, at: Vector2, tab_size: Vector2) -> void:
	var tab := Label.new()
	tab.text = text
	tab.position = at
	tab.size = tab_size
	tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab.add_theme_font_size_override("font_size", 20)
	tab.add_theme_color_override("font_color", C.TEXT)
	var style := C.box(C.PANEL.lightened(0.08), C.TEXT, 0)
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	tab.add_theme_stylebox_override("normal", style)
	add_child(tab)


## The dashed NEW divider that sits just above the newest report.
func _make_new_marker() -> Control:
	var marker := Control.new()
	marker.custom_minimum_size = Vector2(_list.custom_minimum_size.x, 26)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(func() -> void:
		var w := marker.size.x
		var y := marker.size.y * 0.5
		var font := marker.get_theme_default_font()
		var color := C.YELLOW
		marker.draw_dashed_line(Vector2(0, y), Vector2(w * 0.5 - 40, y), Color(color, 0.8), 2.0, 8.0)
		marker.draw_dashed_line(Vector2(w * 0.5 + 40, y), Vector2(w, y), Color(color, 0.8), 2.0, 8.0)
		marker.draw_rect(Rect2(w * 0.5 - 34, 1, 68, marker.size.y - 2), Color(C.BG, 1.0))
		marker.draw_rect(Rect2(w * 0.5 - 34, 1, 68, marker.size.y - 2), color, false, 2.0)
		marker.draw_string(font, Vector2(w * 0.5 - 34, y + 7), Loc.t("NEW"), HORIZONTAL_ALIGNMENT_CENTER, 68, 20, color))
	return marker


## Puts the NEW divider right above the last row.
func _place_new_marker() -> void:
	if _new_marker == null or not is_instance_valid(_new_marker):
		_new_marker = _make_new_marker()
	if _new_marker.get_parent() == _list:
		_list.remove_child(_new_marker)
	if _list.get_child_count() == 0:
		return
	_list.add_child(_new_marker)
	_list.move_child(_new_marker, _list.get_child_count() - 2)


func _rebuild() -> void:
	if _new_marker != null and is_instance_valid(_new_marker) and _new_marker.get_parent() == _list:
		_list.remove_child(_new_marker)
	for child in _list.get_children():
		child.queue_free()
	var all: Array = []
	for channel: String in Feed.CHANNELS:
		for entry: Dictionary in Feed.entries.get(channel, []):
			all.append(entry)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("time", 0.0)) < float(b.get("time", 0.0)))
	for i in range(maxi(0, all.size() - MAX_ROWS), all.size()):
		_list.add_child(_make_row(all[i]))
	_place_new_marker()
	_scroll_to_bottom.call_deferred()


## New line at the bottom. The view only follows it if you were already at the bottom, so reading
## further up is never interrupted. The new line flashes briefly so it is easy to spot.
func _append(row: Control, fresh: bool) -> void:
	var bar := _scroll.get_v_scroll_bar()
	var at_bottom := _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 40
	_list.add_child(row)
	while _list.get_child_count() > MAX_ROWS + 1:
		var first := _list.get_child(0)
		if first == _new_marker:
			break
		_list.remove_child(first)
		first.queue_free()
	_place_new_marker()
	if fresh:
		row.modulate = Color(1.8, 1.8, 1.8)
		create_tween().tween_property(row, "modulate", Color.WHITE, 1.5)
	if at_bottom:
		_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _make_row(entry: Dictionary) -> Control:
	var channel := str(entry.get("channel", ""))
	var sector := str(entry.get("sector", ""))
	var trending := entry.has("trend_count")
	var kind := "trend" if trending else channel
	var color: Color = entry.get("color", CHANNEL_COLORS.get(kind, C.TEXT))

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal := C.box(Color(C.PANEL, 0.85) if trending else Color(C.BG, 0.6), Color(color, 0.7) if trending else Color(0, 0, 0, 0), 2 if trending else 0)
	var hovered := C.box(C.PANEL.lightened(0.12), C.DIM.lightened(0.4), 1)
	row.add_theme_stylebox_override("panel", normal)
	if sector != "":
		row.mouse_entered.connect(func() -> void:
			row.add_theme_stylebox_override("panel", hovered)
			sector_hovered.emit(sector))
		row.mouse_exited.connect(func() -> void:
			row.add_theme_stylebox_override("panel", normal)
			sector_hovered.emit(""))

	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)

	# District tag: a solid chip so the location is the first thing you read.
	var tag := Label.new()
	tag.text = C.sector_name(sector) if sector != "" else Loc.t("FIELD UNIT")
	tag.custom_minimum_size = Vector2(TAG_WIDTH, 52)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", C.BG if sector != "" else C.TEXT)
	tag.add_theme_stylebox_override("normal", C.box(C.TEXT if sector != "" else Color(C.DIM, 0.6), Color(0, 0, 0, 0), 0))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(tag)

	var source := Label.new()
	var seconds := int(entry.get("time", 0.0))
	var source_name := Loc.t(str(SOURCE_NAMES.get(channel, channel.to_upper())))
	if trending:
		source_name = Loc.t("TRENDING %d") % int(entry["trend_count"])
	elif channel == "social":
		source_name = Loc.t("POST (unverified)")
	source.text = "%02d:%02d  %s" % [floori(seconds / 60.0), seconds % 60, source_name]
	source.custom_minimum_size = Vector2(SOURCE_WIDTH, 0)
	source.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	source.add_theme_font_size_override("font_size", 17)
	source.add_theme_color_override("font_color", color if trending else C.DIM.lightened(0.6))
	source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(source)

	var body := Label.new()
	body.text = _glitch(str(entry.get("text", ""))) if channel != "unit" else str(entry.get("text", ""))
	body.custom_minimum_size = Vector2(_list.custom_minimum_size.x - TAG_WIDTH - SOURCE_WIDTH - 60, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Color(color, 0.7) if (channel == "social" and not trending) else color)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(body)
	return row


## Corrupts a fraction of the characters, more as public trust falls (none above 60 trust).
func _glitch(text: String) -> String:
	var amount := clampf((60.0 - GameState.trust) / 60.0, 0.0, 1.0) * 0.14
	if amount <= 0.0:
		return text
	var out := ""
	for i in text.length():
		var character := text[i]
		if character != " " and randf() < amount:
			out += GLITCH_GLYPHS[randi() % GLITCH_GLYPHS.size()]
		else:
			out += character
	return out


func _process(_delta: float) -> void:
	if not visible:
		return
	# Everything in the open window counts as read.
	for channel: String in Feed.CHANNELS:
		Feed.unread[channel] = 0
	Feed.mark_all_seen()
	var rows := _list.get_child_count()
	if _new_marker != null and is_instance_valid(_new_marker) and _new_marker.get_parent() == _list:
		rows -= 1
	_count_label.text = Loc.t("%d REPORTS") % rows
