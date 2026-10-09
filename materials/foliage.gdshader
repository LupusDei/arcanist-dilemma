shader_type spatial;
// Tree canopies and bushes. Leaves are drawn as clusters (cellular noise in
// model space, so each tree keeps its pattern), lighter at the top of each
// cluster and darker in the gaps, with a soft sway above the trunk and a
// per-instance tint from the MultiMesh colour.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 leaf_color : source_color = vec4(0.52, 0.64, 0.20, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.22, 0.36, 0.12, 1.0);
uniform float cluster_scale = 3.5;
uniform float sway = 0.04;
uniform float sway_start = 1.5;

varying vec3 tint;
varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	tint = COLOR.rgb;
	model_position = VERTEX;
	model_normal = NORMAL;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.2 + origin.x * 0.21 + origin.z * 0.17;
	float k = max(VERTEX.y - sway_start, 0.0);
	VERTEX.x += sin(t) * sway * k;
	VERTEX.z += cos(t * 0.83) * sway * k * 0.7;
}

void fragment() {
	vec2 uv = planar_uv(model_position * cluster_scale, model_normal);
	// Soft clumps of leaves from layered noise, with small leaf shapes inside.
	float clumps = fbm(uv * 0.6, 4);
	float lit = smoothstep(0.38, 0.68, clumps);
	vec3 leaves = cells(uv * 3.0);
	float leaf = smoothstep(0.75, 0.2, leaves.x) * (0.8 + 0.4 * leaves.z);
	lit *= 0.75 + 0.25 * leaf;
	float gap = (1.0 - smoothstep(0.25, 0.45, clumps)) * 0.5;
	vec3 clusters = vec3(0.0, 0.0, leaves.z);
	// Underside of the canopy sits in its own shade.
	float underside = smoothstep(0.2, -0.6, model_normal.y);
	vec3 color = mix(shadow_color.rgb, leaf_color.rgb * (0.9 + 0.25 * clusters.z), lit);
	color = mix(color, shadow_color.rgb * 0.85, max(gap, underside * 0.5));
	ALBEDO = color * tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = leaf_color.rgb * 0.3;
	NORMAL = bump_normal(NORMAL, VERTEX, clumps * 0.25 + leaf * 0.015, 1.0);
}
