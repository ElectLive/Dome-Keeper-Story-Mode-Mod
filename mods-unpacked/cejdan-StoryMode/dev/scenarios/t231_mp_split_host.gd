extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #231: online and splitscreen mixed. The host plays two local keepers
# (keyboard and a gamepad, split views on the host's screen) and a client
# joins with its own: three keepers. The host's second keeper goes into lava:
# its heat is its own, the recall sends it home and the team pays the
# penalty once; keeper 1 and the client's keeper stay cool. Then into gas.
# Pair: t231_mp_split_client.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true, "splitscreen": true}


func run(h) -> void:
	GameWorld.figuredOutMovementInLoadout = true
	h.check("keyboard joined", await h.join_device(0))
	h.check("gamepad joined", await h.join_device(1))
	if not await host_start(h, 3):
		return
	await h.wait(2.0)
	var k1 = Keepers.getLocalKeeperByDeviceId(0)
	var k2 = Keepers.getLocalKeeperByDeviceId(1)
	h.note("keepers", Keepers.getAll().map(func(k): return [k.playerId, k.peerId, k.deviceId, Keepers.local.has(k)]))
	h.check("three keepers, two of them local", Keepers.getAll().size() == 3 and h.local_keepers().size() == 2 and k2 != null, h.local_keepers().map(func(k): return k.playerId))
	h.check("split views on the host", Level.viewports.viewportContainersByKeeperId.size() == 2, Level.viewports.viewportContainersByKeeperId.keys())
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	lava.magma.clear()
	gas.rock.clear()
	lava.freeze_flow = true
	gas.freeze_flow = true
	Data.apply("team1.inventory.money", 1000)
	var spot2: Vector2 = lava.recall_spots.get(k2.playerId, Vector2.ZERO)
	var room := Vector2i(-7, 12)
	await h.dig_room(room + Vector2i(-2, -1), room + Vector2i(2, 1))
	await h.teleport_tile(room, k2)
	k2.set("gravity_scale", 0.0)
	await h.wait(0.5)
	for x in range(-2, 3):
		for y in [0, 1]:
			lava.mass[room + Vector2i(x, y)] = 1.0
			lava.shown[room + Vector2i(x, y)] = 1.0
	lava.wake_all()
	share("k2", k2.playerId)
	await h.wait(1.0)
	h.check("host keeper 2 heats up, keeper 1 doesn't", lava.heat_of(k2) > 5.0 and lava.heat_of(k1) == 0.0, lava.heats)
	await h.shot("host_k2_in_lava")
	var r0: int = lava.recalls
	h.check("host keeper 2 overheats and is recalled", await h.until(func(): return lava.recalls > r0, 20.0), lava.recalls)
	await h.wait(1.5)
	h.check("host keeper 2 is home", k2.global_position.distance_to(spot2) < 40.0, [k2.global_position, spot2])
	h.check("the team paid half once", int(Data.ofOr("team1.inventory.money", 0)) == 500, Data.ofOr("team1.inventory.money", 0))
	for c in lava.mass.keys():
		lava.mass.erase(c)
		lava.shown.erase(c)
	lava.wake_all()
	share("lava_done", true)
	# Gas on host keeper 2.
	await h.teleport_tile(room, k2)
	k2.set("gravity_scale", 0.0)
	var cells: Array = []
	for y in range(-1, 2):
		for x in range(-2, 3):
			cells.append(room + Vector2i(x, y))
	gas.fill(cells, 1.2)
	await h.until(func(): return gas.toxin_of(k2) >= 60.0, 6.0)
	h.check("host keeper 2's toxin, not keeper 1's", gas.toxin_of(k2) >= 60.0 and gas.toxin_of(k1) == 0.0, gas.toxins)
	await h.shot("host_k2_in_gas")
	gas.mass.clear()
	gas.wake_all()
	# The client checks its side meanwhile.
	await h.wait(10.0)
	share("done", true)
	await host_wait_clients_left(h, 60.0)
