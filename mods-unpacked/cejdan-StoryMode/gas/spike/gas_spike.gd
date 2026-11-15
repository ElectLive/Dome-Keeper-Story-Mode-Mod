extends Node2D

# Spike #199: can the gas's look be a small GPU fluid simulation?
#
# The gameplay grid (`gas`: one density per tile, a rough rising-gas rule here;
# the real one is #200) stays the truth. For a window of tiles around the
# screen, two float fields at SUB texels a tile are stepped on the GPU each
# frame (ping-pong SubViewports): velocity, and the dye the picture is made of.
# The dye is pulled toward the grid, so the picture can't drift from it.
#
# Throwaway code: a child of the run's map, added by the spike's scenario.

const DIR := "res://mods-unpacked/cejdan-StoryMode/gas/spike/"
const TILE := 24.0
const SUB := 8                      # field texels per tile
const WIN := Vector2i(32, 20)       # the window, in tiles (the screen shows about 19 x 11)
const TICK := 0.05
const COMPRESS := 0.6
const MAX_FLOW := 1.2

var map
var gas: Dictionary = {}            # Vector2i -> density
var vented := 0.0
var c0 := Vector2i.ZERO             # the window's top-left tile
var params := {"buoyancy": 1.8, "churn": 7.0, "vorticity": 0.25, "jet": 0.05, "relax": 0.03, "remarble": 0.02}
var cpu_us := 0
var cpu_frames := 0
var freeze_grid := false

var _acc := 0.0
var _time := 0.0
var _vel_mat: ShaderMaterial
var _dye_mat: ShaderMaterial
var _show_mat: ShaderMaterial
var _vel_a: SubViewport
var _dye_a: SubViewport
var _tiles_img: Image
var _tiles_tex: ImageTexture
var _sprite: Sprite2D
var _last_keeper = null
var _have_window := false


func setup(p_map) -> void:
	map = p_map
	z_index = 7
	var size := WIN * SUB
	_tiles_img = Image.create(WIN.x, WIN.y, false, Image.FORMAT_RGBA8)
	_tiles_tex = ImageTexture.create_from_image(_tiles_img)
	_vel_mat = _material("vel.gdshader")
	_dye_mat = _material("dye.gdshader")
	var vel := _pair("Vel", size, _vel_mat)
	var dye := _pair("Dye", size, _dye_mat)
	_vel_a = vel[0]
	_dye_a = dye[0]
	_vel_mat.set_shader_parameter("prev", vel[1].get_texture())
	_vel_mat.set_shader_parameter("dye", dye[1].get_texture())
	_dye_mat.set_shader_parameter("prev", dye[1].get_texture())
	_dye_mat.set_shader_parameter("vel", vel[0].get_texture())
	for m in [_vel_mat, _dye_mat]:
		m.set_shader_parameter("tiles", _tiles_tex)
		m.set_shader_parameter("tiles_soft", _tiles_tex)
		m.set_shader_parameter("texel", Vector2(1.0 / size.x, 1.0 / size.y))
		m.set_shader_parameter("sub", float(SUB))
	_show_mat = _material("show.gdshader")
	_show_mat.set_shader_parameter("dye", dye[0].get_texture())
	_show_mat.set_shader_parameter("tiles", _tiles_tex)
	_show_mat.set_shader_parameter("vel", vel[0].get_texture())
	_show_mat.set_shader_parameter("size_px", Vector2(WIN) * TILE)
	_sprite = Sprite2D.new()
	_sprite.texture = dye[0].get_texture()
	_sprite.centered = false
	_sprite.scale = Vector2(TILE / SUB, TILE / SUB)
	_sprite.material = _show_mat
	add_child(_sprite)


func _material(file: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FileAccess.get_file_as_string(DIR + file)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# A simulated field and its copy: the simulation reads the copy (last frame's
# state) and writes the next state.
func _pair(label: String, size: Vector2i, mat: ShaderMaterial) -> Array:
	var out: Array = []
	for i in 2:
		var vp := SubViewport.new()
		vp.name = label + ("Sim" if i == 0 else "Copy")
		vp.size = size
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(vp)
		out.append(vp)
	var sim := ColorRect.new()
	sim.size = Vector2(size)
	sim.material = mat
	out[0].add_child(sim)
	var copy := TextureRect.new()
	copy.texture = out[0].get_texture()
	copy.size = Vector2(size)
	copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cm := ShaderMaterial.new()
	cm.shader = Shader.new()
	cm.shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment(){ COLOR = texture(TEXTURE, UV); }"
	copy.material = cm
	out[1].add_child(copy)
	return out


func _is_open(c: Vector2i) -> bool:
	return c.y >= 1 and map.is_tile_empty(c)


func _process(delta: float) -> void:
	if map == null:
		return
	var t0 := Time.get_ticks_usec()
	var paused: bool = GameWorld.paused
	if not paused:
		_time += delta
		_acc += delta
		while _acc >= TICK:
			_acc -= TICK
			if not freeze_grid:
				_step()
	_update_window()
	_update_tiles()
	var keeper = Keepers.first()
	var kv := Vector2.ZERO
	var kp := Vector2(-999, -999)
	if keeper != null and is_instance_valid(keeper):
		var local: Vector2 = to_local(keeper.global_position)
		kp = (local - _sprite.position) / (TILE / SUB)
		if _last_keeper != null and delta > 0.0:
			# Field velocity is texels a step / 0.15; a step is a frame.
			kv = (local - _last_keeper) / (TILE / SUB) / 0.15
			if kv.length() < 0.8:
				kv = Vector2.ZERO
			if kv.length() > 10.0:
				kv = kv.normalized() * 10.0
		_last_keeper = local
	for m in [_vel_mat, _dye_mat]:
		m.set_shader_parameter("run", 0.0 if paused else 1.0)
		m.set_shader_parameter("time", _time)
		m.set_shader_parameter("origin", Vector2(c0 * SUB))
	_vel_mat.set_shader_parameter("keeper", kp)
	_vel_mat.set_shader_parameter("keeper_vel", kv)
	_vel_mat.set_shader_parameter("keeper_r", 0.8 * SUB)
	for k in ["buoyancy", "churn", "vorticity", "jet"]:
		_vel_mat.set_shader_parameter(k, params[k])
	for k in ["relax", "remarble"]:
		_dye_mat.set_shader_parameter(k, params[k])
	_show_mat.set_shader_parameter("time", _time)
	cpu_us += Time.get_ticks_usec() - t0
	cpu_frames += 1


# The window follows the screen's centre in whole tiles; the fields are shifted
# by the same amount on the frame it moves, so the gas stays put in the world.
func _update_window() -> void:
	var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var centre: Vector2 = inv * (get_viewport().get_visible_rect().get_center())
	var want: Vector2i = map.getTileCoord(to_global(centre)) - WIN / 2
	var shift := Vector2.ZERO
	if _have_window and want != c0:
		shift = Vector2(want - c0) / Vector2(WIN)
	c0 = want
	_have_window = true
	_vel_mat.set_shader_parameter("shift", shift)
	_dye_mat.set_shader_parameter("shift", shift)
	_sprite.position = to_local(map.getTilePos(Vector2(c0))) - Vector2(TILE, TILE) * 0.5


# One texel a tile: r open, g gas density / 4 b revealed.
func _update_tiles() -> void:
	var data := PackedByteArray()
	data.resize(WIN.x * WIN.y * 4)
	var i := 0
	var vis: Dictionary = map.visibleTileCoords
	for y in range(c0.y, c0.y + WIN.y):
		for x in range(c0.x, c0.x + WIN.x):
			var c := Vector2i(x, y)
			var open := _is_open(c)
			var g: float = gas.get(c, 0.0)
			data[i] = 255 if open else 0
			data[i + 1] = int(clampf(g / 4.0, 0.0, 1.0) * 255.0)
			data[i + 2] = 255 if (vis.has(Vector2(c)) or vis.has(c)) else 0
			data[i + 3] = 255
			i += 4
	_tiles_img.set_data(WIN.x, WIN.y, false, Image.FORMAT_RGBA8, data)
	_tiles_tex.update(_tiles_img)


# How much of `total` the upper of two stacked cells should hold.
func _split(total: float) -> float:
	if total <= 1.0:
		return 1.0
	if total < 2.0 + COMPRESS:
		return (1.0 + total * COMPRESS) / (1.0 + COMPRESS)
	return (total + COMPRESS) / 2.0


# Lava's rule upside down, looser: up first, sideways along a ceiling, down
# only when squeezed; a little spreading everywhere; thin gas fades.
func _step() -> void:
	var dm: Dictionary = {}
	for c in gas:
		var m: float = gas[c]
		var rem := m
		var up: Vector2i = c + Vector2i.UP
		var up_open := _is_open(up)
		if up.y < 1 and map.is_tile_empty(up):
			# The surface: it leaves the mine.
			vented += rem
			dm[c] = dm.get(c, 0.0) - rem
			continue
		if up_open:
			var mu: float = gas.get(up, 0.0)
			var flow: float = clampf((_split(rem + mu) - mu) * 0.7, 0.0, minf(MAX_FLOW, rem))
			if flow > 0.0:
				dm[c] = dm.get(c, 0.0) - flow
				dm[up] = dm.get(up, 0.0) + flow
				rem -= flow
		if rem <= 0.0:
			continue
		var resting: bool = not up_open or gas.get(up, 0.0) >= 0.9
		for side in [Vector2i.LEFT, Vector2i.RIGHT]:
			var sc: Vector2i = c + side
			if not _is_open(sc):
				continue
			var flow: float = clampf((m - gas.get(sc, 0.0)) / (2.2 if resting else 14.0), 0.0, minf(MAX_FLOW, rem))
			if flow > 0.002:
				dm[c] = dm.get(c, 0.0) - flow
				dm[sc] = dm.get(sc, 0.0) + flow
				rem -= flow
		var down: Vector2i = c + Vector2i.DOWN
		if _is_open(down):
			var md: float = gas.get(down, 0.0)
			var flow := 0.0
			if rem > 1.0:
				flow = (rem - _split(rem + md)) * 0.7
			flow = clampf(maxf(flow, (m - md) * 0.015), 0.0, minf(MAX_FLOW, rem))
			if flow > 0.002:
				dm[c] = dm.get(c, 0.0) - flow
				dm[down] = dm.get(down, 0.0) + flow
	for c in dm:
		var v: float = gas.get(c, 0.0) + dm[c]
		if v < 0.06:
			v -= 0.1 * TICK
		if v > 0.004:
			gas[c] = v
		else:
			gas.erase(c)


func total() -> float:
	var t := 0.0
	for c in gas:
		t += gas[c]
	return t
