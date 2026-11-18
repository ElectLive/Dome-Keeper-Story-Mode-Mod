extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #253, client half: once the host has given every keeper the Suit Blaster,
# this client's keeper has it, its charge keys are here and its HUD shows.
# The error scan fails the run on SuitBlaster.gd's script error or the HUD's
# unknown-key reads. Pair: t253_mp_blaster_host.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var given = await shared(h, "given", 150.0)
	h.check("the host gave the Suit Blaster", given is Dictionary, given)
	if not given is Dictionary:
		return
	await h.wait(2.0)
	var k = Story.local_keeper()
	var gadget = null
	if k != null:
		for c in k.get_children():
			if str(c.get_script().resource_path if c.get_script() else "").ends_with("SuitBlaster.gd"):
				gadget = c
	h.check("this client's keeper has the Suit Blaster", gadget != null, k.playerId if k else null)
	var charge = Data.ofOr(k.playerId + ".suitblaster.charge", null) if k else null
	var maxc = Data.ofOr(k.teamId + ".suitblaster.maxcharge", null) if k else null
	h.check("its charge keys reached this client", charge != null and maxc != null, {"charge": charge, "maxcharge": maxc})
	await h.shot("client_blaster")
