extends Node
## Runs the simulation: spawns alerts, ticks their countdowns, and moves units through
## travel -> work/stranded -> standby on the map (redeployable for balance standby_seconds) -> back to the
## team bar with a cooldown. The UI only reads this state and listens to EventBus.

var alerts: Array[Alert] = []
var units: Array[UnitState] = []

var _next_alert_id: int = 1
var _spawn_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var difficulty_level: int = 0   # rises every balance difficulty.step_seconds
var casualties: Array[Dictionary] = []   # active casualty events (see EventBus.casualty_spawned)
var casualty_alt: Dictionary = {}        # sector id -> its fixed alternate clinic sector for this shift
var _next_casualty_id: int = 1
var rescues: Array[Dictionary] = []      # active third-party rescue events
var reserves: Array = []                 # teams still waiting to be rescued
var _next_rescue_id: int = 1000          # ids start high so map pins never clash with casualty ids
var _rescue_next_at: float = 0.0
var _relief_until: float = 0.0           # until then new alerts are all Green (trust was falling fast)
var _trust_log: Array = []               # [time, trust] samples for the last few seconds
var _rescue_done: bool = false           # the stranded-team event happens at most once per shift
var craters: Array[String] = []          # districts hit by a missile this shift (scorch marks on the map)
var missile_sector: String = ""          # district the first missile hit; the stranded team is sent there
var _missile_done: bool = false

const C_GOOD := Color(0.3, 0.95, 0.45)
const C_BAD := Color(1.0, 0.3, 0.3)


func _ready() -> void:
	_rng.randomize()
	set_process(false)
	EventBus.game_started.connect(_on_game_started)
	EventBus.trust_changed.connect(_on_trust_changed)
	EventBus.game_over.connect(func(_score: int) -> void: set_process(false))


func _on_game_started() -> void:
	alerts.clear()
	units.clear()
	_next_alert_id = 1
	difficulty_level = 0
	casualties.clear()
	_next_casualty_id = 1
	rescues.clear()
	reserves = GameData.unit_reserves.duplicate()
	_next_rescue_id = 1000
	_rescue_done = false
	craters.clear()
	missile_sector = ""
	_missile_done = false
	var rescue_settings: Dictionary = GameData.balance["rescue"]
	_rescue_next_at = float(rescue_settings["first_at"]) + _rng.randf_range(-float(rescue_settings["jitter"]), float(rescue_settings["jitter"]))
	_relief_until = 0.0
	_trust_log.clear()
	# Every district gets one fixed alternate clinic (any other district except the hospital's).
	casualty_alt.clear()
	var hospital := str(GameData.balance["hospital_sector"])
	for sector_id: String in GameData.sector_order:
		var options: Array = GameData.sector_order.filter(func(s: String) -> bool: return s != sector_id and s != hospital)
		casualty_alt[sector_id] = options.pick_random()
	for entry: Dictionary in GameData.unit_roster:
		units.append(UnitState.new(entry["id"], entry["type"], str(entry.get("depot", "C")), str(entry.get("callsign", ""))))
	_spawn_timer = float(GameData.balance["spawn"]["first_delay"])
	set_process(true)


func _process(delta: float) -> void:
	if GameState.state != GameState.State.PLAYING:
		return
	_tick_difficulty()
	_tick_missile()
	_tick_alerts(delta)
	_tick_units(delta)
	_tick_casualties(delta)
	_tick_rescues(delta)
	_tick_spawner(delta)


# ---------------------------------------------------------------- public API (used by UI)

func get_alert(alert_id: int) -> Alert:
	for alert in alerts:
		if alert.id == alert_id:
			return alert
	return null


func get_unit(unit_id: String) -> UnitState:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func alerts_in_sector(sector_id: String) -> Array[Alert]:
	var result: Array[Alert] = []
	for alert in alerts:
		if alert.sector_id == sector_id:
			result.append(alert)
	return result


## True if a unit of `unit_type` may be sent to this alert: it is open, or the team on it is still
## travelling and is the same type (so a closer one can take over).
func alert_open_for(alert: Alert, unit_type: String) -> bool:
	if not alert.assigned:
		return true
	var responder := _unit_for(alert)
	return responder != null and responder.status == UnitState.Status.TRAVELING and responder.type == unit_type


## True if the alert's current team could still be replaced (it is on the road, not on site).
func alert_reassignable(alert: Alert) -> bool:
	var responder := _unit_for(alert)
	return alert.assigned and responder != null and responder.status == UnitState.Status.TRAVELING


## True if the unit can take an order: ready in the team bar, or on standby on the map.
func can_dispatch(unit: UnitState) -> bool:
	return unit.status == UnitState.Status.IDLE or unit.status == UnitState.Status.STANDBY


## Sends a ready or standby unit to an alert, from wherever it is now. Returns false if not valid.
func dispatch(unit_id: String, alert_id: int) -> bool:
	var unit := get_unit(unit_id)
	var alert := get_alert(alert_id)
	if unit == null or alert == null:
		return false
	if not can_dispatch(unit) or not alert_open_for(alert, unit.type):
		return false
	if alert.assigned:
		# Handover: a same-type team takes over from one still on the road; that one turns back.
		var relieved := _unit_for(alert)
		relieved.alert = null
		EventBus.radio_event.emit("relieved", relieved, alert)
		_log("RELIEVED %s from %s by %s" % [relieved.id, alert.describe(), unit.id])
		_return_to_bar(relieved, float(GameData.balance["relieved_cooldown"]))

	var incident: Dictionary = GameData.incidents[alert.incident_id]
	unit.outcome = _match_for(unit.type, incident)
	alert.assigned = true
	alert.locked_phase = alert.phase
	unit.alert = alert
	_log("DISPATCH %s -> %s (match: %s)" % [unit.id, alert.describe(), unit.outcome])
	EventBus.unit_dispatched.emit(unit, alert)
	var eta := eta_for(unit, alert)
	unit.travel_total = eta
	_set_leg(unit, unit.location, alert.sector_id, 0.0, eta)
	EventBus.radio_event.emit("dispatch", unit, alert)
	_set_status(unit, UnitState.Status.TRAVELING, eta)
	return true


## Idle unit of this type with the shortest trip to the alert, or null if none is free.
func best_unit_of_type(unit_type: String, alert: Alert) -> UnitState:
	var best: UnitState = null
	var best_eta := INF
	for unit in units:
		if unit.type != unit_type or unit.status != UnitState.Status.IDLE:
			continue
		var eta := eta_for(unit, alert)
		if eta < best_eta:
			best_eta = eta
			best = unit
	return best


## Seconds for `unit` to get from where it is now to the alert's sector.
func eta_for(unit: UnitState, alert: Alert) -> float:
	return travel_time(unit, unit.location, alert.sector_id, alert.incident_id)


## (distance + arrival penalty + incident access delay) x unit speed x terrain multiplier at the destination.
func travel_time(unit: UnitState, from_sector: String, to_sector: String, incident_id: String = "") -> float:
	var distances: Dictionary = GameData.distances
	var base: float
	if from_sector == to_sector:
		base = float(distances["local_time"])
	else:
		base = _sector_distance(from_sector, to_sector)
	base += float(distances["arrival_penalty"].get(to_sector, 0.0))
	if incident_id != "":
		base += float(GameData.incidents[incident_id].get("access_delay", 0.0))
	var type_data: Dictionary = GameData.unit_types[unit.type]
	var terrain: float = float(type_data["terrain_mult"].get(to_sector, 1.0))
	return base * float(type_data["speed_mult"]) * terrain


func _sector_distance(a: String, b: String) -> float:
	var matrix: Dictionary = GameData.distances["matrix"]
	if matrix.has(a) and matrix[a].has(b):
		return float(matrix[a][b])
	return float(matrix[b][a])


## The unit currently assigned to this alert, or null.
func responder_for(alert: Alert) -> UnitState:
	return _unit_for(alert)


func _set_leg(unit: UnitState, from_sector: String, to_sector: String, t0: float, time: float) -> void:
	unit.leg_from = from_sector
	unit.leg_to = to_sector
	unit.leg_t0 = t0
	unit.leg_time = time


func _unit_for(alert: Alert) -> UnitState:
	for unit in units:
		if unit.alert == alert:
			return unit
	return null


# ---------------------------------------------------------------- alerts

func _tick_alerts(delta: float) -> void:
	for alert in alerts.duplicate():
		if alert.assigned:
			# The clock keeps running while the unit is still on the road, and stops once it is on site.
			var responder := _unit_for(alert)
			if responder == null or responder.status != UnitState.Status.TRAVELING:
				continue
		if alert.tick(delta):
			_log("PHASE %s" % alert.describe())
			EventBus.alert_phase_changed.emit(alert)
		if alert.time_left <= 0.0:
			_expire(alert)
			if GameState.state != GameState.State.PLAYING:
				return


func _expire(alert: Alert) -> void:
	var sector: Dictionary = GameData.sectors[alert.sector_id]
	var penalty := float(GameData.balance["expiry_penalty"]) * float(sector["penalty_multiplier"]) * penalty_scale()
	var responder := _unit_for(alert)
	if responder != null:
		# Too late: the unit is called back to the team bar and cools down there.
		EventBus.radio_event.emit("recall", responder, alert)
		responder.alert = null
		_log("RECALL %s, was %.1fs from %s" % [responder.id, responder.timer, alert.describe()])
		_return_to_bar(responder)
	alerts.erase(alert)
	EventBus.radio_event.emit("expired", null, alert)
	_log("EXPIRED %s  trust -%.1f" % [alert.describe(), penalty])
	EventBus.alert_expired.emit(alert)
	GameState.change_trust(-penalty)


# ---------------------------------------------------------------- spawner

## Threat level: one step per entry of difficulty.level_times passed (falls back to every step_seconds).
func _tick_difficulty() -> void:
	var settings: Dictionary = GameData.balance["difficulty"]
	var level := 0
	if settings.has("level_times"):
		for i in (settings["level_times"] as Array).size():
			if GameState.survival_time >= float(settings["level_times"][i]):
				level = i
	else:
		level = int(GameState.survival_time / float(settings["step_seconds"]))
	if level > difficulty_level:
		difficulty_level = level
		EventBus.difficulty_changed.emit(level)
		EventBus.radio_event.emit("escalate", null, null)


func _tick_spawner(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _current_interval()
	if alerts.size() < _max_alerts():
		_spawn_alert()


## The pace-table row that applies now (from the rescue minute on, one per 3-minute stage), or {} before it.
func _pace() -> Dictionary:
	var current: Dictionary = {}
	for row: Dictionary in GameData.balance["pace"]:
		if GameState.survival_time >= float(row["from"]):
			current = row
	return current


func relief_active() -> bool:
	return GameState.survival_time < _relief_until


## Rescue window: from `lead` seconds before the stranded team appears until it is saved or lost, the
## map is kept quiet (see rescue.max_other_alerts).
func _rescue_window() -> bool:
	if not rescues.is_empty():
		return true
	var settings: Dictionary = GameData.balance["rescue"]
	return not _rescue_done and GameState.survival_time >= float(settings["first_at"]) - float(settings["lead"])


func _current_interval() -> float:
	var pace := _pace()
	var interval: float
	if pace.is_empty():
		var spawn: Dictionary = GameData.balance["spawn"]
		var boost: Dictionary = GameData.balance["intensity"]
		interval = float(spawn["interval_start"]) * pow(float(GameData.balance["difficulty"]["spawn_interval_mult"]), difficulty_level)
		if GameState.survival_time < float(boost["early_until"]):
			interval /= float(boost["early_boost"])
		interval = maxf(float(spawn["interval_min"]), interval)
	else:
		interval = float(pace["interval"])
	if relief_active():
		interval *= float(GameData.balance["relief"]["interval_mult"])
	return interval * _rng.randf_range(0.8, 1.2)


func _max_alerts() -> int:
	var spawn: Dictionary = GameData.balance["spawn"]
	var pace := _pace()
	var cap: int
	if pace.is_empty():
		cap = int(spawn["max_alerts_start"]) + difficulty_level * int(GameData.balance["difficulty"]["alerts_per_level"])
	else:
		cap = int(pace["max_alerts"])
	cap = mini(cap, int(spawn["max_alerts_cap"]))
	if _rescue_window():
		cap = mini(cap, int(GameData.balance["rescue"]["max_other_alerts"]))
	return cap


## Threat level used for the feed speed and the music.
func intensity_level() -> int:
	return difficulty_level


## Trust penalties grow with the threat level (1.0 at level 0).
func penalty_scale() -> float:
	return 1.0 + float(GameData.balance["difficulty"]["penalty_growth"]) * difficulty_level


## Watches for a fast trust crash after the rescue minute: then the next alerts are all Green for a while.
func _on_trust_changed(value: float) -> void:
	var settings: Dictionary = GameData.balance["relief"]
	var now := GameState.survival_time
	_trust_log.append([now, value])
	while not _trust_log.is_empty() and now - float(_trust_log[0][0]) > float(settings["window"]):
		_trust_log.pop_front()
	var peak := value
	for sample in _trust_log:
		peak = maxf(peak, float(sample[1]))
	if _pace().is_empty() or relief_active():
		return
	if peak - value >= float(settings["drop"]):
		_relief_until = now + float(settings["duration"])
		_log("RELIEF until %.0f (trust fell %.0f in %.0fs)" % [_relief_until, peak - value, float(settings["window"])])


## Chance that a spawn tick brings a casualty event: very rare early, 16% by minute 8, then rising.
func casualty_chance() -> float:
	var settings: Dictionary = GameData.balance["casualty"]
	var t := GameState.survival_time
	var peak_at := float(settings["peak_at"])
	var peak := float(settings["peak_chance"])
	if t <= peak_at:
		return peak * pow(t / peak_at, 2.0)
	return minf(float(settings["cap"]), peak + float(settings["growth_per_minute"]) * (t - peak_at) / 60.0)


# ---------------------------------------------------------------- third-party rescues

## The only team type that can reach the stranded team.
func rescue_team_type() -> String:
	return str(GameData.balance["rescue"]["only_type"])


func get_rescue(rescue_id: int) -> Dictionary:
	for rescue in rescues:
		if int(rescue["id"]) == rescue_id:
			return rescue
	return {}


## Ready team of this type with the shortest trip to a sector, or null.
func best_unit_for_sector(unit_type: String, sector_id: String) -> UnitState:
	var best: UnitState = null
	var best_eta := INF
	for unit in units:
		if unit.type != unit_type or unit.status != UnitState.Status.IDLE:
			continue
		var eta := travel_time(unit, unit.location, sector_id)
		if eta < best_eta:
			best_eta = eta
			best = unit
	return best


func _tick_rescues(delta: float) -> void:
	if not _rescue_done and GameState.survival_time >= _rescue_next_at and not reserves.is_empty():
		_rescue_done = true
		_spawn_rescue()
	for rescue in rescues.duplicate():
		rescue["time_left"] = maxf(0.0, float(rescue["time_left"]) - delta)
		if float(rescue["time_left"]) <= 0.0:
			_expire_rescue(rescue)
			if GameState.state != GameState.State.PLAYING:
				return


func _spawn_rescue() -> void:
	var settings: Dictionary = GameData.balance["rescue"]
	var reserve: Dictionary = reserves.pick_random()
	# The relief team was sent for the missile casualties and got buried by debris at the impact site.
	var sector_id: String = missile_sector if missile_sector != "" else GameData.sector_order.pick_random()
	var rescue := {
		"id": _next_rescue_id,
		"sector": sector_id,
		"reserve": reserve,
		"time_left": float(settings["time"]),
		"total": float(settings["time"]),
		"unit": "",
	}
	_next_rescue_id += 1
	rescues.append(rescue)
	_log("RESCUE spawned %s in %s" % [reserve["id"], sector_id])
	EventBus.rescue_spawned.emit(rescue)
	var place := str(GameData.sectors[sector_id]["name"]).to_upper()
	if missile_sector != "":
		EventBus.comms_message.emit("CENTRAL: %s was sent from the next county for the missile casualties. Their convoy is buried under debris @ %s." % [str(reserve["callsign"]), place], Color(1.0, 0.7, 0.2))
	EventBus.comms_message.emit("%s DOWN @ %s. %s ONLY." % [str(reserve["callsign"]), place, str(GameData.unit_types[rescue_team_type()]["name"]).to_upper()], Color(1.0, 0.7, 0.2))
	EventBus.banner_requested.emit("TEAM IN TROUBLE")


## Sends a ready or standby team to a stranded third-party team.
func dispatch_rescue(unit_id: String, rescue_id: int) -> bool:
	var unit := get_unit(unit_id)
	var rescue := get_rescue(rescue_id)
	if unit == null or rescue.is_empty() or not can_dispatch(unit) or str(rescue["unit"]) != "":
		return false
	if unit.type != rescue_team_type():
		return false
	rescue["unit"] = unit.id
	unit.rescue_id = rescue_id
	unit.alert = null
	unit.outcome = "perfect"
	var eta := travel_time(unit, unit.location, str(rescue["sector"]))
	unit.travel_total = eta
	_set_leg(unit, unit.location, str(rescue["sector"]), 0.0, eta)
	_set_status(unit, UnitState.Status.TRAVELING, eta)
	EventBus.sfx_requested.emit("deploy_chime")
	EventBus.comms_message.emit("%s EN ROUTE TO %s." % [unit.callsign, str(rescue["reserve"]["callsign"])], Color(0.55, 0.95, 0.75))
	EventBus.rescue_dispatched.emit(unit, rescue)
	return true


func _arrive_rescue(unit: UnitState) -> void:
	var rescue := get_rescue(unit.rescue_id)
	unit.rescue_id = 0
	unit.location = unit.leg_to
	if rescue.is_empty():
		_return_to_bar(unit)
		return
	rescues.erase(rescue)
	var entry: Dictionary = rescue["reserve"]
	reserves = reserves.filter(func(r: Dictionary) -> bool: return r["id"] != entry["id"])
	var fresh := UnitState.new(str(entry["id"]), str(entry["type"]), str(entry["depot"]), str(entry["callsign"]))
	units.append(fresh)
	var reward := float(GameData.balance["rescue"]["reward"])
	_log("RESCUED %s by %s  trust +%.1f" % [fresh.id, unit.id, reward])
	EventBus.comms_message.emit("%s SAVED. THEY JOIN YOUR TEAMS. +%d TRUST" % [fresh.callsign, int(reward)], C_GOOD)
	EventBus.rescue_gone.emit(rescue, "saved")
	EventBus.unit_unlocked.emit(fresh)
	_enter_standby(unit)
	GameState.change_trust(reward)


func _expire_rescue(rescue: Dictionary) -> void:
	rescues.erase(rescue)
	var sector: Dictionary = GameData.sectors[str(rescue["sector"])]
	var penalty := float(GameData.balance["expiry_penalty"]) * float(sector["penalty_multiplier"]) * penalty_scale()
	var unit := get_unit(str(rescue["unit"]))
	if unit != null and unit.rescue_id == int(rescue["id"]):
		unit.rescue_id = 0
		_return_to_bar(unit)
	_log("RESCUE LOST %s  trust -%.1f" % [rescue["reserve"]["id"], penalty])
	EventBus.comms_message.emit("%s LOST. TOO LATE." % str(rescue["reserve"]["callsign"]), C_BAD)
	EventBus.sfx_requested.emit("expire_sting")
	EventBus.rescue_gone.emit(rescue, "lost")
	GameState.change_trust(-penalty)


# ---------------------------------------------------------------- missile event

## Once per shift at missile.at: picks the district hit at once and the target of the second missile.
## The missile overlay (scripts/ui/missile_event.gd) runs the scene and reports back below.
func _tick_missile() -> void:
	if _missile_done or GameState.survival_time < float(GameData.balance["missile"]["at"]):
		return
	_missile_done = true
	var first: String = GameData.sector_order.pick_random()
	var second: String = GameData.sector_order.filter(func(s: String) -> bool: return s != first).pick_random()
	missile_sector = first
	_log("MISSILE EVENT first %s, second %s" % [first, second])
	EventBus.missile_event_started.emit(first, second)


## The unavoidable first strike: scorch mark and a fire in that district, no trust loss (nobody could stop it).
func missile_first_impact(sector_id: String) -> void:
	craters.append(sector_id)
	var settings: Dictionary = GameData.balance["missile"]
	var alert := Alert.new(_next_alert_id, str(settings.get("first_incident", "wildfire")), sector_id, float(GameData.balance["yellow_at"]))
	_next_alert_id += 1
	alerts.append(alert)
	EventBus.alert_spawned.emit(alert)


## The override console is over: the second missile was shot down, or it hit `sector_id`.
func missile_result(sector_id: String, intercepted: bool) -> void:
	var settings: Dictionary = GameData.balance["missile"]
	var place := str(GameData.sectors[sector_id]["name"]).to_upper()
	if intercepted:
		_log("MISSILE intercepted")
		EventBus.comms_message.emit("COUNTER-DEFENSE RESTORED. Second missile down over %s. +%d TRUST" % [place, int(settings["reward"])], C_GOOD)
		GameState.change_trust(float(settings["reward"]))
		return
	_log("MISSILE hit %s" % sector_id)
	craters.append(sector_id)
	var picks: Array = (settings["hit_incidents"] as Array).duplicate()
	picks.shuffle()
	for i in mini(int(settings["hit_alerts"]), picks.size()):
		var alert := Alert.new(_next_alert_id, str(picks[i]), sector_id, float(GameData.balance["red_at"]))
		_next_alert_id += 1
		alerts.append(alert)
		EventBus.alert_spawned.emit(alert)
	EventBus.comms_message.emit("SECOND MISSILE HIT %s. Fires and collapses reported. -%d TRUST" % [place, int(settings["hit_trust"])], C_BAD)
	GameState.change_trust(-float(settings["hit_trust"]))


# ---------------------------------------------------------------- casualties

func _spawn_casualty(at_sector: String = "") -> void:
	var settings: Dictionary = GameData.balance["casualty"]
	var sector_id: String = at_sector if at_sector != "" else GameData.sector_order.pick_random()
	var answer := "hospital" if _rng.randf() < 0.5 else "alt"
	var scenarios: Array = GameData.feed_content["casualty"][answer]
	var scenario: Array = scenarios.pick_random()
	var alt_name := str(GameData.sectors[casualty_alt[sector_id]]["name"])
	var count := _rng.randi_range(4, 18)
	var sector_name := str(GameData.sectors[sector_id]["name"]).to_upper()
	var reports: Array[Dictionary] = []
	var delays := [float(settings["first_report_delay"]), float(settings["second_report_delay"])]
	for i in scenario.size():
		var text := str(scenario[i]).replace("{n}", str(count)).replace("{alt}", alt_name)
		reports.append({"at": GameState.survival_time + float(delays[mini(i, delays.size() - 1)]), "text": "MEDIC @ %s: %s" % [sector_name, text]})
	var casualty := {
		"id": _next_casualty_id,
		"sector": sector_id,
		"alt": casualty_alt[sector_id],
		"answer": answer,
		"time_left": float(settings["time"]),
		"total": float(settings["time"]),
		"reports": reports,
	}
	_next_casualty_id += 1
	casualties.append(casualty)
	_log("CASUALTY %d at %s, answer %s" % [casualty["id"], sector_id, answer])
	EventBus.casualty_spawned.emit(casualty)
	EventBus.comms_message.emit("DISPATCH: Casualties reported in %s. Medics assessing, stand by." % sector_name, Color(0.45, 0.65, 1.0))


func _tick_casualties(delta: float) -> void:
	for casualty in casualties.duplicate():
		var reports: Array[Dictionary] = casualty["reports"]
		while not reports.is_empty() and float(reports[0]["at"]) <= GameState.survival_time:
			EventBus.comms_message.emit(str(reports.pop_front()["text"]), Color(0.55, 0.75, 1.0))
		casualty["time_left"] = float(casualty["time_left"]) - delta
		if float(casualty["time_left"]) <= 0.0:
			_finish_casualty(casualty, "expired")
			if GameState.state != GameState.State.PLAYING:
				return


func get_casualty(casualty_id: int) -> Dictionary:
	for casualty in casualties:
		if int(casualty["id"]) == casualty_id:
			return casualty
	return {}


## The player routes the injured: "hospital" or "alt". Right call earns trust, wrong one costs it.
func route_casualty(casualty_id: int, choice: String) -> void:
	var casualty := get_casualty(casualty_id)
	if casualty.is_empty():
		return
	_finish_casualty(casualty, "correct" if choice == casualty["answer"] else "wrong")


func _finish_casualty(casualty: Dictionary, result: String) -> void:
	var settings: Dictionary = GameData.balance["casualty"]
	casualties.erase(casualty)
	var sector_name := str(GameData.sectors[casualty["sector"]]["name"]).to_upper()
	var destination := "GENERAL HOSPITAL" if casualty["answer"] == "hospital" else "%s CLINIC" % str(GameData.sectors[casualty["alt"]]["name"]).to_upper()
	match result:
		"correct":
			EventBus.comms_message.emit("MEDIC @ %s: Patients arrived safely. Good call." % sector_name, C_GOOD)
		"wrong":
			EventBus.comms_message.emit("MEDIC @ %s: Wrong destination. They needed %s." % [sector_name, destination], C_BAD)
		_:
			EventBus.comms_message.emit("MEDIC @ %s: No routing order came. Patients waited too long." % sector_name, C_BAD)
	_log("CASUALTY %d %s" % [casualty["id"], result])
	EventBus.casualty_gone.emit(casualty, result)
	if result == "correct":
		GameState.change_trust(float(settings["reward"]))
	else:
		GameState.change_trust(-float(settings["penalty"]) * penalty_scale())


func _spawn_alert() -> void:
	var pick := _pick_incident_and_sector()
	if pick.is_empty():
		return
	var alert := Alert.new(_next_alert_id, pick["incident"], pick["sector"], _pick_start_time())
	_next_alert_id += 1
	alerts.append(alert)
	_log("SPAWNED %s" % alert.describe())
	EventBus.alert_spawned.emit(alert)


## Any incident can hit any sector, but sectors an incident is prone to are weighted higher.
func _pick_incident_and_sector() -> Dictionary:
	var spawn: Dictionary = GameData.balance["spawn"]
	var prone_mult := float(spawn["prone_weight_mult"])
	var entries: Array[Dictionary] = []
	var total := 0.0
	for incident_id: String in GameData.incidents:
		var incident: Dictionary = GameData.incidents[incident_id]
		if GameState.survival_time < float(incident["min_time"]):
			continue
		for sector_id: String in GameData.sector_order:
			var weight := float(incident["weight"])
			if sector_id in incident["prone"]:
				weight *= prone_mult
			entries.append({"incident": incident_id, "sector": sector_id, "weight": weight})
			total += weight
	if entries.is_empty():
		return {}
	var roll := _rng.randf() * total
	for entry in entries:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry
	return entries.back()


## Early game: always Green. Later, alerts can spawn straight into Yellow or Red; from the rescue minute
## the pace table sets the odds (mostly Yellow), unless trust is crashing: then everything is Green.
func _pick_start_time() -> float:
	if relief_active():
		return float(GameData.balance["green_start"])
	var spawn: Dictionary = GameData.balance["spawn"]
	var t := GameState.survival_time
	var pace := _pace()
	var red_chance: float
	var yellow_chance: float
	if pace.is_empty():
		red_chance = _ramp_chance(t, float(spawn["red_start_after"]), float(spawn["red_start_max_chance"]), float(spawn["chance_ramp_seconds"]))
		yellow_chance = _ramp_chance(t, float(spawn["yellow_start_after"]), float(spawn["yellow_start_max_chance"]), float(spawn["chance_ramp_seconds"]))
	else:
		red_chance = float(pace["red"])
		yellow_chance = float(pace["yellow"])
	var roll := _rng.randf()
	if roll < red_chance:
		return float(GameData.balance["red_at"])
	if roll < red_chance + yellow_chance:
		return float(GameData.balance["yellow_at"])
	return float(GameData.balance["green_start"])


func _ramp_chance(t: float, after: float, max_chance: float, ramp: float) -> float:
	return max_chance * clampf((t - after) / ramp, 0.0, 1.0)


# ---------------------------------------------------------------- units

func _tick_units(delta: float) -> void:
	for unit in units:
		if GameState.state != GameState.State.PLAYING:
			return
		match unit.status:
			UnitState.Status.IDLE:
				continue
			UnitState.Status.STRANDED:
				unit.timer -= delta
				if unit.timer <= 0.0:
					_enter_standby(unit)
			UnitState.Status.STANDBY:
				unit.timer -= delta
				if unit.timer <= 0.0:
					EventBus.radio_event.emit("standby_timeout", unit, null)
					_return_to_bar(unit)
			_:
				unit.timer -= delta
				if unit.timer <= 0.0:
					_advance(unit)


func _advance(unit: UnitState) -> void:
	match unit.status:
		UnitState.Status.TRAVELING:
			if unit.rescue_id != 0:
				_arrive_rescue(unit)
			else:
				_arrive(unit)
		UnitState.Status.WORKING:
			_resolve(unit, float(GameData.balance["semi_reward_mult"]))
		UnitState.Status.LOADING:
			var leg_time := _evac_leg_time(unit)
			_set_leg(unit, unit.alert.sector_id, str(GameData.balance["hospital_sector"]), 0.0, leg_time)
			_set_status(unit, UnitState.Status.TRANSPORTING, leg_time)
		UnitState.Status.TRANSPORTING:
			var mult := 1.0 if unit.outcome == "perfect" else float(GameData.balance["semi_reward_mult"])
			_resolve(unit, mult)
		UnitState.Status.RETURNING:
			unit.location = unit.home
			_set_status(unit, UnitState.Status.IDLE, 0.0)


func _arrive(unit: UnitState) -> void:
	unit.location = unit.alert.sector_id
	EventBus.radio_event.emit("arrive_" + unit.outcome, unit, unit.alert)
	var incident: Dictionary = GameData.incidents[unit.alert.incident_id]
	var is_evacuation: bool = incident.get("special", "") == "evacuation"
	var balance: Dictionary = GameData.balance
	_log("ARRIVE %s at %s (match: %s)" % [unit.id, unit.alert.describe(), unit.outcome])
	match unit.outcome:
		"perfect":
			if is_evacuation:
				_set_status(unit, UnitState.Status.LOADING, float(balance["evac_load_time"]))
			else:
				_resolve(unit, 1.0)
		"semi":
			if is_evacuation:
				_set_status(unit, UnitState.Status.LOADING, float(balance["evac_load_time"]))
			else:
				_set_status(unit, UnitState.Status.WORKING, float(balance["semi_work_time"]))
		_:
			# Wrong team: one trust hit. The alert is handed straight back (its clock runs again and
			# the right team can still be sent); the wrong team is stuck there for a while, then stands by.
			var alert := unit.alert
			var sector: Dictionary = GameData.sectors[alert.sector_id]
			alert.assigned = false
			unit.alert = null
			EventBus.alert_released.emit(alert)
			_set_status(unit, UnitState.Status.STRANDED, float(balance["stranded_retreat_time"]))
			GameState.change_trust(-float(balance["stranded_penalty"]) * float(sector["penalty_multiplier"]) * penalty_scale())


## Clears the alert, pays the reward (set by the phase when the unit was dispatched), sends the unit home.
func _resolve(unit: UnitState, reward_mult: float) -> void:
	var alert := unit.alert
	EventBus.radio_event.emit("done", unit, alert)
	var reward := float(GameData.balance["reward"][alert.locked_phase_name()]) * reward_mult
	var incident: Dictionary = GameData.incidents[alert.incident_id]
	var return_sector := alert.sector_id
	if incident.get("special", "") == "evacuation":
		return_sector = GameData.balance["hospital_sector"]

	alerts.erase(alert)
	unit.alert = null
	_log("RESOLVED %s by %s  trust +%.1f" % [alert.describe(), unit.id, reward])
	EventBus.alert_resolved.emit(alert, reward)
	unit.location = return_sector
	_enter_standby(unit)
	GameState.change_trust(reward)


## Job over: the unit waits where it is, on the map, ready to be redeployed from there.
func _enter_standby(unit: UnitState) -> void:
	_set_leg(unit, unit.location, unit.location, 1.0, 0.0)
	var standby := float(GameData.balance["standby_seconds"])
	_set_status(unit, UnitState.Status.STANDBY, standby)


## Back to the team bar at once (no drive), then a cooldown (the type's, unless one is given).
func _return_to_bar(unit: UnitState, cooldown: float = -1.0) -> void:
	unit.location = unit.home
	_set_leg(unit, unit.home, unit.home, 1.0, 0.0)
	if cooldown < 0.0:
		cooldown = float(GameData.unit_types[unit.type]["cooldown"])
	_set_status(unit, UnitState.Status.RETURNING, cooldown)


func _evac_leg_time(unit: UnitState) -> float:
	var balance: Dictionary = GameData.balance
	var from_index := int(GameData.sectors[unit.alert.sector_id]["map_index"])
	var hospital_index := int(GameData.sectors[balance["hospital_sector"]]["map_index"])
	var base := float(balance["evac_leg_base"]) + absi(from_index - hospital_index) * float(balance["evac_leg_per_step"])
	var time := base * float(GameData.unit_types[unit.type]["speed_mult"])
	if unit.outcome == "semi":
		time *= float(balance["semi_evac_time_mult"])
	return time


func _match_for(unit_type: String, incident: Dictionary) -> String:
	if unit_type == incident["perfect"]:
		return "perfect"
	if unit_type == incident["semi"]:
		return "semi"
	return "wrong"


func _set_status(unit: UnitState, status: UnitState.Status, timer: float) -> void:
	unit.status = status
	unit.timer = timer
	unit.status_total = timer
	_log("UNIT %s (%.1fs)" % [unit.describe(), timer])
	EventBus.unit_status_changed.emit(unit)


func _log(message: String) -> void:
	if GameData.balance.get("debug", false):
		print("[World] ", message)
