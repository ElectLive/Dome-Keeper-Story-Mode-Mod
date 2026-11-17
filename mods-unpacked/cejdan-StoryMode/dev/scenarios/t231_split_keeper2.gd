extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #231: splitscreen, every local keeper. Two devices join in the loadout and
# start a Story Mode run; then keeper 2 (the gamepad's, not keeper 1) goes
# into lava, overheats and is recalled, into gas, and deep for a depth beat and
# a heat line. Each value must be keeper 2's (keeper 1 stays cool and clean in
# the dome), shown over keeper 2 and in keeper 2's split view. Both views are
# shot at each step.

const TIMEOUT := 420
const Split = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t231_split_restart.gd")
const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")

var k1
var k2
var lava
var gas


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await Split.start_split(h):
		return
	k1 = Keepers.getLocalKeeperByDeviceId(0)
	k2 = Keepers.getLocalKeeperByDeviceId(1)
	h.check("keeper 2 is the gamepad's", k2 != null and k2.playerId == "player2" and k1.playerId == "player1", [k1.playerId, k2.playerId])
	lava = Level.map.get_node("StoryLavaField")
	gas = Level.map.get_node("StoryGasField")
	lava.magma.clear()
	gas.rock.clear()
	lava.freeze_flow = true
	gas.freeze_flow = true
	# Both keepers' recall spots are where they stood when the run began.
	h.note("recall spots", lava.recall_spots)
	h.check("a recall spot per keeper", lava.recall_spots.has("player1") and lava.recall_spots.has("player2"), lava.recall_spots.keys())
	var spot2: Vector2 = lava.recall_spots.get("player2", Vector2.ZERO)
	h.check("both views", Level.viewports.viewportContainersByKeeperId.size() == 2 and Keepers.isSplitScreen, Level.viewports.viewportContainersByKeeperId.keys())

	# ---- 1. keeper 2 in lava: its heat, its bar; then it overheats and is recalled
	var room := _find_biome_row(1, 8)
	await h.dig_room(room + Vector2i(-2, -1), room + Vector2i(2, 1))
	await h.teleport_tile(room, k2)
	k2.set("gravity_scale", 0.0)
	await h.wait(0.5)
	for x in range(-2, 3):
		var c: Vector2i = room + Vector2i(x, 1)
		lava.mass[c] = 1.0
		lava.shown[c] = 1.0
		c = room + Vector2i(x, 0)
		lava.mass[c] = 1.0
		lava.shown[c] = 1.0
	lava.wake_all()
	h.snap_camera(k2)
	await h.wait(1.0)
	h.check("keeper 2 is in lava", lava.keeper_in_lava(k2), Level.map.getTileCoord(k2.global_position))
	var heat2: float = lava.heat_of(k2)
	h.note("heat after 1 s", {"player1": lava.heat_of(k1), "player2": heat2})
	h.check("keeper 2 heats up", heat2 > 5.0, heat2)
	h.check("keeper 1 stays cool", lava.heat_of(k1) == 0.0, lava.heat_of(k1))
	h.check("lava field's `heat` is still keeper 1's", lava.heat == lava.heat_of(k1), lava.heat)
	await h.shot("k2_in_lava")
	# The lava is far from keeper 1's camera: it must be drawn for keeper 2's view.
	var vis: Array = lava._visible_cells()
	h.check("lava on keeper 2's view is in the draw list", vis.has(room) and vis.has(room + Vector2i(0, 1)), {"cells": vis.size(), "views": lava._view_boxes})
	var recalls0: int = lava.recalls
	var k1_pos: Vector2 = k1.global_position
	var overheated: bool = await h.until(func(): return lava.recalls > recalls0, 20.0)
	h.check("keeper 2 overheats and is recalled", overheated, {"recalls": lava.recalls, "heat2": lava.heat_of(k2)})
	await h.wait(1.5)
	h.note("after recall", {"k2": Level.map.getTileCoord(k2.global_position), "spot2": Level.map.getTileCoord(spot2), "heat2": lava.heat_of(k2), "k1 moved": k1.global_position.distance_to(k1_pos)})
	h.check("keeper 2 is home", k2.global_position.distance_to(spot2) < 40.0, [k2.global_position, spot2])
	h.check("keeper 2's heat is cleared", lava.heat_of(k2) < 5.0, lava.heat_of(k2))
	h.check("keeper 1 stayed put", k1.global_position.distance_to(k1_pos) < 4.0, k1.global_position.distance_to(k1_pos))
	h.snap_camera(k2)
	await h.shot("k2_recalled")
	for c in lava.mass.keys():
		lava.mass.erase(c)
		lava.shown.erase(c)
	lava.wake_all()

	# ---- 2. keeper 2 in gas: its toxin, its bar, a vignette in its view only
	var groom := room + Vector2i(8, 0)
	await h.dig_room(groom + Vector2i(-2, -1), groom + Vector2i(2, 1))
	await h.teleport_tile(groom, k2)
	k2.set("gravity_scale", 0.0)
	var cells: Array = []
	for y in range(-1, 2):
		for x in range(-2, 3):
			cells.append(groom + Vector2i(x, y))
	gas.fill(cells, 1.2)
	await h.until(func(): return gas.toxin_of(k2) >= 80.0, 6.0)
	gas.freeze_toxin = true
	await h.wait(1.0)
	var fx = gas.fx
	h.note("toxin", {"player1": gas.toxin_of(k1), "player2": gas.toxin_of(k2), "views": fx.views.keys()})
	h.check("keeper 2's toxin fills", gas.toxin_of(k2) >= 80.0, gas.toxin_of(k2))
	h.check("keeper 1's stays clean", gas.toxin_of(k1) == 0.0, gas.toxin_of(k1))
	h.check("the vignette is in keeper 2's view, not keeper 1's", fx.views["player2"]["rect"].visible and not fx.views["player1"]["rect"].visible
		and fx.views["player2"]["layer"].custom_viewport == Level.viewports.getViewportContainer(k2).viewport,
		[fx.views["player1"]["vignette"], fx.views["player2"]["vignette"]])
	h.check("a gas look per view", gas.looks.size() == 2, gas.looks.keys())
	h.check("keeper 2's gas look follows keeper 2", gas.looks.has("player2") and Rect2i(gas.looks["player2"].c0, gas.looks["player2"].WIN).has_point(groom), gas.looks["player2"].c0 if gas.looks.has("player2") else null)
	h.snap_camera(k2)
	await h.shot("k2_in_gas")
	gas.freeze_toxin = false
	var gassed0: int = gas.gassed
	recalls0 = lava.recalls
	await h.until(func(): return gas.gassed > gassed0, 6.0)
	await h.wait(1.0)
	h.check("a full bar recalls keeper 2", gas.gassed > gassed0 and lava.recalls > recalls0 and k2.global_position.distance_to(spot2) < 40.0, {"gassed": gas.gassed, "recalls": lava.recalls})
	gas.mass.clear()
	gas.wake_all()
	await h.wait(2.0)

	# ---- 3. keeper 2 deep: the depth beat and the heat line are keeper 2's
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	var deep_beats: Array = []
	for b in range(2, 5):
		for id in BeatData.ids_for("biome:B%d" % b):
			deep_beats.append(id)
			played.erase(id)
	Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))
	var hot := _find_biome_row(LavaData.PASSIVE_HEAT_START_BIOME, 4)
	await h.dig_room(hot + Vector2i(-2, -1), hot + Vector2i(2, 1))
	await h.teleport_tile(hot, k2)
	k2.set("gravity_scale", 0.0)
	var id: String = await h.read_beat("depth_beat", 10.0)
	h.check("a depth beat opens for keeper 2's depth", id in deep_beats, id)
	h.check("deepest biome is keeper 2's", int(Data.ofOr("team1.story.deepest", 0)) >= LavaData.PASSIVE_HEAT_START_BIOME, Data.ofOr("team1.story.deepest", 0))
	# The other biome beats this teleport crossed may queue too; read them.
	for i in 3:
		if await h.read_beat("depth_beat_more%d" % i, 2.0, false) == "":
			break
	h.snap_camera(k2)
	var talk = load("res://mods-unpacked/cejdan-StoryMode/hud/heat_talk.gd").instance()
	var said: bool = await h.until(func(): return talk.shown.any(func(e): return e.get("player") == "player2"), 6.0)
	h.check("keeper 2 says its heat line", said, talk.shown)
	h.check("keeper 1 said nothing", not talk.shown.any(func(e): return e.get("player") == "player1"), talk.shown)
	h.check("keeper 2 has passive heat, keeper 1 none", lava.passive_rate_of(k2) > 0.0 and lava.passive_rate_of(k1) == 0.0, [lava.passive_rate_of(k1), lava.passive_rate_of(k2)])
	await h.wait(0.4)
	await h.shot("k2_deep_heat_line")
	h.note("final", {"heats": lava.heats, "toxins": gas.toxins, "recalls": lava.recalls, "gassed": gas.gassed, "talk": talk.shown})

	# ---- 4. keeper 2 walks with its own gamepad
	await h.teleport_tile(hot, k2)
	k2.set("gravity_scale", 1.0)
	var before: Vector2 = k2.global_position
	await h.pad_stick(1, Vector2(1, 0), 1.0)
	h.check("keeper 2 moves with the gamepad's stick", k2.global_position.distance_to(before) > 10.0, k2.global_position.distance_to(before))


# A tile in the first row at or below `from_y` whose biome is `biome`, a few
# columns left of the shaft.
func _find_biome_row(biome: int, from_y: int) -> Vector2i:
	var td = Level.map.tileData
	for y in range(from_y, 400):
		var c := Vector2i(-6, y)
		if td.get_biomev(c) == biome and td.get_biomev(c + Vector2i(0, 2)) == biome:
			return c + Vector2i(0, 1)
	return Vector2i(-6, from_y)
