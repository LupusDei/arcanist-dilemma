shader_type spatial;
// Stylized terrain: grass with large and small scale colour variation, dirt
// paths from vertex colour (R), muddy shore near the water, dirt banks on
// slopes and rock on cliffs.

uniform vec4 grass_dark : source_color = vec4(0.40, 0.58, 0.15, 1.0);
uniform vec4 grass_light : source_color = vec4(0.56, 0.68, 0.20, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.74, 0.48, 0.27, 1.0);
uniform vec4 bank_color : source_color = vec4(0.68, 0.42, 0.24, 1.0);
uniform vec4 rock_color : source_color = vec4(0.52, 0.50, 0.52, 1.0);
uniform float water_level = -0.3;
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float large = texture(variation_noise, world_position.xz * 0.012).r;
	float small = texture(variation_noise, world_position.xz * 0.09).r;

	vec3 color = mix(grass_dark.rgb, grass_light.rgb, smoothstep(0.35, 0.65, large));
	color *= 0.92 + 0.16 * small;

	float path = smoothstep(0.35, 0.6, COLOR.r + (small - 0.5) * 0.35);
	color = mix(color, dirt_color.rgb * (0.95 + 0.1 * small), path);

	float shore = 1.0 - smoothstep(water_level + 0.3, water_level + 0.9, world_position.y);
	color = mix(color, dirt_color.rgb * 0.8, shore);

	float bank = 1.0 - smoothstep(0.72, 0.80, world_normal.y);
	color = mix(color, bank_color.rgb * (0.9 + 0.2 * small), bank);

	float cliff = 1.0 - smoothstep(0.55, 0.68, world_normal.y);
	color = mix(color, rock_color.rgb * (0.85 + 0.3 * small), cliff);

	ALBEDO = color;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
