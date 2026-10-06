shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float edge_power = 2.5;
uniform float fill = 0.08;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	float shimmer = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 18.0);
	ALBEDO = color.rgb + rim * 0.3;
	ALPHA = (fill + rim * (0.75 + 0.15 * shimmer)) * color.a;
}
