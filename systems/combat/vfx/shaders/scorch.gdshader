// A burnt, faintly glowing mark left where a bolt hits the ground or a wall.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 1 below `a`, 0 above `b` (a < b): a falling smoothstep that is defined everywhere.
float fall(float a, float b, float x) { return 1.0 - smoothstep(a, b, x); }

uniform vec4 burn_color : source_color = vec4(0.05, 0.04, 0.06, 1.0);
uniform vec4 ember_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float heat = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x + 1e-5);
	float n = noise(vec2(a * 2.5 + seed, r * 3.0)) * 0.35 + noise(p * 6.0) * 0.25;
	float burn = fall(0.2, 0.85, r + n * 0.6);
	// Radial cracks that glow while hot.
	float cracks = smoothstep(0.92, 1.0, noise(vec2(a * 9.0 + seed, r * 1.5))) * fall(0.3, 0.9, r);
	vec3 col = mix(burn_color.rgb, ember_color.rgb * 4.0, clamp(cracks * heat + fall(0.0, 0.3, r) * heat * 0.8, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(burn * 0.8 + cracks * heat, 0.0, 1.0) * alpha;
}
