// Billboarded glowing dots for SparkParticles (one MultiMesh instance each).
// Instance color carries tint and fade; the instance scale is the dot size.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 2.4;

void vertex() {
	float s = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float body = 1.0 - smoothstep(0.2, 1.0, r);
	float hot = 1.0 - smoothstep(0.0, 0.35, r);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), hot * 0.6) * intensity;
	ALPHA = clamp(body * COLOR.a, 0.0, 1.0);
}
