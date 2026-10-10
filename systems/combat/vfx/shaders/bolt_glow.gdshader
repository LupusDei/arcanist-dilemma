// Camera-facing glow sprite for spell cores: a hot center, a colored halo and
// a flickering crackle ring. HDR colors feed the world's bloom.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 1 below `a`, 0 above `b` (a < b): a falling smoothstep that is defined everywhere.
float fall(float a, float b, float x) { return 1.0 - smoothstep(a, b, x); }

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform float intensity = 4.0;
uniform float core_size = 0.18;
uniform float flicker = 0.35;
uniform float alpha = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	// Billboard that keeps the node's scale.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x + 1e-5);
	float t = TIME * 9.0 + seed * 17.0;
	// Wobbly edge so the halo crackles instead of being a perfect disc.
	float n = noise(vec2(a * 3.0, t)) * 0.5 + noise(vec2(a * 7.0, t * 1.7)) * 0.5;
	float edge = 0.8 + (n - 0.5) * flicker * 0.35;
	float halo = fall(0.15, edge, r);
	float core = fall(core_size * 0.4, core_size + 0.08, r);
	float rim = smoothstep(edge - 0.1, edge - 0.02, r) * fall(edge - 0.02, edge + 0.04, r);
	vec3 col = glow_color.rgb * halo * 0.45 + rim_color.rgb * rim * 0.7 + core_color.rgb * core * 1.2;
	float pulse = 1.0 + (noise(vec2(t * 0.7, seed)) - 0.5) * flicker;
	ALBEDO = col * intensity * pulse;
	ALPHA = clamp(halo * halo * 0.8 + core + rim * 0.6, 0.0, 1.0) * alpha;
}
