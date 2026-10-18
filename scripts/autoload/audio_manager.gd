extends Node
## Plays placeholder sound effects in response to EventBus signals. Drop replacement .wav/.ogg files
## with the same names into res://assets/audio/ and they are picked up with no code changes.
## Missing files are skipped silently.
##
## Tension system: an "intensity" value (0 calm .. 1 frantic) is computed from the threat level,
## unanswered red alerts, open alerts and lost trust. It fades in extra loop layers (pulses),
## raises the hum pitch, and makes the one-shot alarms louder.

const AUDIO_DIR := "res://assets/audio/"
const EXTENSIONS := ["wav", "ogg", "mp3"]
## Levels for the recorded sound set (assets/audio, sources in assets/audio_src): each is set so the
## sounds sit at a consistent loudness against each other. Unlisted sounds play at -6 dB.
const VOLUMES_DB := {
	"ui_click": -25.0,
	"key_clack": -5.0,
	"screen_switch": -4.0,
	"feed_open": -4.0,
	"feed_close": 0.0,
	"type_blip": -9.0,
	"static_burst": -18.0,
	"ambient_hum": -24.0,
	"radio_squelch": -14.0,
	"siren": -15.0,
	"radar_ping": -10.0,
	"deploy_chime": -11.0,
	"resolve_ding": -12.0,
	"alarm_green": -12.0,
	"alarm_yellow": -13.0,
	"alarm_red": -10.0,
	"expire_sting": -7.5,
	"failure_buzzer": -10.0,
	"feed_ping": -21.0,
	"klaxon": -15.0,
	"missile_whistle": -4.0,
	"missile_impact": -1.0,
	"intercept_launch": -6.0,
	"intercept_hit": -4.0,
	"countdown_tick": -14.0,
	"code_accept": -10.0,
}
## Sounds that get louder as intensity rises (extra dB at full intensity).
const TENSION_BOOST_DB := {
	"alarm_green": 2.0,
	"alarm_yellow": 4.0,
	"alarm_red": 5.0,
	"expire_sting": 5.0,
	"failure_buzzer": 5.0,
	"siren": 4.0,
}
const POOL_SIZE := 8
## Background music level (dB): calm .. full tension. It sits under the effects but stays present.
const MUSIC_CALM_DB := -7.0
const MUSIC_TENSE_DB := -10.0
## Cues the music briefly dips under (by MUSIC_DUCK_DB) so they always read clearly.
const DUCK_CUES := ["alarm_green", "alarm_yellow", "alarm_red", "expire_sting", "failure_buzzer",
	"deploy_chime", "resolve_ding", "feed_ping", "missile_whistle", "missile_impact", "intercept_launch",
	"intercept_hit", "code_accept"]
const MUSIC_DUCK_DB := 6.0
const SILENT_DB := -60.0
const RISE_PER_SECOND := 0.25
const FALL_PER_SECOND := 0.08

var intensity: float = 0.0
var _target: float = 0.0
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _pad: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _pulse_low: AudioStreamPlayer
var _pulse_high: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _layers_on: bool = false
var _music_fade: Tween
var _klaxon: AudioStreamPlayer
var _duck: float = 0.0   # 1 right after a key cue, fades back to 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps UI sounds working while the tutorial pauses the game
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_pad = _make_loop_player("bgm_dark_ambience")   # background music: Iwan Gabovitch, "Dark Ambience Loop"
	_hum = _make_loop_player("ambient_hum")
	_pulse_low = _make_loop_player("pulse_low")
	_pulse_high = _make_loop_player("pulse_high")
	_siren = _make_loop_player("siren")
	_klaxon = _make_loop_player("klaxon")

	EventBus.game_started.connect(_on_game_started)
	EventBus.game_over.connect(_on_game_over)
	EventBus.screen_requested.connect(func(_name: String) -> void: play("screen_switch"))
	EventBus.alert_revealed.connect(func(alert: Alert) -> void:
		if alert.phase == Alert.Phase.GREEN:
			play("radar_ping")
		else:
			_play_alarm(alert.phase))
	EventBus.alert_phase_changed.connect(func(alert: Alert) -> void:
		if alert.revealed:
			_play_alarm(alert.phase))
	EventBus.alert_expired.connect(func(_alert: Alert) -> void: play("expire_sting"))
	EventBus.alert_resolved.connect(func(_alert: Alert, _reward: float) -> void: play("resolve_ding"))
	EventBus.unit_dispatched.connect(func(_unit: UnitState, _alert: Alert) -> void: play("deploy_chime"))
	EventBus.unit_status_changed.connect(_on_unit_status_changed)
	EventBus.feed_entry_added.connect(_on_feed_entry)
	EventBus.sfx_requested.connect(play)
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	_duck = maxf(0.0, _duck - delta * 1.6)
	if GameState.state != GameState.State.PLAYING:
		return
	_target = _compute_target()
	if _target > intensity:
		intensity = minf(_target, intensity + RISE_PER_SECOND * delta)
	else:
		intensity = maxf(_target, intensity - FALL_PER_SECOND * delta)
	_apply_layers()
	_update_siren()


## 0..1 from how bad things currently are.
func _compute_target() -> float:
	var level_part := clampf(float(World.intensity_level()) / 6.0, 0.0, 1.0) * 0.45
	var reds := 0
	for alert in World.alerts:
		if not alert.assigned and alert.revealed and alert.phase == Alert.Phase.RED:
			reds += 1
	var red_part := clampf(float(reds) / 3.0, 0.0, 1.0) * 0.25
	var open_part := clampf(float(World.alerts.size()) / 8.0, 0.0, 1.0) * 0.15
	var trust_part := clampf(1.0 - GameState.trust / GameState.MAX_TRUST, 0.0, 1.0) * 0.25
	return clampf(level_part + red_part + open_part + trust_part, 0.0, 1.0)


func _apply_layers() -> void:
	var i := intensity
	if _pad != null:
		# Louder, present music; it eases down a little with tension and dips briefly under key cues.
		_pad.volume_db = lerpf(MUSIC_CALM_DB, MUSIC_TENSE_DB, i) - MUSIC_DUCK_DB * _duck
	if _hum != null:
		_hum.pitch_scale = 1.0 + 0.2 * i
		_hum.volume_db = float(VOLUMES_DB["ambient_hum"]) + 4.0 * i
	if _pulse_low != null:
		var low := clampf((i - 0.2) / 0.8, 0.0, 1.0)
		_pulse_low.volume_db = SILENT_DB if low <= 0.0 else lerpf(-28.0, -8.0, low)   # recorded heartbeat
	if _pulse_high != null:
		var high := clampf((i - 0.5) / 0.5, 0.0, 1.0)
		_pulse_high.volume_db = SILENT_DB if high <= 0.0 else lerpf(-32.0, -14.0, high)   # heart monitor


## The siren loops while any unanswered alert is in the red.
func _update_siren() -> void:
	if _siren == null or _siren.stream == null:
		return
	var wanted := false
	for alert in World.alerts:
		if not alert.assigned and alert.revealed and alert.phase == Alert.Phase.RED:
			wanted = true
			break
	_siren.volume_db = float(VOLUMES_DB["siren"]) + float(TENSION_BOOST_DB["siren"]) * intensity
	if wanted and not _siren.playing:
		_siren.play()
	elif not wanted and _siren.playing:
		_siren.stop()


func play(sound: String) -> void:
	var stream := _get_stream(sound)
	if stream == null:
		return
	if sound in DUCK_CUES:
		_duck = 1.0
	var volume := float(VOLUMES_DB.get(sound, -6.0))
	volume += float(TENSION_BOOST_DB.get(sound, 0.0)) * intensity
	for player in _players:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume
			player.play()
			return


## Missile event alarm: a looping two-tone klaxon (falls back to the siren loop if klaxon.wav is missing).
func set_klaxon(on: bool) -> void:
	var player := _klaxon if _klaxon != null and _klaxon.stream != null else _siren
	if player == null or player.stream == null:
		return
	if on and not player.playing:
		player.volume_db = float(VOLUMES_DB["klaxon"])
		player.play()
	elif not on and player.playing:
		player.stop()


func _get_stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var stream: AudioStream = null
	for ext: String in EXTENSIONS:
		var path := "%s%s.%s" % [AUDIO_DIR, sound, ext]
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	_streams[sound] = stream
	return stream


## Builds a player whose stream loops seamlessly (loop flags are set at runtime, so the imported
## files need no special import settings).
func _make_loop_player(sound: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = float(VOLUMES_DB.get(sound, -20.0))
	var stream := _get_stream(sound)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		@warning_ignore("integer_division")
		wav.loop_end = wav.data.size() / 2   # 16-bit mono
	elif stream != null and "loop" in stream:
		stream.set("loop", true)
	player.stream = stream
	add_child(player)
	return player


func _play_alarm(phase: int) -> void:
	match phase:
		Alert.Phase.GREEN:
			play("alarm_green")
		Alert.Phase.YELLOW:
			play("alarm_yellow")
		Alert.Phase.RED:
			play("alarm_red")


func _on_unit_status_changed(unit: UnitState) -> void:
	if unit.status == UnitState.Status.STRANDED:
		play("failure_buzzer")


func _on_feed_entry(entry: Dictionary) -> void:
	play("feed_ping" if _get_stream("feed_ping") != null else "type_blip")   # every new live feed line
	if entry.get("channel", "") == "audio":
		play("static_burst")


## Every button in the game gets a click sound without each script having to ask for one.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play("ui_click"))


func _on_game_started() -> void:
	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()   # a restart during the game-over fade keeps the music
	intensity = 0.0
	_target = 0.0
	_apply_layers()
	# Start every loop together so the pad and pulses stay in sync.
	for player in [_pad, _hum, _pulse_low, _pulse_high]:
		if player != null and player.stream != null:
			player.play()
	_layers_on = true


## Leaving a shift for the main menu: every game loop stops, the music fades out, no end sound.
func stop_shift_audio() -> void:
	if _pad != null and _pad.playing:
		_music_fade = create_tween()
		_music_fade.tween_property(_pad, "volume_db", -50.0, 0.8)
		_music_fade.tween_callback(_pad.stop)
	for player in [_hum, _pulse_low, _pulse_high, _siren, _klaxon]:
		if player != null:
			player.stop()
	_layers_on = false


func _on_game_over(_final_score: int) -> void:
	if _pad != null and _pad.playing:   # the music fades out instead of cutting off
		_music_fade = create_tween()
		_music_fade.tween_property(_pad, "volume_db", -50.0, 2.0)
		_music_fade.tween_callback(_pad.stop)
	for player in [_hum, _pulse_low, _pulse_high, _siren, _klaxon]:
		if player != null:
			player.stop()
	_layers_on = false
	# Surviving the shift is a celebration; only a lost shift gets the buzzer.
	play("code_accept" if GameState.victory else "failure_buzzer")
