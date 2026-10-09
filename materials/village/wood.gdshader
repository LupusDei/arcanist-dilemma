shader_type spatial;
// Wood for walls, doors and beams. With plank_width > 0 it draws boards with
// seams, staggered end joints and per-board colour; with 0 it is plain timber
// with grain. Patterns use model space, so they stay put on each building.
#include "res://materials/include/procedural.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.56, 0.36, 0.22, 1.0);
uniform float plank_width = 0.3;
uniform bool vertical = false;
uniform float weathering = 0.0;

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec2 uv = planar_uv(model_position, model_normal);
	if (vertical) {
		uv = uv.yx;
	}
	// uv.x runs along the boards, uv.y across them.
	vec3 color = base_color.rgb;
	float height = 0.0;
	float board = 0.0;
	if (plank_width > 0.0) {
		board = floor(uv.y / plank_width);
		float across = fract(uv.y / plank_width);
		float joint_offset = hash12(vec2(board, 3.0)) * 3.0;
		float segment = floor((uv.x + joint_offset) / 2.4);
		float along = fract((uv.x + joint_offset) / 2.4);
		float seam = smoothstep(0.0, 0.07, across) * smoothstep(1.0, 0.93, across);
		float joint = smoothstep(0.0, 0.01, along) * smoothstep(1.0, 0.99, along);
		float tint = hash12(vec2(board, segment));
		color *= 0.82 + 0.3 * tint;
		color *= mix(0.45, 1.0, seam * joint);
		height = (seam * joint) * 0.012 + (across - 0.5) * 0.004;
	}
	float grain = fbm(vec2(uv.x * 1.5, uv.y * 28.0 + board * 7.0), 4);
	color *= 0.85 + 0.3 * grain;
	float knots = smoothstep(0.08, 0.0, cells(uv * vec2(1.2, 3.0) + board).x);
	color *= 1.0 - knots * 0.35;
	color = mix(color, vec3(dot(color, vec3(0.33))) * 1.1, weathering * fbm(uv * 2.0, 3));
	height += grain * 0.003;

	ALBEDO = color;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	NORMAL = bump_normal(NORMAL, VERTEX, height, 1.0);
}
