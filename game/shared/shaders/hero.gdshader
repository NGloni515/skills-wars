shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 team_color : source_color = vec3(0.86, 0.24, 0.2);
uniform float toon_softness : hint_range(0.01, 1.0) = 0.22;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	vec3 base = COLOR.rgb;
	// Models paint team-colored parts in magenta; its brightness scales the team color.
	float team_mask = step(0.12, base.r) * (1.0 - step(0.02, abs(base.r - base.b))) * (1.0 - step(0.02, base.g));
	ALBEDO = mix(base, team_color * base.r, team_mask);
	ROUGHNESS = toon_softness;
	SPECULAR = 0.08;
	RIM = rim_strength;
	RIM_TINT = 0.6;
}
