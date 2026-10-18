extends RefCounted
## Geometry of the city map. The art and district outlines are authored at 1920x1080 ("map pixels");
## the map is shown scaled and centred between the top bar and the unit bar. Districts are the polygons in
## res://data/config/map_polygons.json, so hover and clicks match what is drawn.

const MAP_POS := Vector2(124.8, 86)        # centred; the bottom edge (open sea) runs under the team bar
const MAP_SCALE := 0.87
const MAP_SIZE := Vector2(1670.4, 939.6)
const MAP_ART := "res://assets/images/map/clearvale_2d.jpg"
const WATER_MASK := "res://assets/images/map/water_mask.png"
const POLYGON_FILE := "res://data/config/map_polygons.json"
const LANDMARK_FILE := "res://data/config/landmarks.json"
const SECTOR_KEY := {"A": "Shoreline", "B": "Crestview", "C": "Downtown", "D": "Lowrise", "E": "Ridgeline"}
const HIT_ORDER := ["A", "D", "E", "B", "C"]    # smaller districts win where outlines touch

static var _polygons: Dictionary = {}    # sector id -> PackedVector2Array (map pixels)
static var _labels: Dictionary = {}      # UPPERCASE name -> map pixel position
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var polygon_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLYGON_FILE))
	if polygon_data is Dictionary:
		for sector_id: String in SECTOR_KEY:
			var points: Array = (polygon_data as Dictionary).get(SECTOR_KEY[sector_id], [])
			var outline := PackedVector2Array()
			for point: Array in points:
				outline.append(Vector2(point[0], point[1]))
			_polygons[sector_id] = outline
	var landmark_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDMARK_FILE))
	if landmark_data is Dictionary and (landmark_data as Dictionary).has("labels"):
		_labels = (landmark_data as Dictionary)["labels"]


static func sector_ids() -> Array:
	return SECTOR_KEY.keys()


## District outline in map pixels.
static func polygon(sector_id: String) -> PackedVector2Array:
	_load()
	return _polygons.get(sector_id, PackedVector2Array())


## Where a district's name tag sits, in map-local (scaled) pixels.
static func label_position(sector_id: String) -> Vector2:
	_load()
	var key := str(SECTOR_KEY[sector_id]).to_upper()
	if _labels.has(key):
		var point: Array = _labels[key]
		return Vector2(point[0], point[1]) * MAP_SCALE
	return Vector2.ZERO


## District under a point given in map-local (scaled) pixels, or "".
static func district_at(local: Vector2) -> String:
	_load()
	var map_point := local / MAP_SCALE
	for sector_id: String in HIT_ORDER:
		var outline: PackedVector2Array = _polygons.get(sector_id, PackedVector2Array())
		if outline.size() > 2 and Geometry2D.is_point_in_polygon(map_point, outline):
			return sector_id
	return ""


## Random spot inside a district (map-local pixels), kept clear of its borders where the shape allows.
static func random_point_in(sector_id: String, rng: RandomNumberGenerator) -> Vector2:
	_load()
	var outline: PackedVector2Array = _polygons.get(sector_id, PackedVector2Array())
	if outline.size() < 3:
		return MAP_SIZE * 0.5
	var low := outline[0]
	var high := outline[0]
	for point in outline:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	for attempt in 140:
		var candidate := Vector2(rng.randf_range(low.x, high.x), rng.randf_range(low.y, high.y))
		var margin := 26.0 if attempt < 70 else 8.0
		if Geometry2D.is_point_in_polygon(candidate, outline) and _edge_distance(candidate, outline) > margin:
			return candidate * MAP_SCALE
	return label_position(sector_id)


static func _edge_distance(point: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	for i in outline.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()])
		best = minf(best, point.distance_to(closest))
	return best
