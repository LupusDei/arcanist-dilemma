shader_type spatial;
// Hair, brows and beards. UV.x runs along each lock (0 root, 1 tip) and UV.y
// is a random number per lock: roots are darker, tips catch the light, and
// neighbouring locks differ a little in tone. A sheen band follows the light.

uniform vec4 hair_color : source_color = vec4(0.33, 0.2, 0.11, 1.0);
uniform float root_shade = 0.35;
uniform float sheen = 0.25;
uniform float stubble = 0.0;
uniform float flash = 0.0;
uniform float light_wrap = 0.3;
uniform vec4 scatter = vec4(1.0, 0.6, 0.4, 0.15);
uniform float gloss = 0.55;

#include "res://actors/characters/shaders/character_light.gdshaderinc"

varying vec3 local_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 c = hair_color.rgb;
	float t = UV.x;
	c *= mix(1.0 - root_shade, 1.08, smoothstep(0.0, 0.7, t));
	c *= 0.92 + 0.16 * UV.y;
	if (stubble > 0.0) {
		// Fine buzz-cut speckle; the skin shows through a little.
		float s = hash3(floor(local_pos * 2600.0));
		c *= 1.0 - stubble * 0.18 * s;
	}
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float band = smoothstep(0.45, 0.75, n.y) * smoothstep(0.98, 0.8, n.y) * max(dot(n, v), 0.0);
	ALBEDO = c;
	EMISSION = mix(c, vec3(1.0), 0.3) * band * sheen + vec3(1.0, 0.35, 0.3) * flash;
	ROUGHNESS = 0.6;
	SPECULAR = 0.25;
}
