shader_type spatial;
// Painted cartoon eyes. UV.x is the angle from straight ahead (0 to 1 = 0 to pi)
// and UV.y the angle around it, so the iris, pupil and catchlights are drawn
// in a disc facing forward on the eyeball.

uniform vec4 iris_color : source_color = vec4(0.38, 0.23, 0.12, 1.0);
uniform vec4 sclera_color : source_color = vec4(0.97, 0.95, 0.92, 1.0);
uniform float iris_size = 0.56;
uniform float pupil_size = 0.22;
uniform float flash = 0.0;
uniform float light_wrap = 0.2;
uniform vec4 scatter = vec4(1.0, 1.0, 1.0, 0.0);
uniform float gloss = 0.9;

#include "res://actors/characters/shaders/character_light.gdshaderinc"

void fragment() {
	float th = UV.x * PI;
	float ph = UV.y * TAU;
	vec2 p = vec2(cos(ph), sin(ph)) * th;
	float rho = th;
	vec3 color = sclera_color.rgb;
	// Shadow of the upper lid across the top of the eye.
	color *= mix(1.0, 0.78, smoothstep(0.25, 0.85, p.y));
	float iris = smoothstep(iris_size + 0.015, iris_size - 0.015, rho);
	vec3 ic = iris_color.rgb;
	// Darker rim, lighter toward the bottom like light pooling in the iris.
	vec3 iris_c = mix(ic * 1.45 + vec3(0.04), ic * 0.55, smoothstep(-0.3, 0.35, p.y));
	iris_c = mix(iris_c, ic * 0.3, smoothstep(iris_size * 0.7, iris_size, rho));
	// Fine radial fibres.
	iris_c *= 0.9 + 0.12 * sin(atan(p.y, p.x) * 24.0);
	color = mix(color, iris_c, iris);
	float pupil = smoothstep(pupil_size + 0.01, pupil_size - 0.01, rho);
	color = mix(color, vec3(0.02, 0.015, 0.015), pupil);
	// Two catchlights, upper left, like a key light and its bounce.
	float c1 = smoothstep(0.075, 0.055, length(p - vec2(-0.13, 0.15)));
	float c2 = smoothstep(0.04, 0.025, length(p - vec2(0.12, -0.12)));
	float catch = max(c1, c2 * 0.7);
	ALBEDO = color;
	EMISSION = vec3(catch) * 1.4 + iris_c * iris * (1.0 - pupil) * 0.18 + vec3(1.0, 0.35, 0.3) * flash;
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
}
