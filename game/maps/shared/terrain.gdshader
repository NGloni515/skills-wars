shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform float toon_softness : hint_range(0.01, 1.0) = 0.5;
uniform float tile_size = 2.0;
uniform float tile_contrast = 0.05;
uniform vec2 arena_half_size = vec2(18.0, 15.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tile = floor(world_position.xz / tile_size);
	float checker = mod(tile.x + tile.y, 2.0) * 2.0 - 1.0;
	float in_arena = step(abs(world_position.x), arena_half_size.x) * step(abs(world_position.z), arena_half_size.y);
	float on_grass = smoothstep(-0.12, -0.04, world_position.y);
	ALBEDO = COLOR.rgb * (1.0 + checker * tile_contrast * in_arena * on_grass);
	ROUGHNESS = toon_softness;
}
