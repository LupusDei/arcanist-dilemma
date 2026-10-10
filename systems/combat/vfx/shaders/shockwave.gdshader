// Expanding shock ring. `progress` 0..1 grows and thins the ring.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// 1 below `a`, 0 above `b` (a < b): a falling smoothstep that is defined everywhere.
float fall(float a, float b, float x) { return 1.0 - smoothstep(a, b, x); }

uniform vec4 color : source_color = vec4(0.5, 0.85, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float progress = 0.0;
uniform bool billboard = false;

void vertex() {
	if (billboard) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radius = mix(0.15, 0.95, progress);
	float width = mix(0.22, 0.03, progress);
	float ring = fall(0.0, width, abs(r - radius));
	float inner_fill = fall(0.0, radius, r) * 0.25 * (1.0 - progress);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(ring + inner_fill, 0.0, 1.0) * (1.0 - progress * progress);
}
