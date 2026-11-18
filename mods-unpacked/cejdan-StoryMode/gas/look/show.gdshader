shader_type canvas_item;

// Draws the gas (#203): snapped to the game's pixels, in green bands with
// dithered edges, only in open cells the player has revealed. The pattern is
// looked up where the flow carried it from (dye.yz), so it swirls.

uniform sampler2D dye : filter_linear, repeat_disable;
uniform sampler2D vel : filter_linear, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform vec2 size_px;        // the window in world pixels
uniform vec2 origin_tiles;   // the window's corner, in tiles
uniform vec2 win_tiles;
uniform float time;
uniform float raw;           // debug: 1 the dye field, 2 the velocity

const vec3 C0 = vec3(0.16, 0.36, 0.17);
const vec3 C1 = vec3(0.22, 0.50, 0.18);
const vec3 C2 = vec3(0.38, 0.68, 0.18);
const vec3 C3 = vec3(0.62, 0.86, 0.25);
const vec3 C4 = vec3(0.88, 0.99, 0.50);
const vec3 MOTE = vec3(0.96, 1.0, 0.72);

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

// How hot the gas burns here (#204): the grid's fire, blended over open tiles.
float fire_at(vec2 uv) {
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
			sum += t.a * w;
			wsum += w;
		}
	}
	return wsum > 0.0 ? sum / wsum : 0.0;
}

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
	if (raw > 1.5) {
		vec2 q = texture(vel, uv).xy;
		COLOR = vec4(abs(q) * 0.25, 0.0, 1.0);
	} else if (raw > 0.5) {
		COLOR = vec4(d.x, abs(d.y) * 0.5, abs(d.z) * 0.5, 1.0);
	} else if (t.r < 0.5 || t.b < 0.5 || (d.x < 0.03 && fire_at(uv) < 0.02)) {
		COLOR = vec4(0.0);
	} else {
		// Where this bit of gas's pattern lives (world tiles), after the flow's twist.
		vec2 q = origin_tiles + uv * win_tiles + d.yz;
		// Billows, warped by a slower field so they curl even in still gas.
		vec2 warp = vec2(fbm(q * 0.6 + vec2(0.0, time * 0.05)), fbm(q * 0.6 + vec2(5.2, 1.3 - time * 0.04)));
		float billow = fbm(q * 0.9 + (warp - 0.5) * 2.4 + vec2(0.0, time * 0.06));
		float p = smoothstep(0.28, 0.72, billow);
		// Thin bright filaments along the billows' ridges.
		float ridge = 1.0 - abs(2.0 * fbm(q * 1.7 + (warp - 0.5) * 1.6 + 40.0) - 1.0);
		float wisp = smoothstep(0.82, 0.97, ridge);
		float v = d.x * (0.42 + 0.95 * p + 0.45 * wisp);

		float lv = v * 4.0 + (bayer(px) - 0.5) * 0.8;
		vec3 col = C0;
		float a = 0.34;
		if (lv > 3.9) { col = C4; a = 0.94; }
		else if (lv > 2.9) { col = C3; a = 0.88; }
		else if (lv > 1.9) { col = C2; a = 0.78; }
		else if (lv > 1.0) { col = C1; a = 0.6; }
		else if (lv < 0.22) { a = 0.0; }

		// Motes carried by the flow: single bright pixels that twinkle.
		// (They follow only part of the twist, or they would stretch into streaks.)
		vec2 mc = floor((origin_tiles + uv * win_tiles + d.yz * 0.3 + vec2(0.0, -time * 0.12)) * 12.0);
		float mh = hash(mc);
		if (mh > 0.991 && d.x > 0.25) {
			float tw = sin(time * (2.0 + 5.0 * hash(mc + 3.7)) + mh * 90.0);
			if (tw > 0.2) {
				col = MOTE;
				a = 0.95;
			}
		}
		// Fire (#204): flames that lick upward, hottest where the gas is thickest.
		float f = fire_at(uv);
		if (f > 0.02) {
			vec2 fq = origin_tiles + uv * win_tiles;
			float lick = fbm(fq * vec2(2.6, 1.7) + vec2(0.0, time * 5.5));
			float heat = f * (0.45 + 1.1 * lick) + 0.3 * min(d.x, 1.0) * f + (bayer(px) - 0.5) * 0.14;
			vec3 fc = vec3(0.45, 0.08, 0.05);
			float fa = 0.55;
			if (heat > 1.0) { fc = vec3(1.0, 0.97, 0.78); fa = 0.97; }
			else if (heat > 0.78) { fc = vec3(1.0, 0.82, 0.26); fa = 0.95; }
			else if (heat > 0.55) { fc = vec3(0.98, 0.5, 0.1); fa = 0.9; }
			else if (heat > 0.34) { fc = vec3(0.8, 0.22, 0.06); fa = 0.78; }
			else if (heat < 0.16) { fa = 0.0; }
			if (fa > 0.0) {
				col = fc;
				a = max(a * (1.0 - f), fa);
			}
		}
		COLOR = vec4(col, a);
	}
}
