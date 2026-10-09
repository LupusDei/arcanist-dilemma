shader_type spatial;
// Roof shingles. Model-space X runs down the slope (the kit orients both roof
// planes that way) and Z along the ridge.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.86, 0.43, 0.18, 1.0);
uniform float row_height = 0.32;
uniform float shingle_width = 0.42;
uniform float moss = 0.15;

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec3 color = base_color.rgb;
	float height = 0.0;
	if (abs(model_normal.y) > 0.5) {
		float row = floor(model_position.x / row_height);
		float t = fract(model_position.x / row_height);
		float column_position = model_position.z / shingle_width + row * 0.5 + hash12(vec2(row, 1.0)) * 0.3;
		float column = floor(column_position);
		float s = fract(column_position);
		float id = hash12(vec2(row, column));
		// Each shingle is lighter at the top, darker at the lower edge that
		// overlaps the row below, with a dark gap between neighbours.
		float edge = smoothstep(0.62 + id * 0.2, 1.0, t);
		float gap = smoothstep(0.0, 0.05, s) * smoothstep(1.0, 0.95, s);
		color *= 0.8 + 0.35 * id;
		color *= mix(1.0, 0.6, edge);
		color *= mix(0.45, 1.0, gap);
		height = t * 0.03 * gap;
		float mossy = smoothstep(0.55, 0.8, fbm(model_position.xz * 0.6, 3)) * moss;
		color = mix(color, vec3(0.35, 0.45, 0.16), mossy);
	} else {
		color *= 0.7;
	}
	color *= 0.9 + 0.2 * fbm(model_position.xz * 6.0, 3);

	ALBEDO = color;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
}
