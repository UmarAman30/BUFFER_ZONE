extends Node
## Language switch: "en" (default) or "tr". Chosen on the start screen (LANGUAGE.EXE) and remembered
## in user://settings.cfg.
##   - Text written in scripts goes through Loc.t("English text"); the Turkish wording is looked up in
##     res://data/tr/ui.json (English -> Turkish). Missing entries simply stay English.
##   - Content files (feed, incidents, sectors, units, briefing, taglines) have full Turkish copies in
##     res://data/tr/ with the same structure as res://data/en/; GameData loads those through Loc.data_path().
##   - Loc.upper() capitalises with Turkish rules (i -> İ, ı -> I).
## District and landmark names stay in English in both languages.

signal language_changed(lang: String)

const SETTINGS := "user://settings.cfg"
const UI_FILE := "res://data/tr/ui.json"

var lang: String = "en"
var _ui: Dictionary = {}
var _ui_tr: Dictionary = {}     # the Turkish map, always loaded (for switching mid-game)
var _swap: Dictionary = {}      # old-language text -> new-language text for the last switch


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		lang = str(config.get_value("game", "language", "en"))
	_load_ui()


func set_language(code: String) -> void:
	if code == lang:
		return
	lang = code
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("game", "language", lang)
	config.save(SETTINGS)
	var old_names := _data_names()
	_load_ui()
	GameData.reload()
	_build_swap(old_names)
	language_changed.emit(lang)


func is_turkish() -> bool:
	return lang == "tr"


## Translates a piece of UI text written in English. Unknown text is returned unchanged.
func t(text: String) -> String:
	if lang == "tr":
		return str(_ui.get(text, text))
	return text


## Upper case that respects Turkish dotted / dotless i.
func upper(text: String) -> String:
	if lang == "tr":
		return text.replace("i", "İ").replace("ı", "I").to_upper()
	return text.to_upper()


## Turkish-aware upper case for BBCode text: tags such as [color=#ff4444] keep their spelling.
## For all-caps fonts (HomeVideo), whose lowercase dotless i would otherwise draw like a dotted one.
func upper_rich(text: String) -> String:
	var tags := RegEx.create_from_string("\\[/?(color|b|i|u|font_size|wave|shake)[^\\]]*\\]")
	var out := ""
	var last := 0
	for found in tags.search_all(text):
		out += upper(text.substr(last, found.get_start() - last)) + found.get_string()
		last = found.get_end()
	return out + upper(text.substr(last))


## The Turkish copy (res://data/tr/) of a res://data/en/ file when Turkish is on and the copy exists.
func data_path(path: String) -> String:
	if lang == "tr":
		var translated := path.replace("res://data/en/", "res://data/tr/")
		if FileAccess.file_exists(translated):
			return translated
	return path


func _load_ui() -> void:
	if _ui_tr.is_empty():
		var file := FileAccess.open(UI_FILE, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_ui_tr = parsed
	_ui = _ui_tr if lang == "tr" else {}


# ---------------------------------------------------------------- switching mid-game

## Team and incident names from the loaded content files, keyed by id.
func _data_names() -> Dictionary:
	var names := {}
	for type_id: String in GameData.unit_types:
		names["unit:" + type_id] = str(GameData.unit_types[type_id].get("name", ""))
	for incident_id: String in GameData.incidents:
		names["inc:" + incident_id] = str(GameData.incidents[incident_id].get("name", ""))
		names["risk:" + incident_id] = str(GameData.incidents[incident_id].get("risk_name", ""))
	return names


## Builds the old -> new text table used by retranslate() after a switch.
func _build_swap(old_names: Dictionary) -> void:
	_swap = {}
	var to_tr := lang == "tr"
	for english: String in _ui_tr:
		var turkish := str(_ui_tr[english])
		if to_tr:
			_swap[english] = turkish
		else:
			_swap[turkish] = english
	var new_names := _data_names()
	var old_lang := "en" if to_tr else "tr"
	for key: String in old_names:
		var before := str(old_names[key])
		var after := str(new_names.get(key, before))
		if before == "" or before == after:
			continue
		_swap[before] = after
		_swap[_upper_in(before, old_lang)] = upper(after)


func _upper_in(text: String, code: String) -> String:
	if code == "tr":
		return text.replace("i", "İ").replace("ı", "I").to_upper()
	return text.to_upper()


## Swaps the static text of every Label / Button under `root` into the new language. Text that is
## rebuilt on its own (timers, counters, drawn text) is left to its owner.
func retranslate(root: Node) -> void:
	if _swap.is_empty():
		return
	for node in root.find_children("*", "", true, false):
		if node is Label or node is Button:
			var text: String = node.text
			if _swap.has(text):
				node.text = _swap[text]
			else:
				# "TEAM NAME  x3" style labels: swap the part before the count.
				for before: String in _swap:
					if before.length() > 3 and text.begins_with(before + " "):
						node.text = str(_swap[before]) + text.substr(before.length())
						break
