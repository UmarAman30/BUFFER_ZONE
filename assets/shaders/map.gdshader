shader_type canvas_item;
// City map: water shimmer + drifting cloud shadows, plus the radar sweep and static that tie it to
// the game. The map stays fully visible; the sweep only brightens it as it passes.

uniform sampler2D water_mask : filter_linear;
uniform sampler2D cloud_noise : repeat_enable, filter_linear;
uniform float shimmer_strength = 0.18;
uniform float cloud_strength = 0.2;
uniform vec2 cloud_speed = vec2(0.006, 0.0025);
uniform float sweep_angle = 0.0;     // radians, screen space (0 = right, grows clockwise)
uniform float static_amount = 0.1;   // 0..1, grows as public trust falls

const float TAU_C = 6.28318530718;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 c = COLOR;
	float t = TIME;

	float w = texture(water_mask, UV).r;
	float a = sin(UV.x * 260.0 + t * 1.3 + sin(UV.y * 90.0 + t * 0.6) * 3.0);
	float b = sin(UV.y * 210.0 - t * 1.1 + sin(UV.x * 70.0 - t * 0.4) * 3.0);
	float s = smoothstep(0.6, 1.0, a * b);
	c.rgb *= 1.0 + w * s * shimmer_strength;

	vec2 cuv = UV * vec2(1.7778, 1.0) * 0.55 + t * cloud_speed;
	float n = texture(cloud_noise, cuv).r;
	c.rgb *= 1.0 - smoothstep(0.5, 0.78, n) * cloud_strength;

	// Radar sweep around the map centre (16:9 aspect so angles match the pin positions).
	vec2 d = (UV - 0.5) * vec2(16.0, 9.0);
	float ang = atan(d.y, d.x);
	float behind = mod(sweep_angle - ang, TAU_C);
	float trail = exp(-behind * 2.2);
	c.rgb *= 0.86 + 0.26 * trail;
	c.rgb += vec3(0.2, 1.0, 0.55) * (1.0 - smoothstep(0.0, 0.03, behind)) * 0.35;
	c.rgb += vec3(0.05, 0.3, 0.18) * trail * 0.12;

	// Static grain, heavier as trust falls.
	float grain = hash(floor(UV * vec2(640.0, 360.0)) + floor(t * 24.0));
	c.rgb += (grain - 0.5) * (0.02 + 0.26 * static_amount);

	// Soft edges so the map blends into the screen instead of ending in a hard rectangle.
	float edge_x = smoothstep(0.0, 0.045, min(UV.x, 1.0 - UV.x));
	float edge_y = smoothstep(0.0, 0.08, min(UV.y, 1.0 - UV.y));
	c.a *= edge_x * edge_y;

	COLOR = c;
}
