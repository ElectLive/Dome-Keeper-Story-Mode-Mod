shader_type canvas_item;
render_mode blend_disabled;

// What the gas carries along (#203), moved by the velocity field.
// State: x gas density as drawn, yz how far this bit of gas has been carried
// from where its pattern belongs (tiles). The draw shader looks its pattern up
// at "here + yz", so the flow twists the pattern into swirls while the pattern
// itself stays as sharp as the screen.
// The density is pulled toward the gameplay grid every step, so the drawn gas
// never drifts from where it hurts; the twist slowly unwinds, so it never
// smears into mush.

uniform sampler2D prev : filter_linear, repeat_disable;
uniform sampler2D vel : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform vec2 texel;
uniform vec2 shift;
uniform float sub;
uniform float run;
uniform float fill_rate;
uniform float clear_rate;
uniform float untwist;

const float DT = 0.15;

float coarse_at(vec2 uv) {
	vec2 ts = vec2(textureSize(tiles, 0));
	vec2 p = uv * ts - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	float sum = 0.0;
	float wsum = 0.0;
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			vec4 t = texture(tiles, (i + vec2(float(x), float(y)) + 0.5) / ts);
			float w = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y) * step(0.5, t.r);
			sum += t.g * 4.0 * w;
			wsum += w;
		}
	}
	return wsum > 0.0 ? sum / wsum : 0.0;
}

void fragment() {
	vec2 old = UV + shift;
	if (texture(tiles, UV).r < 0.5) {
		COLOR = vec4(0.0);
	} else if (run < 0.5) {
		COLOR = texture(prev, old);
	} else {
		vec2 v = texture(vel, UV).xy;
		vec2 src = old - DT * v * texel;
		vec4 d;
		// Gas is never pulled out of rock; such a cell keeps its own.
		if (texture(tiles, src - shift).r < 0.5) {
			d = texture(prev, old);
		} else {
			d = texture(prev, src);
			d.yz -= DT * v / sub;
		}
		d.yz *= 1.0 - untwist;
		// Never twisted further than a few tiles: past that the pattern only smears.
		float tw = length(d.yz);
		if (tw > 2.5) {
			d.yz *= 2.5 / tw;
		}
		float target = min(coarse_at(UV), 1.6);
		d.x += (target - d.x) * (d.x > target ? clear_rate : fill_rate);
		COLOR = vec4(max(d.x, 0.0), d.y, d.z, 1.0);
	}
}
