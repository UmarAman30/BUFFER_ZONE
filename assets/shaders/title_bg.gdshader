shader_type canvas_item;
// Title screen backdrop: a dark tactical display. Drifting topographic contour lines (the city seen
// from above), a faint grid, a slow radar sweep with rings from the centre, a few contacts that flare
// as the sweep passes, rolling interference bands, grain and a vignette.

uniform float time_s = 0.0;
uniform vec2 aspect = vec2(1.7778, 1.0);
uniform vec3 tint = vec3(0.30, 0.95, 0.50);
uniform float boot = 1.0;      // 0..1 fades the whole display in
uniform float glitch = 0.0;    // 0..1 tears the picture during transitions

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	// Horizontal tearing while glitching.
	float band = step(0.92, hash(vec2(floor(uv.y * 40.0), floor(time_s * 18.0))));
	uv.x += glitch * band * (hash(vec2(floor(uv.y * 40.0), time_s)) - 0.5) * 0.12;
	vec2 p = (uv - 0.5) * aspect;
	vec3 col = vec3(0.008, 0.03, 0.018);

	// Topographic contours, slowly drifting.
	float h = fbm(p * 2.2 + vec2(time_s * 0.015, -time_s * 0.01));
	float iso = abs(fract(h * 9.0) - 0.5);
	float contour = smoothstep(0.035, 0.0, iso - 0.46);
	col += tint * contour * 0.10;
	col += tint * smoothstep(0.55, 0.85, h) * 0.035;

	// Grid.
	vec2 g = abs(fract(p * 12.0) - 0.5);
	float grid = smoothstep(0.485, 0.5, max(g.x, g.y));
	col += tint * grid * 0.045;

	// Radar: rings and a rotating sweep with a fading tail.
	float r = length(p);
	float ang = atan(p.y, p.x);
	float sweep = mod(ang - time_s * 0.9, 6.28318);
	float tail = exp(-sweep * 2.2) * smoothstep(0.95, 0.2, r);
	col += tint * tail * 0.16;
	float rings = smoothstep(0.004, 0.0, abs(fract(r * 5.0 + 0.5) - 0.5) - 0.0);
	col += tint * rings * 0.05 * smoothstep(1.0, 0.1, r);

	// Contacts that light up when the sweep passes over them.
	for (int i = 0; i < 7; i++) {
		vec2 c = vec2(hash(vec2(float(i), 1.3)) - 0.5, hash(vec2(float(i), 7.1)) - 0.5) * vec2(1.4, 0.8);
		float ca = atan(c.y, c.x);
		float since = mod(time_s * 0.9 - ca, 6.28318);
		float glow = exp(-since * 1.4);
		float d = length(p - c);
		col += vec3(1.0, 0.75, 0.25) * smoothstep(0.012, 0.0, d) * glow;
		col += vec3(1.0, 0.6, 0.2) * smoothstep(0.05, 0.0, d) * glow * 0.25;
	}

	// Rolling interference band and scanline shimmer.
	float roll = smoothstep(0.0, 0.08, abs(fract(uv.y - time_s * 0.07) - 0.5) - 0.42);
	col += tint * roll * 0.025;
	col *= 0.92 + 0.08 * sin(uv.y * 1080.0 * 3.14159);
	// Grain and flicker.
	col += (hash(uv * 900.0 + time_s) - 0.5) * 0.03;
	col *= 0.97 + 0.03 * sin(time_s * 50.0);
	// Vignette.
	col *= smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(1.25, 1.0)) * 1.4);
	col *= boot;
	col += vec3(0.6, 1.0, 0.7) * glitch * band * 0.15;
	COLOR = vec4(col, 1.0);
}
