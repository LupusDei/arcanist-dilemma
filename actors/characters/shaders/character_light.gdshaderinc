// Soft "cartoon realism" lighting shared by the character shaders: a wrapped
// diffuse that rolls gently into shadow, a warm band where light turns into
// shadow (light scattering under skin and through cloth), a broad soft
// highlight and a rim from lights behind. Include after the uniforms; it reads
// the shader's light_wrap, scatter and gloss uniforms.

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	// The terminator band, strongest just where the surface turns away.
	float band = smoothstep(0.0, 0.35, d) * smoothstep(0.75, 0.25, d);
	vec3 warm = scatter.rgb * band * scatter.a;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (d + warm) / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, h), 0.0), mix(8.0, 64.0, gloss)) * gloss * 0.35;
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0) * smoothstep(-0.2, 0.4, -dot(VIEW, LIGHT)) * 0.5;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (spec * max(ndl, 0.0) + rim * ALBEDO) / PI;
}
