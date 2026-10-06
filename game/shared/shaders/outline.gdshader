shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec3 outline_color : source_color = vec3(0.07, 0.05, 0.1);
uniform float outline_width = 0.028;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color;
}
