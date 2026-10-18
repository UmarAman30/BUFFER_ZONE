extends Control

@onready var output_label = $MarginContainer/VBoxContainer/TerminalOutput
@onready var input_field = $MarginContainer/VBoxContainer/UserInputLine

enum State { NAME, SEX, READY }
var current_state = State.NAME

# Typewriter variables
var full_text_queue = ""
var is_typing = false
var char_delay = 0.02 # Speed of typewriter effect
var _typing_sound := AudioStreamPlayer.new()   # recorded keyboard loop while the terminal prints

func _ready() -> void:
	input_field.text_submitted.connect(_on_text_submitted)
	input_field.placeholder_text = Loc.upper(Loc.t("Type your response here...."))
	var typing: AudioStreamWAV = null
	if ResourceLoader.exists("res://assets/audio/intro_typing.wav"):
		typing = load("res://assets/audio/intro_typing.wav") as AudioStreamWAV
	if typing != null:
		typing.loop_mode = AudioStreamWAV.LOOP_FORWARD
		typing.loop_begin = 0
		@warning_ignore("integer_division")
		typing.loop_end = typing.data.size() / 2   # 16-bit mono
		_typing_sound.stream = typing
	_typing_sound.volume_db = -5.0
	add_child(_typing_sound)
	# The player's own keystrokes click like the terminal's keyboard.
	input_field.text_changed.connect(func(_text: String) -> void: AudioManager.play("key_clack"))
	
	# Initial prompt sequence
	queue_print(Loc.t("INITIALIZING EOC SECURE TERMINAL v1.04...\nCONNECTION ESTABLISHED.\n\n> What is your name, officer?"))

func _on_text_submitted(new_text: String) -> void:
	var cleaned_text = new_text.strip_edges()
	if cleaned_text.is_empty() or is_typing:
		return

	# Echo user input to screen
	output_label.text += "\n[color=#00ff00]> " + cleaned_text + "[/color]\n"
	input_field.clear()

	# Process input based on current state machine step
	match current_state:
		State.NAME:
			if cleaned_text.length() > 0:
				PlayerData.player_name = cleaned_text
				queue_print(Loc.t("\nIdentity confirmed: ") + PlayerData.player_name + Loc.t(".\n\nSECURITY CHECK:\nDo you think you're ready for deployment? (Y/N)"))
				current_state = State.READY
			else:
				queue_print(Loc.t("\n[color=#ff4444][ERROR: NAME CANNOT BE BLANK][/color]\n> What is your name, officer?"))
				
		State.SEX:
			var sex_input = cleaned_text.to_upper()
			var shown_sex: String = sex_input
			if Loc.is_turkish():   # E = erkek (male), K = kadin (female)
				sex_input = {"E": "M", "K": "F"}.get(sex_input, sex_input)
			if sex_input == "M" or sex_input == "F":
				PlayerData.player_sex = sex_input
				queue_print(Loc.t("\nSex recorded: ") + shown_sex + Loc.t(".\n\nSECURITY CHECK:\nDo you think you're ready for deployment? (Y/N)"))
				current_state = State.READY
			else:
				queue_print(Loc.t("\n[color=#ff4444][ERROR: INVALID INPUT. TYPE 'M' OR 'F' ONLY][/color]\n> What is your sex? (Enter M or F)"))
				
		State.READY:
			var ready_input = cleaned_text.to_upper()
			if ready_input in ["Y", "YES", "E", "EVET"]:
				queue_print(Loc.t("\n[color=#00ff00]DEPLOYMENT AUTHORIZED. DOWNLOADING SECTOR DATA...[/color]"))
				input_field.editable = false
				await get_tree().create_timer(1.8).timeout
				# Straight into the shift (briefing book first).
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			else:
				queue_print(Loc.t("\n[color=#ffaa00][WARNING: HESITATION NOTED IN PROFILE][/color]\nDo you think you're ready for deployment? (Y/N)"))

# Typewriter system to print text character by character
func queue_print(text_to_add: String) -> void:
	if Loc.is_turkish():
		text_to_add = Loc.upper_rich(text_to_add)   # the terminal font is all caps
	full_text_queue += text_to_add
	if not is_typing:
		_type_text()

func _type_text() -> void:
	is_typing = true
	input_field.editable = false # Lock input while text is printing
	if _typing_sound.stream != null and not _typing_sound.playing:
		_typing_sound.play(randf() * 4.0)   # start somewhere new in the loop each time
	
	while full_text_queue.length() > 0:
		var next_char = full_text_queue.left(1)
		full_text_queue = full_text_queue.substr(1)
		output_label.text += next_char
		
		# Pause briefly per character (skip spaces for speed)
		if next_char != " " and next_char != "\n":
			await get_tree().create_timer(char_delay).timeout
		else:
			await get_tree().create_timer(char_delay * 0.5).timeout
			
	is_typing = false
	_typing_sound.stop()
	input_field.editable = true
	input_field.grab_focus()
