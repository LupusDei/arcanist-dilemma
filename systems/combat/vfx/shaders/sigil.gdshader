// A rotating arcane circle: two rings, rune ticks and spokes. Lies flat on
// its quad; used at launch, on impact and around the charging hand.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 1 below `a`, 0 above `b` (a < b): a falling smoothstep that is defined everywhere.
float fall(float a, float b, float x) { return 1.0 - smoothstep(a, b, x); }

uniform vec4 color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(0.8, 0.5, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float alpha = 1.0;
uniform float spin = 1.5;
uniform float fill = 1.0;      // 0..1, how much of the outer ring is drawn (charge)
uniform float thickness = 1.0;
uniform bool billboard = false;

void vertex() {
	if (billboard) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	}
}

float ring(float r, float radius, float w) {
	return fall(0.0, w, abs(r - radius));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x + 1e-5);
	float w = 0.025 * thickness;
	float outer_a = a + TIME * spin;
	float swept = step(fract((outer_a / 6.28318) + 0.5), fill);
	float outer = ring(r, 0.92, w) * swept;
	float inner = ring(r, 0.62, w * 0.8);
	// Rune ticks between the rings, turning the other way.
	float ta = a - TIME * spin * 0.6;
	float ticks = step(0.55, fract(ta * 12.0 / 6.28318)) * step(fract(ta * 12.0 / 6.28318), 0.75);
	float tick_band = smoothstep(0.7, 0.72, r) * fall(0.84, 0.86, r) * ticks;
	// Small diamonds on the outer ring.
	float da = fract(outer_a * 6.0 / 6.28318) - 0.5;
	float diamonds = fall(0.0, 0.08, abs(da) * 0.9 + abs(r - 0.92) * 2.0) * swept;
	// Spokes of a triangle inside.
	float tri = 0.0;
	for (int i = 0; i < 3; i++) {
		float ang = float(i) * 2.0944 + TIME * spin * 0.3;
		vec2 dir = vec2(cos(ang), sin(ang));
		float d = abs(dot(p, vec2(-dir.y, dir.x)));
		tri += fall(0.0, w * 0.8, abs(d - 0.31)) * step(r, 0.62);
	}
	float m = clamp(outer + inner + tick_band * 0.8 + diamonds + tri * 0.6, 0.0, 1.0);
	vec3 col = mix(color.rgb, accent.rgb, clamp(tick_band + tri * 0.5, 0.0, 1.0));
	ALBEDO = col * intensity;
	ALPHA = m * alpha * fall(0.95, 1.0, r);
}
