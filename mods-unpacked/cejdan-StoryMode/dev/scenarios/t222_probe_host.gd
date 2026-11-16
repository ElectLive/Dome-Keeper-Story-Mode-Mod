extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #222 gap probe, host half: opens the welcome log (does the client see it?),
# then gives the team money for the client's shop and gadget-shop tries, and
# reports what the host saw. Pair: t222_probe_client.

const TIMEOUT := 420
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true, "beats": true, "welcome": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var opened: bool = await h.until(func(): return StoryBeats.is_open(), 15.0)
	h.check("welcome log open on the host", opened)
	share("beat_open", true)
	await h.wait(5.0)
	await h.shot("host_beat")
	h.note("host paused during beat", GameWorld.paused)
	if opened:
		await h.read_beat("welcome", 10.0, false)
	Data.apply("team1.inventory.money", 100000)
	Data.apply("team1.inventory.water", 5)
	share("go", true)
	var entry: String = GadgetShop.entries("team1")[0]
	await h.until(func(): return GameWorld.boughtUpgrades.has(entry), 40.0)
	await h.wait(3.0)
	var gadgets: Array = GameWorld.boughtUpgrades.filter(func(k): return GameWorld.upgrades.get(k, {}).get("type", "") == "gadget")
	h.note("host view after client tries", {"money": Data.ofOr("team1.inventory.money", -1), "entry bought": GameWorld.boughtUpgrades.has(entry), "gadgets": gadgets, "heatshield1": GameWorld.boughtUpgrades.has("team1.storyheatshield1")})
	await host_wait_clients_left(h)
