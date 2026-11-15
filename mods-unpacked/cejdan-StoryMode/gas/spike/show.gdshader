shader_type canvas_item;

// Spike #199. Draws the gas: snapped to the game's pixels, in green bands with
// dithered edges, only in open cells the player has revealed.

uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform vec2 size_px;        // the window in world pixels
uniform float time;
uniform float raw;           // 1: show the field unbanded, 2: the velocity (debug)
uniform sampler2D vel : filter_linear, repeat_disable;

const vec3 C0 = vec3(0.07, 0.20, 0.09);
const vec3 C1 = vec3(0.16, 0.40, 0.13);
const vec3 C2 = vec3(0.33, 0.62, 0.16);
const vec3 C3 = vec3(0.58, 0.83, 0.22);
const vec3 C4 = vec3(0.86, 0.98, 0.45);

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	vec2 px = floor(UV * size_px);
	vec2 uv = (px + 0.5) / size_px;
	vec4 t = texture(tiles, uv);
	vec4 d = texture(dye, uv);
	float v = d.x * (0.5 + 1.0 * clamp((d.y - 0.5) * 3.5 + 0.5, 0.0, 1.0));
	if (raw > 1.5) {
		vec2 q = texture(vel, uv).xy;
		COLOR = vec4(abs(q) * 0.5, 0.0, 1.0);
	} else if (raw > 0.5) {
		COLOR = vec4(d.x, d.y, 0.0, 1.0);
	} else if (t.r < 0.5 || t.b < 0.5 || v < 0.05) {
		COLOR = vec4(0.0);
	} else {
		// Five bands; the dither moves each band's edge by up to a third of a band.
		float lv = v * 4.2 + (bayer(px) - 0.5) * 0.7;
		vec3 col = C0;
		float a = 0.42;
		if (lv > 3.6) { col = C4; a = 0.95; }
		else if (lv > 2.6) { col = C3; a = 0.9; }
		else if (lv > 1.7) { col = C2; a = 0.82; }
		else if (lv > 0.9) { col = C1; a = 0.68; }
		COLOR = vec4(col, a);
	}
}
