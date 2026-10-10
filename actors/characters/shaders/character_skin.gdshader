shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Skin and clothes of the sculpted characters. The body mesh carries a colour
// region per vertex in UV2.x (0 skin, 1 top, 2 bottom, 3 boots, 4 leather,
// 5 trim, 6 inner shirt, 7 hair tie), so one mesh wears any outfit palette.
// Heads set face_paint: UV is head-space x,y over the head radius and UV2.y
// its depth, which places the lips, blush and a little shadow under the brows.

uniform vec4 region_skin : source_color = vec4(0.93, 0.76, 0.62, 1.0);
uniform vec4 region_top : source_color = vec4(0.79, 0.68, 0.5, 1.0);
uniform vec4 region_bottom : source_color = vec4(0.42, 0.42, 0.35, 1.0);
uniform vec4 region_boots : source_color = vec4(0.43, 0.27, 0.16, 1.0);
uniform vec4 region_leather : source_color = vec4(0.35, 0.22, 0.13, 1.0);
uniform vec4 region_trim : source_color = vec4(0.79, 0.64, 0.31, 1.0);
uniform vec4 region_inner : source_color = vec4(0.85, 0.81, 0.73, 1.0);
uniform vec4 region_tie : source_color = vec4(0.48, 0.23, 0.16, 1.0);
uniform float face_paint = 0.0;
uniform vec4 lip_color : source_color = vec4(0.72, 0.36, 0.33, 1.0);
uniform float lip_amount = 0.35;
uniform vec4 blush_color : source_color = vec4(0.88, 0.45, 0.40, 1.0);
uniform float blush_amount = 0.25;
uniform float mouth_y = -0.47;
uniform float cheek_x = 0.45;
uniform float stubble = 0.0;
uniform vec4 stubble_color : source_color = vec4(0.2, 0.15, 0.1, 1.0);
uniform float flash = 0.0;
uniform float cloth_grain = 0.06;
// The shirt's open V collar: skin shows above vneck_y + |x| * vneck_slope (rest-pose body space, in UV).
uniform float vneck_y = 10.0;
uniform float vneck_slope = 1.6;

varying vec3 base_color;
varying float region;
varying vec3 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	int r = clamp(int(round(UV2.x)), 0, 7);
	vec4 regions[8] = vec4[8](region_skin, region_top, region_bottom, region_boots, region_leather, region_trim, region_inner, region_tie);
	base_color = regions[r].rgb;
	region = float(r);
	local_pos = VERTEX;
}

void fragment() {
	vec3 color = base_color;
	float skin = 1.0 - clamp(region, 0.0, 1.0);
	if (face_paint > 0.5) {
		vec2 f = UV;
		float front = smoothstep(-0.55, -0.8, UV2.y);
		// Lips: an ellipse over the mouth, the lower lip a little fuller.
		vec2 m = (f - vec2(0.0, mouth_y)) / vec2(0.2, 0.085);
		float lips = smoothstep(1.0, 0.55, length(m)) * front;
		color = mix(color, lip_color.rgb, lips * lip_amount);
		// Blush on the cheeks.
		vec2 c = vec2(abs(f.x) - cheek_x, f.y + 0.22) / vec2(0.2, 0.13);
		color = mix(color, blush_color.rgb, smoothstep(1.0, 0.0, length(c)) * blush_amount * front);
		// Warmer nose tip and ears.
		float nose = smoothstep(0.16, 0.0, length(f - vec2(0.0, -0.24))) * front;
		color = mix(color, blush_color.rgb, nose * blush_amount * 0.5);
		// Stubble along the jaw and upper lip.
		float jaw = smoothstep(-0.2, -0.38, f.y) * (1.0 - lips) * smoothstep(0.3, -0.1, UV2.y);
		jaw = max(jaw, smoothstep(0.06, 0.0, abs(f.y - mouth_y - 0.1)) * step(abs(f.x), 0.2) * front);
		float grain = vnoise(f * 90.0);
		color = mix(color, stubble_color.rgb, stubble * 0.45 * jaw * (0.6 + 0.4 * grain));
		float ear = smoothstep(0.8, 0.95, abs(f.x)) * smoothstep(0.3, -0.1, abs(UV2.y));
		color = mix(color, color * vec3(1.0, 0.82, 0.78), ear * 0.6);
	} else if (UV2.y > 0.5) {
		float v = UV.y - (vneck_y + abs(UV.x) * vneck_slope);
		float open = smoothstep(-0.0015, 0.0015, v);
		// A darker hem along the edge of the opening.
		float hem = smoothstep(0.006, 0.0, abs(v + 0.003)) * (1.0 - open);
		color = mix(color * (1.0 - 0.25 * hem), region_skin.rgb, open);
		skin = open;
	} else if (region > 0.5) {
		// A soft woven grain on cloth so it doesn't read as plastic.
		float g = vnoise(local_pos.xy * 260.0) * 0.6 + vnoise(local_pos.zy * 260.0) * 0.4;
		color *= 1.0 - cloth_grain + g * cloth_grain * 1.4;
	}
	ALBEDO = color;
	ROUGHNESS = 0.82;
	SPECULAR = 0.12;
	RIM = 0.2;
	RIM_TINT = 0.6;
	// Light bleeding through skin keeps faces from going grey in shadow.
	EMISSION = vec3(1.0, 0.35, 0.3) * flash * 1.2;
}
