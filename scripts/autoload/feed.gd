extends Node
## Builds the data feed. Each alert drips clues into the channels as it ages:
##   spawn  : a sensor reading of the symptom (smoke, shaking, outage...), shared by several disasters
##   Green  : a vague call, also symptom-level
##   Yellow : a radio field report naming a landmark in the district
##   Red    : a confirming call, and usually a TRENDING group opinion on social (many posters, reliable)
## Single social posts are unreliable: they carry the false flags (right hazard in the wrong sector,
## or the wrong hazard in the right sector). Every channel also gets unrelated noise. Timings and odds live in balance.json
## under "feed", and all text lives in feed_content.json. The UI only reads this state.

const CHANNELS: Array[String] = ["audio", "sensor", "radio", "social"]
const MAX_PER_CHANNEL := 80
const RELIABILITY := {
	"sensor": "true",
	"call_vague": "vague",
	"call_confirm": "true",
	"radio": "true",
	"trend": "true",
	"social": "exaggerated",
}

var entries: Dictionary = {}   # channel -> Array of entry dictionaries
var unread: Dictionary = {}    # channel -> unread count
var viewing: String = ""       # channel on screen right now ("" when the feed screen is hidden)

var _pending: Array[Dictionary] = []   # [{due, entry}] entries waiting for their delay
var _sensor_ids: Dictionary = {}       # alert id -> sensor id text
var _landmarks: Dictionary = {}        # alert id -> the landmark every clue for that alert names
var _used: Dictionary = {}             # alert id -> templates already used
var _rumor_timer: float = 0.0
var _outbox: Array[Dictionary] = []   # entries waiting their turn; released one at a time (balance feed.min_gap)
var _gap_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Awareness stats for the end-of-shift report card (see shift_report.gd).
var stats: Dictionary = {}
var _rumors: Array[Dictionary] = []   # published false flags: the feed entry plus what it claims


func _ready() -> void:
	_rng.randomize()
	_reset()
	set_process(false)
	EventBus.game_started.connect(_on_game_started)
	EventBus.game_over.connect(func(_score: int) -> void: set_process(false))
	EventBus.alert_spawned.connect(_on_alert_spawned)
	EventBus.alert_phase_changed.connect(_on_phase_changed)
	EventBus.unit_dispatched.connect(_on_dispatched)
	EventBus.alert_expired.connect(_purge_alert)
	EventBus.alert_resolved.connect(func(alert: Alert, _reward: float) -> void: _purge_alert(alert))


func _reset() -> void:
	entries = {}
	unread = {}
	for channel in CHANNELS:
		entries[channel] = []
		unread[channel] = 0
	_pending.clear()
	_outbox.clear()
	_gap_timer = 0.0
	_sensor_ids.clear()
	_landmarks.clear()
	_used.clear()
	_rumors.clear()
	stats = {"rumors_seen": 0, "rumors_followed": 0, "reports_read": 0, "dispatches": 0, "informed": 0}


## Gap between released feed entries; shrinks as the difficulty level climbs.
func _current_gap() -> float:
	var diff: Dictionary = GameData.balance["difficulty"]
	var gap := float(GameData.balance["feed"]["min_gap"]) * pow(float(diff["feed_gap_mult"]), World.intensity_level())
	return maxf(float(diff["feed_gap_min"]), gap)


func _on_game_started() -> void:
	_reset()
	_rumor_timer = 6.0
	set_process(true)
	EventBus.feed_read.emit()


func _process(delta: float) -> void:
	if GameState.state != GameState.State.PLAYING:
		return
	var now := GameState.survival_time
	for item in _pending.duplicate():
		if item["due"] <= now:
			_pending.erase(item)
			_emit(item["entry"])
	_gap_timer -= delta
	if _gap_timer <= 0.0 and not _outbox.is_empty():
		_publish(_take_next())
		_gap_timer = _current_gap()
	_rumor_timer -= delta
	if _rumor_timer <= 0.0:
		_rumor_timer = _rumor_interval()
		_post_rumor()


# ---------------------------------------------------------------- public API (used by UI)

func unread_total() -> int:
	var total := 0
	for channel in CHANNELS:
		total += int(unread.get(channel, 0))
	return total


## The UI calls this with the channel it is showing, or "" when it leaves the feed screen.
func set_viewing(channel: String) -> void:
	viewing = channel
	if channel != "":
		unread[channel] = 0
	EventBus.feed_read.emit()


# ---------------------------------------------------------------- alert hooks

func _on_alert_spawned(alert: Alert) -> void:
	_sensor_ids[alert.id] = "SEN-%s%02d" % [alert.sector_id, _rng.randi_range(1, 19)]
	_landmarks[alert.id] = _landmark_for(alert.sector_id, alert.incident_id)
	_queue(alert, "sensor", "sensor", 0.0)
	_unlock_tier(alert)


func _on_phase_changed(alert: Alert) -> void:
	_unlock_tier(alert)


func _unlock_tier(alert: Alert) -> void:
	if alert.assigned:
		return   # a unit is already on it; no new clues
	var feed: Dictionary = GameData.balance["feed"]
	match alert.phase:
		Alert.Phase.GREEN:
			_queue(alert, "audio", "call_vague", float(feed["call_vague_delay"]))
		Alert.Phase.YELLOW:
			_queue(alert, "radio", "radio", float(feed["radio_delay"]))
		Alert.Phase.RED:
			_queue(alert, "audio", "call_confirm", float(feed["confirm_delay"]))
			if _rng.randf() < float(feed["trend_chance"]):
				_queue(alert, "social", "trend", float(feed["trend_delay"]))


## A unit was sent: no more clues arrive for this alert (the ones already shown stay until it is over).
func _on_dispatched(unit: UnitState, alert: Alert) -> void:
	_record_dispatch(unit, alert)
	_forget_alert(alert)


## The alert is over (solved or expired): all its clues leave the feed (noise and rumors stay).
func _purge_alert(alert: Alert) -> void:
	_forget_alert(alert)
	for channel in CHANNELS:
		var kept: Array = []
		for entry: Dictionary in entries[channel]:
			if int(entry["alert_id"]) != alert.id:
				kept.append(entry)
		entries[channel] = kept
	EventBus.feed_cleared.emit(alert.id)


func _forget_alert(alert: Alert) -> void:
	for i in range(_outbox.size() - 1, -1, -1):
		if int(_outbox[i]["alert_id"]) == alert.id:
			_outbox.remove_at(i)
	for i in range(_pending.size() - 1, -1, -1):
		if _pending[i]["entry"]["alert_id"] == alert.id:
			_pending.remove_at(i)
	_sensor_ids.erase(alert.id)
	_landmarks.erase(alert.id)
	_used.erase(alert.id)


# ---------------------------------------------------------------- entry building

func _queue(alert: Alert, channel: String, pool_key: String, delay: float) -> void:
	var item: Variant = _pick_item(alert, pool_key)
	if item == null:
		return
	var entry := {
		"channel": channel,
		"alert_id": alert.id,
		"sector": alert.sector_id,
		"reliability": RELIABILITY[pool_key],
		"icon": "",
		"text": "",
	}
	var line := _format(str(item), alert.sector_id, alert.id)
	if pool_key == "trend":
		# Many people saying the same thing: shown as one trending entry, and trustworthy.
		entry["trend_count"] = _rng.randi_range(14, 90)
		entry["text"] = "\"%s\"" % line
	elif channel == "social":
		line = "@%s  %s" % [_handle(), line]
		entry["text"] = line
	else:
		entry["text"] = line

	if delay <= 0.0:
		_emit(entry)
	else:
		_pending.append({"due": GameState.survival_time + delay, "entry": entry})


## Picks a random template from the incident's pool, avoiding repeats for the same alert.
## The first sensor reading and first call come from the incident's symptom group, which several
## disasters share, so they are a hint rather than an answer.
func _pick_item(alert: Alert, pool_key: String) -> Variant:
	var incident: Dictionary = GameData.incidents[alert.incident_id]
	var pool: Array = GameData.feed_content["incidents"][alert.incident_id].get(pool_key, [])
	if pool_key in ["sensor", "call_vague"] and incident.has("symptom"):
		var symptom_pools: Dictionary = GameData.feed_content.get("symptoms", {}).get(str(incident["symptom"]), {})
		if symptom_pools.has(pool_key):
			pool = symptom_pools[pool_key]
	if pool.is_empty():
		return null
	var used: Array = _used.get(alert.id, [])
	var fresh := pool.filter(func(candidate: Variant) -> bool: return not (candidate in used))
	var choice: Variant = fresh.pick_random() if not fresh.is_empty() else pool.pick_random()
	used.append(choice)
	_used[alert.id] = used
	return choice


## The landmark an alert is reported at: one whose risks include the incident if the district has one
## (so the feed can be matched against the district file), otherwise any landmark there.
func _landmark_for(sector_id: String, incident_id: String) -> String:
	var sector: Dictionary = GameData.sectors[sector_id]
	var landmarks: Array = sector.get("landmarks", [])
	if landmarks.is_empty():
		return str(sector["name"])
	var risks: Dictionary = sector.get("landmark_risks", {})
	var matching: Array = landmarks.filter(func(landmark: String) -> bool: return incident_id in risks.get(landmark, []))
	return str(matching.pick_random()) if not matching.is_empty() else str(landmarks.pick_random())


func _format(template: String, sector_id: String, alert_id: int, sensor_override: String = "") -> String:
	var sector: Dictionary = GameData.sectors[sector_id]
	var line := template.replace("{sector}", str(sector["name"])).replace("{sid}", sector_id)
	if line.contains("{landmark}"):
		var landmarks: Array = sector.get("landmarks", [])
		var landmark: String = _landmarks.get(alert_id, "")
		if landmark == "":
			landmark = str(landmarks.pick_random()) if not landmarks.is_empty() else str(sector["name"])
		if Loc.is_turkish():
			landmark = landmark.trim_prefix("the ")
		line = line.replace("{landmark}", landmark)
	var sensor_id := sensor_override if sensor_override != "" else str(_sensor_ids.get(alert_id, "SEN-%s01" % sector_id))
	line = line.replace("{sensor}", sensor_id)
	line = line.replace("{n1}", str(_rng.randi_range(20, 99)))
	line = line.replace("{n2}", str(_rng.randi_range(100, 899)))
	line = line.replace("{n3}", str(_rng.randi_range(2, 9)))
	return line


func _handle() -> String:
	return str(GameData.feed_content["handles"].pick_random())


## Everything goes through the outbox so the feed never dumps several lines at once.
func _emit(entry: Dictionary) -> void:
	if int(entry["alert_id"]) < 0:
		# Background chatter never piles up: if two are already waiting, the oldest is dropped.
		var waiting: Array[int] = []
		for i in _outbox.size():
			if int(_outbox[i]["alert_id"]) < 0:
				waiting.append(i)
		if waiting.size() >= 2:
			_outbox.remove_at(waiting[0])
	_outbox.append(entry)


## Clues about real alerts jump ahead of background chatter.
func _take_next() -> Dictionary:
	for i in _outbox.size():
		if int(_outbox[i]["alert_id"]) >= 0:
			var urgent: Dictionary = _outbox[i]
			_outbox.remove_at(i)
			return urgent
	return _outbox.pop_front()


func _publish(entry: Dictionary) -> void:
	entry["time"] = GameState.survival_time
	var channel: String = entry["channel"]
	var list: Array = entries[channel]
	list.append(entry)
	if list.size() > MAX_PER_CHANNEL:
		list.pop_front()
	if channel != viewing:
		unread[channel] = int(unread.get(channel, 0)) + 1
	if str(entry.get("reliability", "")) == "false":
		_rumors.append(entry)
	EventBus.feed_entry_added.emit(entry)


# ---------------------------------------------------------------- rumors and noise

func _rumor_interval() -> float:
	var feed: Dictionary = GameData.balance["feed"]
	var progress := clampf(GameState.survival_time / float(feed["rumor_ramp_seconds"]), 0.0, 1.0)
	var interval := lerpf(float(feed["rumor_interval_start"]), float(feed["rumor_interval_min"]), progress)
	return interval * _rng.randf_range(0.8, 1.2)


## Every tick is either a false flag about a live alert or harmless noise.
func _post_rumor() -> void:
	var live: Array[Alert] = World.alerts
	if not live.is_empty() and _rng.randf() < float(GameData.balance["feed"]["false_flag_chance"]):
		if _post_false_flag(live.pick_random()):
			return
	_post_noise()


func _post_false_flag(alert: Alert) -> bool:
	var incident_pools: Dictionary = GameData.feed_content["incidents"]
	var incident_id := alert.incident_id
	var sector_id := alert.sector_id
	if _rng.randf() < 0.5:
		# Right hazard, wrong sector.
		var other_sectors: Array = GameData.sector_order.filter(func(s: String) -> bool: return s != alert.sector_id)
		sector_id = other_sectors.pick_random()
	else:
		# Right sector, wrong hazard.
		var other_incidents: Array = incident_pools.keys().filter(func(i: String) -> bool: return i != alert.incident_id)
		incident_id = other_incidents.pick_random()
	var rumors: Array = incident_pools[incident_id].get("rumor", [])
	if rumors.is_empty():
		return false
	# The rumour names a landmark that fits the hazard it claims, so it looks plausible.
	_landmarks[-1] = _landmark_for(sector_id, incident_id)
	var rumor_text := _format(str(rumors.pick_random()), sector_id, -1)
	_landmarks.erase(-1)
	_emit({
		"channel": "social",
		"alert_id": -1,
		"sector": sector_id,
		"reliability": "false",
		"claims_sector": sector_id,
		"claims_type": str(GameData.incidents.get(incident_id, {}).get("perfect", "")),
		"icon": "",
		"text": "@%s  %s" % [_handle(), rumor_text],
	})
	return true


## Unrelated chatter in a weighted random channel: routine logs, nominal sensors, prank calls, small talk.
func _post_noise() -> void:
	var weights: Dictionary = GameData.balance["feed"]["noise_channel_weights"]
	var total := 0.0
	for channel: String in weights:
		total += float(weights[channel])
	var roll := _rng.randf() * total
	var chosen := "social"
	for channel: String in weights:
		roll -= float(weights[channel])
		if roll <= 0.0:
			chosen = channel
			break

	var pool: Array = GameData.feed_content["noise"].get(chosen, [])
	if pool.is_empty():
		return
	var sector_id: String = GameData.sector_order.pick_random()
	var sensor_id := "SEN-%s%02d" % [sector_id, _rng.randi_range(1, 19)]
	var line := _format(str(pool.pick_random()), sector_id, -1, sensor_id)
	if chosen == "social":
		line = "@%s  %s" % [_handle(), line]
	_emit({
		"channel": chosen,
		"alert_id": -1,
		"sector": sector_id,
		"reliability": "noise",
		"icon": "",
		"text": line,
	})


# ---------------------------------------------------------------- awareness stats

## The feed window is open: everything in it counts as read (rumors included).
func mark_all_seen() -> void:
	for channel in CHANNELS:
		for entry: Dictionary in entries[channel]:
			if not entry.get("seen", false):
				entry["seen"] = true
				if str(entry.get("reliability", "")) == "false":
					stats["rumors_seen"] = int(stats["rumors_seen"]) + 1


## Counts the alert's reports the player had read before this dispatch, and checks whether the
## dispatch looks like it followed a rumor: the wrong team, of the type a recent rumor called for,
## sent into the sector that rumor named.
func _record_dispatch(unit: UnitState, alert: Alert) -> void:
	var read := 0
	for channel in CHANNELS:
		for entry: Dictionary in entries[channel]:
			if int(entry["alert_id"]) == alert.id and entry.get("seen", false):
				read += 1
	stats["dispatches"] = int(stats["dispatches"]) + 1
	stats["reports_read"] = int(stats["reports_read"]) + read
	if read > 0:
		stats["informed"] = int(stats["informed"]) + 1
	var incident: Dictionary = GameData.incidents.get(alert.incident_id, {})
	if unit.type == str(incident.get("perfect", "")):
		return
	var window := float(GameData.balance["feed"].get("rumor_follow_window", 60.0))
	for rumor in _rumors:
		if rumor.get("followed", false) or not rumor.get("seen", false):
			continue
		if GameState.survival_time - float(rumor.get("time", 0.0)) > window:
			continue
		if str(rumor["claims_sector"]) == alert.sector_id and str(rumor["claims_type"]) == unit.type:
			rumor["followed"] = true
			stats["rumors_followed"] = int(stats["rumors_followed"]) + 1
			return
