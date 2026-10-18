class_name UnitState
extends RefCounted
## Runtime state of one response unit.

enum Status { IDLE, TRAVELING, WORKING, STRANDED, LOADING, TRANSPORTING, RETURNING, STANDBY }

var id: String = ""
var type: String = ""
var status: Status = Status.IDLE
var alert: Alert = null
var timer: float = 0.0
var rescue_id: int = 0   # >0 while travelling to a third-party rescue
var outcome: String = ""  # "perfect", "semi" or "wrong" for the current job
var callsign: String = ""  # radio name, e.g. QUAKE-2
var home: String = ""      # depot sector; the unit starts here and returns here
var location: String = ""  # sector the unit is currently in (updates on arrival and on return)
var travel_total: float = 0.0  # length of the current outbound trip, used if the unit is recalled
var status_total: float = 0.0  # timer value when the current status began (for progress bars and animation)
# The moving part of the current status, for the map animation. The unit slides from leg_from to leg_to
# over leg_time seconds, starting leg_t0 of the way along (1.0 = already there).
var leg_from: String = ""
var leg_to: String = ""
var leg_t0: float = 0.0
var leg_time: float = 0.0


func _init(p_id: String, p_type: String, p_home: String = "C", p_callsign: String = "") -> void:
	id = p_id
	callsign = p_callsign if p_callsign != "" else p_id.to_upper()
	type = p_type
	home = p_home
	location = p_home


func status_name() -> String:
	return Status.keys()[status]


func describe() -> String:
	return "%s [%s] %s" % [id, type, status_name()]
