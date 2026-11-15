extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 199 (spike): the gas's look as a GPU fluid simulation.
#
# A cavern in solid rock:
#
#   ...##...........      an alcove in the ceiling (a trap)   y -1
#   ................      the upper room                      y 0..2
#   ########.#######      the shaft                           y 3..5
#   #PPP####.#######      P the pressurised pocket, sealed    y 4..5
#   #PPP#....#######
#
# The pocket's wall is opened, the gas jets out, climbs the shaft and settles
# under the room's ceiling. Then the keeper flies through it, and the camera
# jumps to see whether the field stays put.

const Spike = preload("res://mods-unpacked/cejdan-StoryMode/gas/spike/gas_spike.gd")
const TIMEOUT := 240

var OX := 0
var OY := 30
var td
var spike


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 3, oy + 11):
		for x in range(ox - 2, ox + 18):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _frame_ms(h, frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	await h.frames(frames)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / frames


func run(h) -> void:
	h.disable_waves()
	td = Level.map.tileData
	var lava = Level.map.get_node_or_null("StoryLavaField")
	if lava != null:
		lava.magma.clear()
		lava.mass.clear()
		lava.shown.clear()
	var found := false
	for oy in range(20, 110):
		for ox in range(-40, 30):
			if not found and _fits(ox, oy):
				OX = ox
				OY = oy
				found = true
	h.check("found solid rock for the cavern", found, [OX, OY])
	var around: Array = []
	for y in range(-3, 11):
		for x in range(-2, 18):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = [_c(3, -1), _c(4, -1)]
	for x in 16:
		for y in 3:
			open.append(_c(x, y))
	for y in range(3, 6):
		open.append(_c(8, y))
	for x in range(5, 8):
		open.append(_c(x, 5))
	var pocket: Array = []
	for x in range(1, 4):
		for y in range(4, 6):
			pocket.append(_c(x, y))
	await h.clear_tiles(open + pocket)
	await h.teleport_tile(_c(10, 2))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(3.0)
	h.snap_camera()
	var base_ms: float = await _frame_ms(h, 120)

	spike = Spike.new()
	spike.name = "GasSpike"
	Level.map.add_child(spike)
	spike.setup(Level.map)
	await h.frames(10)
	var fmt: int = spike._vel_a.get_texture().get_image().get_format()
	h.check("the fields are float", fmt == Image.FORMAT_RGBAH or fmt == Image.FORMAT_RGBAF, fmt)
	var empty_ms: float = await _frame_ms(h, 120)

	# ---- 1. the sealed pocket
	for c in pocket:
		spike.gas[c] = 5.0
	await h.wait(1.0)
	await h.shot("sealed")
	h.check("the sealed pocket keeps its gas", absf(spike.total() - 5.0 * pocket.size()) < 0.05, spike.total())

	# ---- 2. the breach
	await h.clear_tiles([_c(4, 5)])
	await h.burst("breach", 24, 3)
	await h.burst("climb", 16, 6)
	await h.wait(4.0)
	await h.burst("settled", 12, 5)
	var in_room := 0.0
	for c in spike.gas:
		if c.y <= OY + 2:
			in_room += spike.gas[c]
	h.check("most of the gas ends up under the room's ceiling", in_room > 0.6 * spike.total(), [in_room, spike.total()])
	h.check("the alcove holds gas", spike.gas.get(_c(3, -1), 0.0) > 0.8, spike.gas.get(_c(3, -1), 0.0))

	# ---- 3. the keeper flies through it
	await h.teleport_tile(_c(14, 0))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(0.5)
	h.down("ui_left")
	await h.burst("wake", 30, 3)
	h.up("ui_left")
	await h.burst("after_wake", 8, 6)
	var full_ms: float = await _frame_ms(h, 120)

	# ---- 4. the camera jumps: the gas must stay where it is in the world
	var cell: Vector2i = _c(3, -1)
	var before: float = _dye_at(cell)
	var c0_before: Vector2i = spike.c0
	await h.shot("before_jump")
	await h.teleport_tile(_c(6, 1))
	h.keeper().set("gravity_scale", 0.0)
	await h.frames(4)
	var after: float = _dye_at(cell)
	await h.shot("after_jump")
	h.check("the window moved with the camera", spike.c0 != c0_before, [c0_before, spike.c0])
	h.check("the gas stayed put in the world", before > 0.5 and absf(after - before) < 0.25, [before, after])

	h.note("cost", {"frame_ms_no_spike": base_ms, "frame_ms_spike_no_gas": empty_ms, "frame_ms_spike_gas": full_ms,
		"spike_cpu_ms": float(spike.cpu_us) / 1000.0 / maxi(spike.cpu_frames, 1), "fps": Engine.get_frames_per_second()})
	spike._show_mat.set_shader_parameter("raw", 1.0)
	await h.shot("raw_field")
	spike._show_mat.set_shader_parameter("raw", 2.0)
	await h.shot("raw_velocity")


# The drawn density at the middle of a tile, read back from the dye field.
func _dye_at(cell: Vector2i) -> float:
	var img: Image = spike._dye_a.get_texture().get_image()
	var p: Vector2i = (cell - spike.c0) * Spike.SUB + Vector2i(4, 4)
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return -1.0
	return img.get_pixel(p.x, p.y).r
