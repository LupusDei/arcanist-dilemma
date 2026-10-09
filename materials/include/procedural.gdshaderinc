// Shared procedural texture helpers: hashing, value noise, fbm, cellular noise
// and bump mapping from a height value, so materials get surface detail
// without image textures.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

// Cellular noise. Returns (distance to nearest feature, distance to the edge
// between the two nearest cells, a random id for the nearest cell).
vec3 cells(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float best = 8.0;
	float second = 8.0;
	vec2 best_cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = offset + hash22(cell + offset) - local;
			float d = dot(point, point);
			if (d < best) {
				second = best;
				best = d;
				best_cell = cell + offset;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec3(sqrt(best), sqrt(second) - sqrt(best), hash12(best_cell));
}

// Projects a model or world position onto the plane a face mostly points along:
// the two coordinates across the face, so patterns wrap around boxes.
vec2 planar_uv(vec3 position, vec3 normal) {
	vec3 n = abs(normal);
	if (n.y > n.x && n.y > n.z) {
		return position.xz;
	}
	return n.x > n.z ? vec2(position.z, position.y) : vec2(position.x, position.y);
}

// Bump mapping without tangents (Mikkelsen 2010). Call in fragment() with the
// view-space NORMAL and VERTEX and a height in metres.
vec3 bump_normal(vec3 normal, vec3 position, float height, float strength) {
	vec3 dpdx = dFdx(position);
	vec3 dpdy = dFdy(position);
	float dhdx = dFdx(height);
	float dhdy = dFdy(height);
	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);
	float det = dot(dpdx, r1);
	vec3 gradient = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * normal - strength * gradient);
}
