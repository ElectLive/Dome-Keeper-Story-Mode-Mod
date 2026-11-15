shader_type canvas_item;
render_mode blend_disabled;

// Spike #199. The gas's velocity field, one step a frame.
// State: xy velocity (texels a step), z pressure density (rests at 1), w curl.
// A single-pass compressible solver: the density's gradient is the pressure.

uniform sampler2D prev : filter_linear, repeat_disable;
uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;      // r open, g gas / 4, b revealed
uniform sampler2D tiles_soft : filter_linear, repeat_disable;
uniform vec2 texel;          // 1 / field size
uniform vec2 shift;          // the window moved this frame (uv)
uniform vec2 origin;         // the window's corner in world texels
uniform float run;           // 0 while the game is paused
uniform float time;
uniform vec2 keeper;         // texels in the window
uniform vec2 keeper_vel;     // field velocity units
uniform float keeper_r;
uniform float buoyancy;
uniform float churn;
uniform float vorticity;
uniform float jet;
uniform float sub;            // texels per tile

const float DT = 0.15;
const float K = 0.2;
const float VISC = 0.35;

bool solid(vec2 uv) {
	return texture(tiles, uv).r < 0.5;
}

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

// A neighbour's state; rock gives a still wall at this cell's own pressure.
vec4 at(vec2 uv_new, vec2 uv_old, vec4 c) {
	if (solid(uv_new)) {
		return vec4(0.0, 0.0, c.z, 0.0);
	}
	return texture(prev, uv_old);
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
	if (solid(UV) || old.x < 0.0 || old.y < 0.0 || old.x > 1.0 || old.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 1.0, 0.0);
	} else {
		vec4 data = texture(prev, old);
		if (run > 0.5) {
			vec2 ex = vec2(texel.x, 0.0);
			vec2 ey = vec2(0.0, texel.y);
			vec4 tr = at(UV + ex, old + ex, data);
			vec4 tl = at(UV - ex, old - ex, data);
			vec4 tu = at(UV + ey, old + ey, data);
			vec4 td = at(UV - ey, old - ey, data);
			vec3 dx = (tr.xyz - tl.xyz) * 0.5;
			vec3 dy = (tu.xyz - td.xyz) * 0.5;
			vec2 dens_dif = vec2(dx.z, dy.z);
			data.z -= DT * dot(vec3(dens_dif, dx.x + dy.y), data.xyz);
			vec2 lap = tu.xy + td.xy + tr.xy + tl.xy - 4.0 * data.xy;
			data.xy = texture(prev, old - DT * data.xy * texel).xy;

			float d = texture(dye, UV).x;
			vec2 force = vec2(0.0, -buoyancy * d);
			// Slow churning, so gas held in a pocket still moves.
			vec2 wp = (UV / texel + origin) / sub * 0.18;
			float e = 0.35;
			float n0 = noise(wp + vec2(0.0, time * 0.25));
			float nx = noise(wp + vec2(e, time * 0.25));
			float ny = noise(wp + vec2(0.0, e + time * 0.25));
			force += vec2(ny - n0, -(nx - n0)) / e * churn * min(d, 1.5);
			vec2 wq = wp * 2.7 + 31.0;
			float m0 = noise(wq - vec2(time * 0.4, 0.0));
			float mx = noise(wq + vec2(e - time * 0.4, 0.0));
			float my = noise(wq + vec2(-time * 0.4, e));
			force += vec2(my - m0, -(mx - m0)) / e * churn * 0.6 * min(d, 1.5);

			data.xy += DT * (VISC * lap - K / DT * dens_dif + force);
			data.xy = max(vec2(0.0), abs(data.xy) - 1e-4) * sign(data.xy);

			data.w = tr.y - tl.y - tu.x + td.x;
			vec2 vort = vec2(abs(tu.w) - abs(td.w), abs(tl.w) - abs(tr.w));
			vort *= vorticity / length(vort + 1e-9) * data.w;
			data.xy += vort;

			// The keeper drags the gas along.
			vec2 kd = (UV / texel - keeper) / keeper_r;
			float kg = exp(-dot(kd, kd));
			if (dot(keeper_vel, keeper_vel) > 0.01) {
				data.xy = mix(data.xy, keeper_vel, kg * 0.7);
			}

			// Gas under pressure in the grid pushes outward; everything eases back to rest.
			float coarse = coarse_at(UV);
			data.z += jet * max(0.0, coarse - 1.0);
			data.z = mix(data.z, 1.0, 0.004);
			data = clamp(data, vec4(-10.0, -10.0, 0.5, -10.0), vec4(10.0, 10.0, 3.0, 10.0));
		}
		COLOR = data;
	}
}
