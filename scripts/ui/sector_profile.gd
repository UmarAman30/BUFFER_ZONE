extends Control
## District file, opened with Shift + left click on a district and shown only while Shift is held.
## A fixed-width card drawn by hand: the district name and its alert status, each landmark with the
## hazards it is prone to (the feed names these landmarks, so a report can be matched to a hazard),
## an optional note, and the teams based there. It never reveals what an alert actually is.

signal closed

const C := preload("res://scripts/ui/ui_colors.gd")
const WIDTH := 600.0
const PAD := 24.0
const HEADER_H := 64.0
const ROW_GAP := 14.0
const CHIP_H := 34.0
const CHIP_GAP := 8.0

var _sector_id: String = ""
var _landmarks: Array = []    # [{name, hazards: Array[String]}]
var _note: String = ""
var _pop: float = 1.0         # open animation 0..1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(WIDTH, 200)


## Opens the file; `anchor` is the screen point to show it next to (kept on screen).
func open(sector_id: String, anchor: Vector2 = Vector2(960, 540)) -> void:
	_sector_id = sector_id
	var sector: Dictionary = GameData.sectors[_sector_id]
	var risks: Dictionary = sector.get("landmark_risks", {})
	_landmarks.clear()
	for landmark: String in sector.get("landmarks", []):
		_landmarks.append({"name": landmark.trim_prefix("the ").to_upper(), "hazards": _risk_names(risks.get(landmark, []))})
	_note = str(sector.get("note", ""))
	size = Vector2(WIDTH, _layout(false))
	var x := anchor.x + 40.0
	if x + size.x > 1880.0:
		x = anchor.x - size.x - 40.0
	position = Vector2(clampf(x, 20.0, 1900.0 - size.x), clampf(anchor.y - size.y * 0.5, 110.0, 950.0 - size.y))
	pivot_offset = Vector2(0.0 if x > anchor.x else size.x, size.y * 0.5)
	_pop = 0.0
	visible = true
	queue_redraw()


func close_profile() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	if not Input.is_key_pressed(KEY_SHIFT):
		close_profile()
		return
	_pop = minf(1.0, _pop + delta * 7.0)
	var eased := 1.0 - pow(1.0 - _pop, 3.0)
	scale = Vector2.ONE * lerpf(0.92, 1.0, eased)
	modulate.a = eased
	queue_redraw()


func _risk_names(incident_ids: Array) -> Array[String]:
	var names: Array[String] = []
	for incident_id: String in incident_ids:
		var incident: Dictionary = GameData.incidents.get(incident_id, {})
		names.append(Loc.upper(str(incident.get("risk_name", incident_id))))
	return names


func _draw() -> void:
	_layout(true)


## Lays the card out top to bottom; draws it when `paint` is true. Returns the total height.
func _layout(paint: bool) -> float:
	var font := get_theme_default_font()
	var inner := WIDTH - PAD * 2.0
	var y := 0.0
	var h := size.y
	if paint:
		draw_rect(Rect2(Vector2(6, 8), size), Color(0, 0, 0, 0.45))   # drop shadow
		draw_rect(Rect2(Vector2.ZERO, size), Color(C.BG, 0.97))
		draw_rect(Rect2(Vector2.ZERO, size), Color(C.TEXT, 0.8), false, 2.0)
		# Header: district name on a solid strip, alert status chip on the right.
		draw_rect(Rect2(0, 0, WIDTH, HEADER_H), C.TEXT)
		draw_string(font, Vector2(PAD, 46), C.sector_name(_sector_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, C.BG)
		var alerts: int = World.alerts_in_sector(_sector_id).size()
		var status := Loc.t("QUIET") if alerts == 0 else Loc.t("%d ALERT" if alerts == 1 else "%d ALERTS") % alerts
		var status_w := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 28.0
		var chip := Rect2(WIDTH - PAD - status_w, 14, status_w, 36)
		draw_rect(chip, C.BG)
		draw_string(font, Vector2(chip.position.x, 41), status, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 26, C.TEXT if alerts == 0 else C.YELLOW)
	y = HEADER_H + 22.0

	if paint:
		draw_string(font, Vector2(PAD, y + 18), Loc.t("LANDMARKS AND THEIR RISKS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C.DIM.lightened(0.65))
		draw_line(Vector2(PAD, y + 28), Vector2(WIDTH - PAD, y + 28), Color(C.DIM, 0.9), 2.0)
	y += 44.0

	for entry: Dictionary in _landmarks:
		if paint:
			draw_rect(Rect2(PAD, y + 6, 6, 22), C.TEXT)
			draw_string(font, Vector2(PAD + 18, y + 27), str(entry["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, C.WHITE)
		y += 40.0
		# Hazard chips, wrapping onto new lines when the row is full.
		var x := PAD + 18.0
		for hazard: String in entry["hazards"]:
			var w := font.get_string_size(hazard, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0
			if x + w > PAD + inner and x > PAD + 18.0:
				x = PAD + 18.0
				y += CHIP_H + CHIP_GAP
			if paint:
				var rect := Rect2(x, y, w, CHIP_H)
				draw_rect(rect, Color(C.TEXT, 0.12))
				draw_rect(rect, Color(C.TEXT, 0.6), false, 1.0)
				draw_string(font, Vector2(x, y + 24), hazard, HORIZONTAL_ALIGNMENT_CENTER, w, 22, C.TEXT)
			x += w + CHIP_GAP
		y += CHIP_H + ROW_GAP

	if _note != "":
		var lines := _wrap(font, _note, inner, 24)
		for line in lines:
			if paint:
				draw_string(font, Vector2(PAD, y + 22), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C.YELLOW)
			y += 30.0
		y += 6.0

	# Teams based in the district.
	if paint:
		draw_line(Vector2(PAD, y + 4), Vector2(WIDTH - PAD, y + 4), Color(C.DIM, 0.9), 2.0)
		var based: Array[String] = []
		for unit in World.units:
			if unit.home == _sector_id:
				based.append(unit.callsign)
		draw_string(font, Vector2(PAD, y + 36), Loc.t("BASED HERE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C.DIM.lightened(0.65))
		var label_w := font.get_string_size(Loc.t("BASED HERE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0
		draw_string(font, Vector2(PAD + label_w, y + 36), ", ".join(based) if not based.is_empty() else Loc.t("no teams"), HORIZONTAL_ALIGNMENT_LEFT, inner - label_w, 24, C.WHITE)
	y += 50.0
	if paint:
		draw_string(font, Vector2(0, y + 20), Loc.t("release SHIFT to close"), HORIZONTAL_ALIGNMENT_CENTER, WIDTH, 20, C.DIM.lightened(0.5))
	y += 34.0
	if paint:
		# Corner brackets, like the other console panels.
		var c := Color(C.TEXT, 0.9)
		for corner in [Vector2(0, 0), Vector2(WIDTH, 0), Vector2(0, h), Vector2(WIDTH, h)]:
			var sx := 1.0 if corner.x == 0.0 else -1.0
			var sy := 1.0 if corner.y == 0.0 else -1.0
			draw_line(corner, corner + Vector2(18 * sx, 0), c, 4.0)
			draw_line(corner, corner + Vector2(0, 18 * sy), c, 4.0)
	return y


func _wrap(font: Font, text: String, width: float, font_size: int) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = word
		else:
			line = test
	if line != "":
		lines.append(line)
	return lines
