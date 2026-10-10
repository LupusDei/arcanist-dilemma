// Trails and lightning ribbons. UV.x runs along the ribbon (0 head, 1 tail),
// UV.y across it. Vertex color alpha fades the tail.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 1 below `a`, 0 above `b` (a < b): a falling smoothstep that is defined everywhere.
float fall(float a, float b, float x) { return 1.0 - smoothstep(a, b, x); }

uniform vec4 inner_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float streaks = 1.0;
uniform float scroll = 6.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float core = fall(0.0, 0.45, across);
	float body = fall(0.2, 1.0, across);
	float n = noise(vec2(UV.x * 14.0 - TIME * scroll, UV.y * 3.0));
	float streak = mix(1.0, 0.55 + n * 0.9, streaks);
	vec3 col = mix(outer_color.rgb, inner_color.rgb, core);
	ALBEDO = col * intensity * streak;
	ALPHA = clamp(body * body * COLOR.a * streak * 0.9, 0.0, 1.0);
}
