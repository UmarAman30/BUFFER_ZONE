class_name Alert
extends RefCounted
## One active emergency. time_left counts down from its start value; the phase follows the clock.
## Once a unit is dispatched, `assigned` is true and the countdown stops.

enum Phase { GREEN, YELLOW, RED }
const PHASE_NAMES: Array[String] = ["green", "yellow", "red"]

var id: int = 0
var incident_id: String = ""
var sector_id: String = ""
var time_left: float = 30.0
var phase: Phase = Phase.GREEN
var assigned: bool = false
var revealed: bool = false   # set when the radar sweep first shows its blip
var locked_phase: Phase = Phase.GREEN  # phase at the moment a unit was dispatched; sets the reward


func _init(p_id: int, p_incident_id: String, p_sector_id: String, p_time_left: float) -> void:
	id = p_id
	incident_id = p_incident_id
	sector_id = p_sector_id
	time_left = p_time_left
	phase = Alert.phase_for(time_left)


static func phase_for(seconds_left: float) -> Phase:
	if seconds_left <= float(GameData.balance["red_at"]):
		return Phase.RED
	if seconds_left <= float(GameData.balance["yellow_at"]):
		return Phase.YELLOW
	return Phase.GREEN


## Advances the countdown. Returns true if the phase changed.
func tick(delta: float) -> bool:
	time_left = maxf(0.0, time_left - delta)
	var new_phase := Alert.phase_for(time_left)
	var changed := new_phase != phase
	phase = new_phase
	return changed


func phase_name() -> String:
	return PHASE_NAMES[phase]


func locked_phase_name() -> String:
	return PHASE_NAMES[locked_phase]


func describe() -> String:
	return "#%d %s in %s (%s, %.1fs)" % [id, incident_id, sector_id, phase_name(), time_left]
