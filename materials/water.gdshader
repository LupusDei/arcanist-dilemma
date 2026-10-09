shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;
// Pond water: colour deepens with depth behind the surface, a soft foam line
// where it meets the shore, and two scrolling normal maps for ripples.

uniform vec4 shallow_color : source_color = vec4(0.40, 0.70, 0.80, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.28, 0.50, 1.0);
uniform float depth_fade = 1.8;
uniform float foam_width = 0.3;
uniform sampler2D normal_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);

	float t = clamp(water_depth / depth_fade, 0.0, 1.0);
	float foam = 1.0 - smoothstep(0.0, foam_width, water_depth);
	ALBEDO = mix(mix(shallow_color.rgb, deep_color.rgb, t), vec3(0.92, 0.95, 1.0), foam * 0.6);
	ALPHA = max(mix(0.55, 0.9, t), foam * 0.8);

	vec2 uv = world_position.xz * 0.08;
	vec3 a = texture(normal_a, uv + TIME * vec2(0.02, 0.01)).rgb;
	vec3 b = texture(normal_b, uv * 1.7 - TIME * vec2(0.015, 0.02)).rgb;
	NORMAL_MAP = mix(a, b, 0.5);
	NORMAL_MAP_DEPTH = 0.5;
	ROUGHNESS = 0.06;
	SPECULAR = 0.5;
}
