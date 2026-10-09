shader_type spatial;
render_mode cull_disabled;
// Grass tufts: root-to-tip gradient, wind sway that grows toward the tip, and
// upward normals so blades light like the ground they grow from.

uniform vec4 root_color : source_color = vec4(0.30, 0.47, 0.10, 1.0);
uniform vec4 tip_color : source_color = vec4(0.66, 0.76, 0.26, 1.0);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;

varying vec3 tint;

void vertex() {
	tint = COLOR.rgb;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * wind_speed + world.x * 0.35 + world.z * 0.25)
		+ 0.5 * sin(TIME * wind_speed * 2.3 + world.x * 0.9);
	vec3 offset = vec3(1.0, 0.0, 0.6) * gust * wind_strength * UV.y * UV.y;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * offset;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(root_color.rgb, tip_color.rgb, UV.y) * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.25);
}
