extends RefCounted
## Shared placeholder palette and style helpers. Swap these values when final art arrives.

const GREEN := Color(0.30, 0.95, 0.45)
const YELLOW := Color(1.0, 0.85, 0.20)
const RED := Color(1.0, 0.25, 0.25)
const TEXT := Color(0.55, 1.0, 0.65)
const DIM := Color(0.18, 0.32, 0.22)
const BG := Color(0.03, 0.08, 0.05)
const PANEL := Color(0.05, 0.14, 0.09)
const WHITE := Color(1.0, 1.0, 1.0)


## Loads a PNG as a texture. If the editor has not imported it yet, reads it straight from disk instead,
## so freshly added art shows up without waiting for an import. Returns null if the file is missing.
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var disk_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(disk_path):
		var image := Image.load_from_file(disk_path)
		if image != null:
			return ImageTexture.create_from_image(image)
	return null


static func phase_color(phase: int) -> Color:
	match phase:
		Alert.Phase.GREEN:
			return GREEN
		Alert.Phase.YELLOW:
			return YELLOW
		_:
			return RED


static func box(fill: Color, border: Color, border_width: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	return style


## Adds the console frame (bevel + corner brackets) over a panel. Returns it so callers can recolour it.
static func add_frame(parent: Control, accent: Color = TEXT) -> Control:
	var frame: Control = preload("res://scripts/ui/console_frame.gd").new()
	frame.accent = accent
	parent.add_child(frame)
	return frame


## District display name, e.g. "CRESTVIEW" (the A-E letters are internal only).
static func sector_name(sector_id: String) -> String:
	if GameData.sectors.has(sector_id):
		return str(GameData.sectors[sector_id]["name"]).to_upper()
	return "?"


const TEAM_COLORS := {
	"quick_deploy": Color(1.0, 0.85, 0.3),
	"earthquake": Color(1.0, 0.6, 0.25),
	"emf": Color(0.4, 0.75, 1.0),
}


## Shared look for every in-game text box: dark glass, thin border, generous even padding.
static func dialog_style(border: Color = TEXT, padding: float = 26.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BG, 0.97)
	style.border_color = Color(border, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.8
	style.content_margin_bottom = padding * 0.8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	return style


## Solid header strip used at the top of dialogs (title on a coloured bar).
static func header_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
