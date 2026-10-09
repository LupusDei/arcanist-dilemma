shader_type spatial;
// World-space grid for greybox geometry, so distance and speed are readable
// without textures. Projects onto whichever axis the surface faces.

uniform vec4 base_color : source_color = vec4(0.55, 0.55, 0.6, 1.0);
uniform vec4 line_color : source_color = vec4(0.38, 0.38, 0.44, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.03;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	vec2 distance_to_line = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float line = 1.0 - step(line_width, min(distance_to_line.x, distance_to_line.y));
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 0.9;
}
