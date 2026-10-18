extends Node
## Session state: Public Trust and the shift clock (which also drives difficulty). Lasting shift_length seconds wins.

enum State { MENU, PLAYING, GAME_OVER }

const MAX_TRUST := 100.0

var state: State = State.MENU
var trust: float = MAX_TRUST
var survival_time: float = 0.0
## True when the shift ended because the clock ran out (a win), false when trust hit zero.
var victory: bool = false
## Fear index 0-100, shown above the trust bar during and after the missile event.
var fear: float = 0.0
var fear_active: bool = false
var _fear_decay: float = 0.0   # per second, once the event is over

var _last_score_second: int = -1


func _ready() -> void:
	set_process(false)


func start_game() -> void:
	trust = MAX_TRUST
	survival_time = 0.0
	victory = false
	fear = 0.0
	fear_active = false
	_fear_decay = 0.0
	_last_score_second = -1
	state = State.PLAYING
	set_process(true)
	EventBus.game_started.emit()
	EventBus.trust_changed.emit(trust)
	EventBus.score_changed.emit(0)
	EventBus.fear_changed.emit(fear, fear_active)


## Length of a shift in seconds (balance.json "shift_length").
func shift_length() -> float:
	return float(GameData.balance.get("shift_length", 600.0))


func _process(delta: float) -> void:
	if fear_active and _fear_decay > 0.0:
		set_fear(fear - _fear_decay * delta)
		if fear <= 0.0:
			fear_active = false
			_fear_decay = 0.0
			EventBus.fear_changed.emit(0.0, false)
	survival_time += delta
	if survival_time >= shift_length():
		# The clock reaches the full shift (10:00 on the HUD) before the win is called.
		survival_time = shift_length()
		_last_score_second = int(survival_time)
		EventBus.score_changed.emit(_last_score_second)
		victory = true
		_end_game()
		return
	var whole_seconds := int(survival_time)
	if whole_seconds != _last_score_second:
		_last_score_second = whole_seconds
		EventBus.score_changed.emit(whole_seconds)


## Shows the fear bar (if hidden) and sets its value.
func set_fear(value: float) -> void:
	fear = clampf(value, 0.0, 100.0)
	fear_active = true
	EventBus.fear_changed.emit(fear, true)


func add_fear(amount: float) -> void:
	set_fear(fear + amount)


## The event is over: fear drains at `per_second` until the bar hides.
func release_fear(per_second: float) -> void:
	_fear_decay = per_second


## Positive amount restores trust, negative drains it. Hitting 0 ends the game.
func change_trust(amount: float) -> void:
	if state != State.PLAYING:
		return
	trust = clampf(trust + amount, 0.0, MAX_TRUST)
	EventBus.trust_changed.emit(trust)
	if trust <= 0.0:
		_end_game()


## Abandons the shift without a result (pause menu > MAIN MENU).
func abort() -> void:
	state = State.MENU
	set_process(false)


func _end_game() -> void:
	state = State.GAME_OVER
	set_process(false)
	EventBus.game_over.emit(roundi(survival_time) if victory else int(survival_time))
