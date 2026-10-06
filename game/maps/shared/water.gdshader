shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_toon, specular_toon, shadows_disabled;

uniform vec3 shallow_color : source_color = vec3(0.3, 0.74, 0.76);
uniform vec3 deep_color : source_color = vec3(0.07, 0.36, 0.6);
uniform vec3 foam_color : source_color = vec3(0.96, 1.0, 1.0);
uniform float depth_range = 0.6;
uniform float foam_depth = 0.16;
uniform float flow_speed = 1.8;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.z * 0.9 + TIME * 1.2) * 0.03 + sin(world_position.x * 1.7 + TIME * 0.8) * 0.02;
}

void fragment() {
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float water_depth = max(-behind.z / behind.w + VERTEX.z, 0.0);
	float deepness = clamp(water_depth / depth_range, 0.0, 1.0);

	float wobble = sin(world_position.z * 2.3 + TIME * 1.7) * 0.03 + sin(world_position.z * 5.1 - TIME * 2.3) * 0.015;
	float foam = 1.0 - smoothstep(foam_depth * 0.55, foam_depth, water_depth + wobble);
	float flow = world_position.z * 1.4 - TIME * flow_speed + sin(world_position.x * 2.6 + TIME * 0.7) * 1.1;
	float streak = smoothstep(0.82, 1.0, sin(flow) * sin(world_position.x * 1.9 + world_position.z * 0.35));

	vec3 water = mix(shallow_color, deep_color, deepness);
	water = mix(water, foam_color, streak * 0.4 * deepness);
	ALBEDO = mix(water, foam_color, foam);
	ALPHA = max(mix(0.6, 0.94, deepness), foam);
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
}
