shader_type spatial;
// Fitted stone blocks with mortar, for foundations, chimneys, wells and towers.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.62, 0.62, 0.6, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.42, 0.4, 0.38, 1.0);
uniform float block_height = 0.32;
uniform float roughness_amount = 1.0;

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec2 uv = planar_uv(model_position, model_normal);
	float row = floor(uv.y / block_height);
	float width = block_height * (1.4 + hash12(vec2(row, 7.0)) * 1.2);
	float x = uv.x / width + hash12(vec2(row, 2.0));
	float column = floor(x);
	vec2 local = vec2(fract(x), fract(uv.y / block_height));
	float id = hash12(vec2(row, column));
	vec2 edge = min(local, 1.0 - local) * vec2(width, block_height);
	float mortar = smoothstep(0.015, 0.04, min(edge.x, edge.y));
	float bulge = sqrt(clamp(min(edge.x, edge.y) / 0.08, 0.0, 1.0));
	float grit = fbm(uv * 9.0, 4);

	vec3 color = base_color.rgb * (0.8 + 0.35 * id) * (0.85 + 0.3 * grit);
	color = mix(mortar_color.rgb, color, mortar);
	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	NORMAL = bump_normal(NORMAL, VERTEX, (bulge * 0.025 + grit * 0.006) * mortar * roughness_amount, 1.0);
}
