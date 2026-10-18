shader_type canvas_item;
// Missile event: washes everything drawn behind it red (desaturated), with a pulsing red vignette and
// slow scan bands. Put it on a full-screen ColorRect; `amount` 0 = no effect, 1 = full red alert.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	vec3 red = vec3(lum * 1.35 + 0.06, lum * 0.22, lum * 0.2);
	float edge = smoothstep(0.3, 0.85, distance(UV, vec2(0.5)));
	float pulse = 0.7 + 0.3 * sin(time_s * 4.0);
	float bands = 0.035 * sin(UV.y * 30.0 - time_s * 5.0);
	vec3 col = mix(base, red, amount * 0.8);
	col += vec3(0.55, 0.0, 0.02) * edge * pulse * amount;
	col += vec3(bands, 0.0, 0.0) * amount;
	COLOR = vec4(col, 1.0);
}
