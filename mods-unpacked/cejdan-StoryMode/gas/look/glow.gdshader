shader_type canvas_item;
render_mode blend_add;

// The gas's sickly light on the rock around it (#203): the drawn density,
// blurred wide, added over everything the player has revealed.

uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform vec2 size_px;
uniform vec2 win_tiles;
uniform float time;
uniform float strength;

void fragment() {
	vec2 px = floor(UV * size_px / 2.0) * 2.0;
	vec2 uv = (px + 1.0) / size_px;
	if (texture(tiles, uv).b < 0.5) {
		COLOR = vec4(0.0);
	} else {
		float g = 0.0;
		vec2 r = 1.0 / win_tiles;
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.5236;
			float rad = (i % 2 == 0) ? 0.55 : 1.25;
			g += min(texture(dye, uv + vec2(cos(ang), sin(ang)) * rad * r).x, 1.3);
		}
		g = g / 12.0 + 0.5 * min(texture(dye, uv).x, 1.3);
		float flick = 0.9 + 0.1 * sin(time * 2.3 + px.x * 0.02);
		COLOR = vec4(vec3(0.42, 1.0, 0.22) * g * strength * flick, 1.0);
	}
}
