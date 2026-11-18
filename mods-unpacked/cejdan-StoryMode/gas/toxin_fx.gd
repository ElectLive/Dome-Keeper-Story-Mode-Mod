extends Node2D

# What the keeper's toxin looks and sounds like (#202): the green bar over the
# keeper, a green vignette that creeps in from the screen's edges, and the
# game's sound going muffled. A child of the gas field, drawn above the gas.
# Draw and sound only; the toxin itself is the gas field's.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const GasSfx = preload("res://mods-unpacked/cejdan-StoryMode/gas/gas_sfx.gd")
const BAR_OFFSET := Vector2(-9, -15)      # under the heat bar (-20)
const COL_BAR := Color("7ad11e")
const COL_BAR_FULL := Color("d8ff4a")
const MUFFLE_FROM := 0.35                 # share of the bar where the sound starts to dull
const MUFFLE_HZ := 700.0                  # cutoff at a full bar

var field
var share := 0.0                          # the bar, 0..1, as shown
var vignette := 0.0                       # 0..1, as shown
var muffle := 0.0                         # 0..1, as applied

var _time := 0.0
var _layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _lowpass: AudioEffectLowPassFilter
var _choke_t := 0.0

const VIGNETTE := """shader_type canvas_item;
uniform float amount;
uniform float pulse;

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	// In blocks of 4 screen pixels, dithered in steps, to sit with the pixel art.
	vec2 cell = floor(FRAGCOORD.xy / 4.0);
	vec2 uv = cell * 4.0 * SCREEN_PIXEL_SIZE;
	vec2 p = uv - 0.5;
	p.x *= 1.25;
	float d = length(p) * 1.55;
	// The clear middle shrinks as the toxin builds; the edge wavers.
	float wob = 0.05 * sin(uv.y * 31.0 + TIME * 1.7) + 0.04 * sin(uv.x * 23.0 - TIME * 1.1);
	float edge = smoothstep(1.1 - 0.7 * amount, 1.45 - 0.45 * amount, d + wob * amount);
	float lvl = floor(edge * 4.0 + bayer(cell)) / 4.0;
	vec3 col = mix(vec3(0.10, 0.34, 0.06), vec3(0.40, 0.78, 0.12), pulse * 0.5);
	COLOR = vec4(col, lvl * (0.18 + 0.5 * amount) * step(0.001, amount));
}
"""


func setup(p_field) -> void:
	field = p_field
	z_index = 20
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("amount", 0.0)
	_mat.set_shader_parameter("pulse", 0.0)
	_rect.material = _mat
	_rect.visible = false
	_layer.add_child(_rect)


func _process(delta: float) -> void:
	if field == null:
		return
	if not GameWorld.paused:
		_time += delta
	share = clampf(field.toxin / GasData.TOXIN_MAX, 0.0, 1.0)
	var warn: bool = share >= GasData.WARN_SHARE
	# The vignette eases toward the bar, so it creeps in and drains away.
	var want: float = smoothstep(0.15, 1.0, share)
	vignette = move_toward(vignette, want, delta * (1.6 if want > vignette else 0.9))
	_rect.visible = vignette > 0.003
	_mat.set_shader_parameter("amount", vignette)
	_mat.set_shader_parameter("pulse", (0.5 + 0.5 * sin(_time * 12.0)) if warn else 0.0)
	_set_muffle(smoothstep(MUFFLE_FROM, 1.0, share), delta)
	if warn and not GameWorld.paused:
		_choke_t -= delta
		if _choke_t <= 0.0:
			_choke_t = 0.45
			GasSfx.play("choke", -4.0)
	else:
		_choke_t = 0.0
	queue_redraw()


# The game's sound through a low-pass on the master bus, only while it is needed.
func _set_muffle(want: float, delta: float) -> void:
	muffle = move_toward(muffle, want, delta * 2.0)
	if muffle <= 0.001:
		_drop_lowpass()
		return
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.resonance = 0.5
		AudioServer.add_bus_effect(0, _lowpass)
	# From wide open down to MUFFLE_HZ, evenly in pitch.
	_lowpass.cutoff_hz = 18000.0 * pow(MUFFLE_HZ / 18000.0, muffle)


func _drop_lowpass() -> void:
	if _lowpass == null:
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _lowpass:
			AudioServer.remove_bus_effect(0, i)
			break
	_lowpass = null


func _exit_tree() -> void:
	_drop_lowpass()


func _draw() -> void:
	if field == null or field.toxin <= 0.5:
		return
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper):
		return
	var p: Vector2 = (to_local(keeper.global_position) + BAR_OFFSET).round()
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(20, 5)), Color(0, 0, 0, 0.8))
	var col: Color = COL_BAR.lerp(COL_BAR_FULL, share)
	if share >= GasData.WARN_SHARE and fposmod(_time * 8.0, 1.0) < 0.5:
		col = Color.WHITE
	draw_rect(Rect2(p, Vector2(round(18.0 * share), 3)), col)
