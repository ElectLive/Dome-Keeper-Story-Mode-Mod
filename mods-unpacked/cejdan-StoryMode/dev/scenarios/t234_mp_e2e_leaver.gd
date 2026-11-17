extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #234: the second client of t234_mp_e2e_host (-Client2): buys the Teleporter
# from the gadget shop (the host puts it in the offers) and leaves mid-run.
# Vanilla's TeleporterStation.on_keeper_removed has logged an error on the host
# when such a player left (#234); log_scan.ps1 allowlists it.

const TIMEOUT := 400


func boot() -> Dictionary:
	return {"netjoin": true}


func _popup(me: String):
	var p = Level.stage.currentGadgetPopupByPlayerId.get(me, null)
	return p if p != null and is_instance_valid(p) and p.is_inside_tree() and not p.inputProcessor.desintegrating else null


func run(h) -> void:
	var me: String = Keepers.first().playerId
	await shared(h, "leaver_go", 240.0)
	await h.wait(1.0)
	Level.stage.openStoryGadgetChoice("team1", me)
	var opened: bool = await h.until(func(): return _popup(me) != null and not _popup(me).offersById.is_empty(), 15.0)
	var shown: Array = _popup(me).offersById.keys() if opened else []
	h.check("the leaver's gadget choice offers the Teleporter", opened and shown.has("teleporter"), shown)
	await h.wait(1.0)
	await h.shot("leaver_offers")
	Level.stage.onGadgetSelected("teleporter", CONST.GADGET, me, "team1")
	var got: bool = await h.until(func(): return GameWorld.boughtUpgrades.has("teleporter") and _popup(me) == null, 10.0)
	h.check("the leaver bought the Teleporter", got)
	await h.wait(3.0)
	await h.shot("leaver_teleporter")
