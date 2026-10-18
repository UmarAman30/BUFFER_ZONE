@warning_ignore_start("unused_signal")
extends Node
## Global signal hub. Systems talk through these instead of holding references to each other.

# Session
signal game_started
signal game_over(final_score: int)
signal trust_changed(value: float)
signal score_changed(seconds: int)
signal screen_requested(screen_name: String)
signal sfx_requested(sound: String)

# Alerts
signal alert_spawned(alert: Alert)
signal alert_revealed(alert: Alert)   # the radar sweep has passed over it; now visible on the scope
signal alert_phase_changed(alert: Alert)
signal alert_expired(alert: Alert)
signal alert_resolved(alert: Alert, reward: float)
signal alert_released(alert: Alert)

# Units
signal unit_dispatched(unit: UnitState, alert: Alert)
signal unit_status_changed(unit: UnitState)
# kind: dispatch, arrive_perfect, arrive_semi, arrive_wrong, done, retreat, recall, expired, ready
signal radio_event(kind: String, unit: UnitState, alert: Alert)

# Data feed
signal feed_entry_added(entry: Dictionary)
signal feed_read
signal feed_cleared(alert_id: int)   # an alert got a unit, so its clues leave the feed
signal difficulty_changed(level: int)
## Casualty events: a Dictionary {id, sector, alt, answer ("hospital"/"alt"), time_left, total}.
signal casualty_spawned(casualty: Dictionary)
## result: "correct", "wrong" or "expired".
signal casualty_gone(casualty: Dictionary, result: String)
## A line for the ECM (field comms): medic assessments and other non-unit reports.
signal comms_message(text: String, color: Color)
## Third-party team rescue events: a Dictionary {id, sector, reserve, time_left, total, unit}.
signal rescue_spawned(rescue: Dictionary)
signal rescue_dispatched(unit: UnitState, rescue: Dictionary)
## result: "saved" or "lost".
signal rescue_gone(rescue: Dictionary, result: String)
signal unit_unlocked(unit: UnitState)
## Big centre-screen text flash (e.g. SURGE).
signal banner_requested(text: String)
## Missile event (4:00): first = district hit at once, second = target of the missile the player must stop.
signal missile_event_started(first_sector: String, second_sector: String)
## Fear index (0-100) shown above the trust bar while `active`.
signal fear_changed(value: float, active: bool)
