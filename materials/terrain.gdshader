shader_type spatial;
// Stylized terrain. Grass has broad colour patches, clover-dark clumps and fine
// speckle; dirt paths (vertex colour R) have pebbles, worn tracks and puddle-dark
// dips; banks on medium slopes are packed earth with roots; cliffs are layered
// rock with cracks and mossy ledges. Everything is bump mapped from the same
// height values, so the ground catches the low sun.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 grass_dark : source_color = vec4(0.40, 0.58, 0.15, 1.0);
uniform vec4 grass_light : source_color = vec4(0.56, 0.68, 0.20, 1.0);
uniform vec4 clover_color : source_color = vec4(0.30, 0.47, 0.13, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.74, 0.48, 0.27, 1.0);
uniform vec4 pebble_color : source_color = vec4(0.72, 0.68, 0.62, 1.0);
uniform vec4 bank_color : source_color = vec4(0.66, 0.41, 0.23, 1.0);
uniform vec4 rock_color : source_color = vec4(0.55, 0.52, 0.54, 1.0);
uniform vec4 moss_color : source_color = vec4(0.38, 0.5, 0.18, 1.0);
uniform float water_level = -0.3;
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 xz = world_position.xz;
	float large = texture(variation_noise, xz * 0.012).r;
	float small = texture(variation_noise, xz * 0.09).r;
	float fine = fbm(xz * 3.0, 3);

	// Grass.
	vec3 grass = mix(grass_dark.rgb, grass_light.rgb, smoothstep(0.35, 0.65, large));
	float clumps = smoothstep(0.55, 0.75, fbm(xz * 0.7 + 31.0, 3));
	grass = mix(grass, clover_color.rgb, clumps * 0.55);
	grass *= 0.88 + 0.24 * fine;
	float grass_height = clumps * 0.03 + fine * 0.02;

	// Dirt path.
	vec3 pebbles = cells(xz * 4.0);
	float pebble_size = 0.06 + 0.14 * fract(pebbles.z * 7.13);
	float pebble = smoothstep(pebble_size + 0.04, pebble_size, pebbles.x) * step(0.62, pebbles.z);
	pebble *= 1.0 - clamp(fwidth(xz.x * 4.0) * 1.5, 0.0, 1.0);
	float tracks = smoothstep(0.4, 0.75, fbm(xz * vec2(0.4, 0.4) + 7.0, 3));
	vec3 dirt = dirt_color.rgb * (0.9 + 0.2 * small) * (0.9 + 0.15 * fine);
	dirt = mix(dirt, dirt * 0.78, tracks * 0.6);
	dirt = mix(dirt, pebble_color.rgb * (0.8 + 0.4 * pebbles.z), pebble);
	float dirt_height = pebble * 0.03 - tracks * 0.02 + fine * 0.01;

	float path = smoothstep(0.35, 0.6, COLOR.r + (small - 0.5) * 0.35 + (fine - 0.5) * 0.15);
	vec3 color = mix(grass, dirt, path);
	float height = mix(grass_height, dirt_height, path);

	// Muddy shore.
	float shore = 1.0 - smoothstep(water_level + 0.3, water_level + 0.9, world_position.y);
	color = mix(color, dirt_color.rgb * 0.62 * (0.9 + 0.2 * fine), shore);

	// Earth banks on medium slopes: soft soil layers with grit.
	float bank = 1.0 - smoothstep(0.72, 0.80, world_normal.y);
	vec2 side_uv = abs(world_normal.x) > abs(world_normal.z) ? world_position.zy : world_position.xy;
	float soil_layers = world_position.y * 0.9 + fbm(side_uv * 0.3, 2) * 1.5;
	float layer_shade = hash12(vec2(floor(soil_layers), 9.0));
	vec3 earth = bank_color.rgb * (0.85 + 0.2 * layer_shade) * (0.88 + 0.24 * fbm(side_uv * 3.0, 3));
	color = mix(color, earth, bank);
	height = mix(height, fine * 0.03, bank);

	// Layered rock on cliffs: strata bands warped by noise, cracks between
	// cells, and moss where ledges face up.
	float cliff = 1.0 - smoothstep(0.55, 0.68, world_normal.y);
	float strata_y = world_position.y * 0.4 + fbm(side_uv * 0.12, 3) * 1.5;
	float band = fract(strata_y);
	// Fade fine rock detail out with distance so far cliffs don't shimmer.
	float near_detail = 1.0 - clamp(fwidth(strata_y) * 6.0, 0.0, 1.0);
	float layer_id = hash12(vec2(floor(strata_y), 3.0));
	vec3 crack = cells(side_uv * vec2(0.6, 1.2));
	float crack_line = smoothstep(0.06, 0.0, crack.y);
	vec3 rock = rock_color.rgb * (0.78 + 0.35 * layer_id) * (0.85 + 0.3 * fbm(side_uv * 3.0, 3));
	rock *= mix(1.0, mix(0.72, 1.0, smoothstep(0.0, 0.12, band)), near_detail);
	rock *= 1.0 - crack_line * 0.5 * near_detail;
	float moss = smoothstep(0.35, 0.6, world_normal.y) * smoothstep(0.4, 0.7, fbm(side_uv * 0.6, 3));
	rock = mix(rock, moss_color.rgb * (0.8 + 0.3 * fine), moss);
	color = mix(color, rock, cliff);
	height = mix(height, smoothstep(0.0, 0.15, band) * 0.12 - crack_line * 0.08 + fine * 0.03, cliff);

	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
}
