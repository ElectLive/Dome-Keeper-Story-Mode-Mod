extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #253, client half: once the host has given every keeper the Suit Blaster,
# this client's keeper has it, its charge keys are here and its HUD shows.
# The error scan fails the run on SuitBlaster.gd's script error or the HUD's
# unknown-key reads. Pair: t253_mp_blaster_host.
# #261: with `--give=<gadget>` the host gives another gadget instead. Either
# way, each of the gadget's Data keys must have been here when the RPC that
# adds it arrived (GameWorld.upgradeAdded), and the Suit Blaster's stand-ins
# (extensions/.../SuitBlaster.gd, #253) must not have been needed.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const TIMEOUT := 300

var _at_add: Dictionary = {}   # upgrade id -> the Data keys here when it was added


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var give: String = Story.user_arg("give", "suitblaster")
	GameWorld.upgradeAdded.connect(func(id: String, _team: String):
		if id.ends_with("." + give) and not _at_add.has(id):
			_at_add[id] = Data.values.keys())
	var given = await shared(h, "given", 150.0)
	h.check("the host gave the %s" % give, given is Dictionary, given)
	if not given is Dictionary:
		return
	await h.wait(2.0)
	var k = Story.local_keeper()
	h.check("this client's keeper has the %s" % give, k != null and GameWorld.boughtUpgrades.has(k.playerId + "." + give), k.playerId if k else null)
	if give == "suitblaster":
		var gadget = null
		if k != null:
			for c in k.get_children():
				if str(c.get_script().resource_path if c.get_script() else "").ends_with("SuitBlaster.gd"):
					gadget = c
		h.check("this client's keeper has the Suit Blaster", gadget != null, k.playerId if k else null)
		var charge = Data.ofOr(k.playerId + ".suitblaster.charge", null) if k else null
		var maxc = Data.ofOr(k.teamId + ".suitblaster.maxcharge", null) if k else null
		h.check("its charge keys reached this client", charge != null and maxc != null, {"charge": charge, "maxcharge": maxc})
	# #261: the gadget's keys were here before (or with) the RPC that added it.
	var keys: Array = given.get("keys", [])
	h.check("the host listed the gadget's Data keys", not keys.is_empty(), keys.size())
	var late: Dictionary = {}
	for id in _at_add:
		var have: Array = _at_add[id]
		for key in keys:
			# A key of another keeper's gadget is that keeper's, not this one's.
			var owner: String = String(key).get_slice(".", 0)
			if owner.begins_with("player") and not String(id).begins_with(owner + "."):
				continue
			if not have.has(key):
				late[key] = true
	h.note("upgrades added here", _at_add.keys())
	h.check("the RPC adding the %s came here (%d)" % [give, _at_add.size()], _at_add.size() >= 1, _at_add.keys())
	h.check("every %s key was here when it was added (#261)" % give, late.is_empty(), late.keys())
	# The extensions sit at vanilla's paths (extensions/installer.gd).
	var blaster = load("res://content/gadgets/suitblaster/SuitBlaster.gd")
	var hud = load("res://content/gadgets/suitblaster/SuitBlasterHud.gd")
	var stand: Dictionary = {"gadget": blaster.get("stand_ins"), "hud": hud.get("stand_ins")}
	h.check("no Suit Blaster stand-in was needed (#261)", stand["gadget"] == 0 and stand["hud"] == 0, stand)
	await h.shot("client_blaster")
