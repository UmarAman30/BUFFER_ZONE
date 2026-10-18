shader_type canvas_item;
// Monitor casing drawn around the game screen. Transparent inside the rounded screen opening
// (apart from a faint glass glare and an inner shadow); moulded dark plastic everywhere else.

uniform vec2 canvas_size = vec2(1920.0, 1080.0);
uniform vec4 screen_rect = vec4(67.0, 24.0, 1786.0, 1004.0); // x, y, w, h in pixels
uniform float radius = 22.0;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * canvas_size;
	vec2 center = screen_rect.xy + screen_rect.zw * 0.5;
	float d = rounded_box(p - center, screen_rect.zw * 0.5, radius);

	if (d < 0.0) {
		// Glass: inner shadow along the edge plus a faint diagonal glare.
		float shadow = smoothstep(-30.0, 0.0, d) * 0.6;
		vec2 uv = (p - screen_rect.xy) / screen_rect.zw;
		float t = uv.x + uv.y * 0.55 - 0.15;
		float glare = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.18, 0.42, t)) * 0.035;
		float a = clamp(shadow + glare, 0.0, 1.0);
		COLOR = vec4(vec3(glare / max(a, 0.001)), a);
	} else {
		// Plastic: vertical gradient, fine grain, a lit lip around the opening, darker outer edge.
		float g = 1.0 - UV.y * 0.35;
		vec3 base = vec3(0.105, 0.105, 0.115) * g;
		base += (hash(floor(p * 0.5)) - 0.5) * 0.012;
		float lip = 1.0 - smoothstep(0.0, 6.0, d);
		float lip_light = lip * (0.5 + 0.5 * clamp(-(p.y - center.y) / (screen_rect.w * 0.5), -1.0, 1.0));
		base += vec3(0.09) * lip_light;
		base *= 1.0 - (1.0 - smoothstep(2.0, 12.0, d)) * 0.35 * (1.0 - lip);
		vec2 edge = min(p, canvas_size - p);
		base *= 0.75 + 0.25 * smoothstep(0.0, 18.0, min(edge.x, edge.y));
		COLOR = vec4(base, 1.0);
	}
}
