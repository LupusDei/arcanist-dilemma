shader_type spatial;
// Tree bark and logs: vertical ridges around the trunk with darker furrows.
// End caps (faces pointing along the trunk) show growth rings instead.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 bark_color : source_color = vec4(0.45, 0.31, 0.2, 1.0);
uniform vec4 heartwood_color : source_color = vec4(0.82, 0.66, 0.44, 1.0);

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec3 color;
	float height;
	if (abs(model_normal.y) > 0.8) {
		float r = length(model_position.xz);
		float rings = fract(r * 14.0 + fbm(model_position.xz * 6.0, 2) * 0.6);
		color = heartwood_color.rgb * (0.82 + 0.18 * smoothstep(0.2, 0.5, rings));
		height = rings * 0.005;
	} else {
		float angle = atan(model_position.z, model_position.x);
		vec2 uv = vec2(angle * 2.5, model_position.y * 0.6);
		float ridges = fbm(vec2(uv.x * 3.0, uv.y * 0.8), 4);
		float furrow = smoothstep(0.42, 0.55, ridges);
		color = bark_color.rgb * mix(0.55, 1.08, furrow) * (0.9 + 0.2 * fbm(uv * 8.0, 2));
		height = furrow * 0.03;
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
}
