shader_type canvas_item;
// Full-screen CRT overlay: scanlines, soft vignette and a faint flicker.
// Put it on a ColorRect that ignores the mouse and sits above everything.

uniform float line_count = 540.0;
uniform float line_strength = 0.16;
uniform float vignette_strength = 0.35;
uniform float flicker_strength = 0.02;

void fragment() {
	float scan = 0.5 + 0.5 * sin(UV.y * line_count * 3.14159265);
	float dark = line_strength * scan;
	float edge = distance(UV, vec2(0.5));
	dark += vignette_strength * smoothstep(0.35, 0.85, edge);
	dark += flicker_strength * (0.5 + 0.5 * sin(TIME * 60.0));
	COLOR = vec4(0.0, 0.0, 0.0, clamp(dark, 0.0, 0.8));
}
