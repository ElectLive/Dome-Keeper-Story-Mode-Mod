extends "res://content/gadgets/suitblaster/SuitBlasterHud.gd"

# The Suit Blaster's HUD on an online client (#253): it can be made before the
# Data with its keys lands, and then read them every frame ("Tried to access
# unknown data player2.suitblaster.charge"). Why, in the SuitBlaster.gd
# extension beside this one. On a client the missing keys get vanilla's
# starting values until the host's arrive and replace them.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

static var stand_ins := 0    # keys given a stand-in (t253_mp_blaster_client, #261)


func init():
	if not Network.is_server():
		for key: String in [teamId + ".suitblaster.maxcharge", playerId + ".suitblaster.charge"]:
			if not Data.values.has(key):
				Data.values[key] = 1.0
				stand_ins += 1
				ModLoaderLog.info("Suit Blaster HUD: %s not here yet, stand-in 1.0 until the host's lands" % key, Story.LOG)
	super()
