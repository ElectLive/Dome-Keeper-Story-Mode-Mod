extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #222 gap probe, client half: does the client see the host's story beat; can
# it buy from the shop; does the gadget shop (New Gadget) work from a client.
# Pair: t222_probe_host.

const TIMEOUT := 420
const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"netjoin": true}


func _cost(id: String) -> int:
	var c = GameWorld.upgrades.get(id, {}).get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


func run(h) -> void:
	var me: String = Keepers.first().playerId
	await shared(h, "beat_open", 60.0)
	await h.wait(2.0)
	h.note("client during host beat", {"beat box": h.beat_box() != null, "paused": GameWorld.paused})
	h.check("client sees the host's story beat", h.beat_box() != null)
	await h.shot("client_during_beat")
	await shared(h, "go", 60.0)
	await h.wait(1.0)
	# A plain shop buy.
	var m0: int = int(Data.ofOr("team1.inventory.money", 0))
	GameWorld.buyUpgrade("team1.storyheatshield1", "team1", me)
	await h.wait(2.0)
	var m1: int = int(Data.ofOr("team1.inventory.money", 0))
	h.check("client buys Heat Shielding I", GameWorld.boughtUpgrades.has("team1.storyheatshield1") and m0 - m1 == _cost("team1.storyheatshield1"), {"paid": m0 - m1, "price": _cost("team1.storyheatshield1")})
	# The gadget shop.
	var entries: Array = GadgetShop.entries("team1")
	var price: int = _cost(entries[0])
	Level.stage.openStoryGadgetChoice("team1", me)
	var popup_open: bool = await h.until(func():
		var p = Level.stage.currentGadgetPopupByPlayerId.get(me, null)
		return p != null and is_instance_valid(p) and p.is_inside_tree(), 6.0)
	h.check("gadget shop popup opens on the client", popup_open)
	await h.wait(1.5)
	await h.shot("client_gadget_offers")
	var offers: Array = GadgetShop.offers("team1", me)
	h.note("client offers", offers)
	if offers.is_empty():
		h.check("client has gadget offers", false)
		return
	var m2: int = int(Data.ofOr("team1.inventory.money", 0))
	Level.stage.onGadgetSelected(offers[0], CONST.GADGET, me, "team1")
	await h.wait(3.0)
	var m3: int = int(Data.ofOr("team1.inventory.money", 0))
	h.note("after client gadget pick", {"paid": m2 - m3, "price": price, "entry bought": GameWorld.boughtUpgrades.has(entries[0]), "pick bought": GameWorld.boughtUpgrades.has(offers[0])})
	h.check("client gadget pick pays the New Gadget I price and marks it bought", m2 - m3 == price and GameWorld.boughtUpgrades.has(entries[0]), {"paid": m2 - m3, "price": price})
	await h.shot("client_after_gadget")
