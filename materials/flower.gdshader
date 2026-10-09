shader_type spatial;
render_mode cull_disabled;
// Wildflowers: green stem, head tinted by the MultiMesh instance colour.

uniform vec4 stem_color : source_color = vec4(0.32, 0.5, 0.12, 1.0);

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sway = sin(TIME * 1.8 + origin.x * 0.5 + origin.z * 0.4) * 0.05 * VERTEX.y / 0.32;
	VERTEX.x += sway;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = UV.y > 0.5 ? tint : stem_color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
