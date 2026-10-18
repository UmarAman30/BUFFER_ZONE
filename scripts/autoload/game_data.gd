extends Node
## Loads the JSON files in res://data/ (config/ = language-neutral balance and map data, en/ and tr/ = text content) once at startup. Content and balance live in those files,
## so the writer can edit them without touching code.

var balance: Dictionary = {}
var sectors: Dictionary = {}          # id -> sector dictionary
var sector_order: Array[String] = []  # ids ordered west to east
var incidents: Dictionary = {}        # id -> incident dictionary
var unit_types: Dictionary = {}       # type id -> stats
var unit_reserves: Array = []          # third-party teams that can be rescued and unlocked
var unit_roster: Array = []           # [{id, type}, ...]
var feed_content: Dictionary = {}     # text pools for the data feed
var radio: Dictionary = {}           # radio chatter lines by event kind
var distances: Dictionary = {}       # sector-to-sector travel times
var tutorial: Dictionary = {}         # intro text, codec script, game-over taglines


func _ready() -> void:
	reload()


## (Re)reads every data file; content files come in the current language (see Loc.data_path).
func reload() -> void:
	sectors.clear()
	sector_order.clear()
	incidents.clear()
	balance = _load_json("res://data/config/balance.json")

	var sector_list: Array = _load_json("res://data/en/sectors.json").get("sectors", [])
	sector_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["map_index"] < b["map_index"])
	for sector: Dictionary in sector_list:
		sectors[sector["id"]] = sector
		sector_order.append(sector["id"])

	for incident: Dictionary in _load_json("res://data/en/incidents.json").get("incidents", []):
		incidents[incident["id"]] = incident

	var unit_data := _load_json("res://data/en/units.json")
	unit_types = unit_data.get("types", {})
	unit_roster = unit_data.get("roster", [])
	unit_reserves = unit_data.get("reserves", [])

	feed_content = _load_json("res://data/en/feed_content.json")
	tutorial = _load_json("res://data/en/tutorial.json")
	distances = _load_json("res://data/config/distances.json")


func _load_json(path: String) -> Dictionary:
	path = Loc.data_path(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameData: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("GameData: %s is not valid JSON (expected an object)" % path)
	return {}
