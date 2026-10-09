shader_type spatial;
// Tree canopies. Sways above the trunk and takes a per-instance tint from the
// MultiMesh colour so neighbouring trees don't look identical.

uniform vec4 leaf_color : source_color = vec4(0.52, 0.64, 0.20, 1.0);
uniform float sway = 0.04;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.2 + origin.x * 0.21 + origin.z * 0.17;
	float k = max(VERTEX.y - 1.5, 0.0);
	VERTEX.x += sin(t) * sway * k;
	VERTEX.z += cos(t * 0.83) * sway * k * 0.7;
}

void fragment() {
	ALBEDO = leaf_color.rgb * tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = leaf_color.rgb * 0.3;
}
