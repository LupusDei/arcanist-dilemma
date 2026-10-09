shader_type spatial;
// Boulders and pebbles: speckled stone with cracks, lichen spots and moss on
// the faces that point up.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 stone_color : source_color = vec4(0.6, 0.6, 0.62, 1.0);
uniform vec4 moss_color : source_color = vec4(0.4, 0.52, 0.18, 1.0);
uniform vec4 lichen_color : source_color = vec4(0.82, 0.78, 0.55, 1.0);
uniform float moss_amount = 0.6;

varying vec3 model_position;
varying vec3 world_normal;

void vertex() {
	model_position = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = planar_uv(model_position * 2.0, world_normal);
	float grain = fbm(uv * 3.0, 4);
	vec3 crack = cells(uv * 0.8);
	float crack_line = smoothstep(0.05, 0.0, crack.y);
	vec3 color = stone_color.rgb * (0.75 + 0.4 * grain) * (0.9 + 0.2 * crack.z);
	color *= 1.0 - crack_line * 0.45;
	float lichen = smoothstep(0.62, 0.7, fbm(uv * 1.7 + 11.0, 3));
	color = mix(color, lichen_color.rgb, lichen * 0.5);
	float moss = smoothstep(0.45, 0.85, world_normal.y) * smoothstep(0.35, 0.6, fbm(uv * 0.9, 3)) * moss_amount;
	color = mix(color, moss_color.rgb * (0.8 + 0.3 * grain), moss);
	ALBEDO = color;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	NORMAL = bump_normal(NORMAL, VERTEX, grain * 0.03 - crack_line * 0.02 + moss * 0.02, 1.0);
}
