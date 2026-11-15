shader_type canvas_item;
render_mode blend_disabled;

// Spike #199. What the gas carries along, moved by the velocity field.
// State: x gas density as drawn, y marbling (noise smeared by the flow).
// The density is pulled back toward the gameplay grid every step, so the drawn
// gas never drifts from where it hurts.

uniform sampler2D prev : filter_linear, repeat_disable;
uniform sampler2D vel : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform sampler2D tiles_soft : filter_linear, repeat_disable;
uniform vec2 texel;
uniform vec2 shift;
uniform vec2 origin;
uniform float run;
uniform float time;
uniform float relax;
uniform float remarble;
uniform float sub;            // texels per tile

const float DT = 0.15;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}


// The grid's gas density here: blended between the four nearest tiles, open ones
// only, so gas never shows through a wall.
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
		vec4 d = texture(prev, src);
		// Dye pulled out of rock is no dye; keep this cell's own instead.
		if (texture(tiles, src - shift).r < 0.5) {
			d = texture(prev, old);
		}
		float target = coarse_at(UV);
		target = min(target, 1.6);
		// Quick to clear where the grid has no gas, slower to fill.
		d.x += (target - d.x) * (d.x > target ? relax * 3.0 : relax);
		vec2 wp = (UV / texel + origin) / sub;
		float fresh = 0.55 * noise(wp * 1.3 + vec2(0.0, time * 0.1)) + 0.45 * noise(wp * 3.1 - vec2(time * 0.07, 0.0));
		d.y = mix(d.y, fresh, remarble);
		COLOR = vec4(max(d.x, 0.0), d.y, 0.0, 1.0);
	}
}
