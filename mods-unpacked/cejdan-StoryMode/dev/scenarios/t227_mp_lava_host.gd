extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #227: host half. Digs a room beside a magma pocket and breaches it, then
# shares its lava (cell count, total mass, a sample of cells) every second so
# the client can compare. Money is set to $1000 for the client's death check.
# Pair: t227_mp_lava_client.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var lava = Level.map.get_node("StoryLavaField")
	Data.apply("team1.inventory.money", 1000)
	# A pocket in the upper biomes with room to dig beside it.
	var pick = null
	for m: Vector2i in lava.magma:
		if m.y >= 12 and m.y <= 40 and not lava.magma.has(m + Vector2i.RIGHT * 2) and (pick == null or m.y < pick.y):
			pick = m
	h.check("found a pocket", pick != null, pick)
	if pick == null:
		return
	var room_a: Vector2i = pick + Vector2i(1, -1)
	var room_b: Vector2i = pick + Vector2i(4, 4)
	h.note("client states at dig", Network.clients.map(func(c): return c.connection_state))
	await h.dig_room(room_a, room_b)
	await h.wait(1.0)
	share("room", [room_a.x, room_a.y, room_b.x, room_b.y])
	await h.clear_tiles([pick])
	h.note("breached", pick)
	for i in 25:
		share("lava", _state(lava))
		await h.wait(1.0)
		if i == 3:
			h.keeper().teleport(Level.map.getTilePos(room_a + Vector2i(1, 0)))
			h.snap_camera()
			await h.shot("host_breach")
	share("lava_final", _state(lava))
	h.note("host lava", _state(lava))
	await h.shot("host_end")
	await host_wait_clients_left(h)
	h.note("money at end", Data.ofOr("team1.inventory.money", -1))


static func _state(lava) -> Dictionary:
	var total := 0.0
	var cells: Array = []
	for c in lava.mass:
		total += lava.mass[c]
		if c.y < 60:
			cells.append([c.x, c.y, snappedf(lava.mass[c], 0.001)])
	return {"t": Time.get_ticks_msec(), "n": lava.mass.size(), "total": total, "upper": cells}
