shader_type sky;
// Stylized dusk sky: violet zenith fading to a warm peach horizon, a soft sun
// with a wide glow, and slowly drifting fbm clouds lit from the sun's side.

uniform vec3 zenith_color : source_color = vec3(0.34, 0.36, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.98, 0.76, 0.68);
uniform vec3 ground_color : source_color = vec3(0.42, 0.36, 0.46);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.86, 0.80);
uniform vec3 cloud_shade_color : source_color = vec3(0.62, 0.55, 0.74);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.006;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 color = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), 0.55));
	if (up < 0.0) {
		color = mix(horizon_color, ground_color, clamp(-up * 5.0, 0.0, 1.0));
	}

	float sun_dot = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	color += sun_color * (pow(sun_dot, 2000.0) * 12.0 + pow(sun_dot, 18.0) * 0.45 + pow(sun_dot, 4.0) * 0.12);

	if (up > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = dir.xz / (up + 0.18) * 1.6 + TIME * cloud_speed * vec2(1.0, 0.35);
		float density = fbm(uv);
		float clouds = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, density);
		float lit = clamp(density - fbm(uv + LIGHT0_DIRECTION.xz * 0.12) + 0.55, 0.0, 1.0);
		vec3 cloud_color = mix(cloud_shade_color, cloud_lit_color, lit);
		cloud_color += sun_color * pow(sun_dot, 8.0) * 0.4;
		color = mix(color, cloud_color, clouds * smoothstep(0.0, 0.12, up) * 0.92);
	}

	COLOR = color;
}
