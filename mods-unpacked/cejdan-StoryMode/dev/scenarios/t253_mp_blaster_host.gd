extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #253, host half: both keepers get the Suit Blaster while a client watches,
# and the client must log no script error or unknown Data key for it
# (t253_mp_blaster_client; dev/log_scan.ps1 counts them).
#   default:          Story Mode's shop: the team buys the Suit Blaster entry
#                     (gamemode/Storymode.gd grants it to every keeper)
#   --devgear:        the boss dev gear (dev/boss_dev.gd: max drill, jetpack,
#                     Laser IV, ... in one frame), then the client's keeper's
#   --vanilla:        a Relic Hunt run, each keeper picking it as a gadget
#                     (LevelStage.addGadgetUpgrade's grant)
#   --early:          (with any of them) given the moment the client is in sync
#   --bigdelta:       (with any of them) right behind a chunked Data delta
# Pair: t253_mp_blaster_client.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	var vanilla: bool = Story.has_user_arg("vanilla")
	if not await host_start(h, 2, "relichunt" if vanilla else "storymode"):
		return
	# `--early`: right after the client is in sync, as the boss dev commands
	# do in t230_mp_boss_*: the host's full Data sync to it is still on its
	# way (chunked), and the gadget's RPC overtakes the Data behind it.
	if not Story.has_user_arg("early"):
		await h.wait(3.0)
	# `--bigdelta`: a 20 KB Data key first, so the next delta is sent in chunks
	# and the Suit Blaster's own delta waits behind it every time.
	if Story.has_user_arg("bigdelta"):
		Data.apply("story.dev.pad", "x".repeat(20000))
		Data.synchronizer.manual_tick()
	var keepers: Array = Keepers.getAll()
	var path: String = "vanilla gadget" if vanilla else ("dev gear" if Story.has_user_arg("devgear") else "shop")
	h.note("giving the Suit Blaster", path)
	if vanilla:
		for k in keepers:
			GameWorld.serverAddUpgrade(k.playerId + ".suitblaster", k.teamId)
	elif Story.has_user_arg("devgear"):
		var given: Array = load(Story.MOD_DIR + "dev/boss_dev.gd").give_gear()
		h.note("dev gear", given)
		for k in keepers:
			if not GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster"):
				GameWorld.serverAddUpgrade(k.playerId + ".suitblaster", k.teamId)
	else:
		Data.apply("team1.inventory.money", 5000)
		await h.wait(0.5)
		GameWorld.buyUpgrade("team1.storysuitblaster", "team1", Keepers.first().playerId)
	var all: bool = await h.until(func(): return keepers.all(func(k): return GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster")), 10.0)
	h.check("every keeper has the Suit Blaster (%s)" % path, all, keepers.map(func(k): return [k.playerId, GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster")]))
	await h.wait(4.0)
	share("given", {"path": path, "players": keepers.map(func(k): return k.playerId)})
	await h.shot("host_blaster")
	await host_wait_clients_left(h, 90.0)
