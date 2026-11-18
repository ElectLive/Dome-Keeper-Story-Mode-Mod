extends "res://content/gadgets/suitblaster/SuitBlaster.gd"

# The Suit Blaster on an online client (#253): its gadget and HUD can be made
# before the Data with its keys lands. The host adds an upgrade, sends the Data
# delta, then the RPC that adds the gadget on clients (GameWorld.
# serverAddUpgrade). While a big Data message to that client is still being
# sent in chunks, the mod's chunker queues the delta behind it (net/
# ordered_chunker.gd, #246) and the RPC goes past. SuitBlaster.propertyChanged
# then took away a maxcharge that was not there yet (a script error), and the
# HUD read the charge keys every frame until they landed. The boss dev gear
# does that (one big delta for max drill, jetpack, Laser IV, ...); bought in
# the shop or picked as a gadget on its own it was not seen. t253_mp_blaster_*
# `--bigdelta` makes it happen every time, in Relic Hunt as well: the chunker
# is the mod's in every mode, so this is too.
#
# On a client the missing keys get vanilla's starting values (a full charge of
# one) until the host's arrive and replace them. A client can't apply Data, so
# nothing else changes. The host is untouched.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

const KEYS := [".suitblaster.maxcharge", ".suitblaster.charge"]


func _ready():
	if not Network.is_server():
		for key: String in [teamId + KEYS[0], playerId + KEYS[1]]:
			if not Data.values.has(key):
				Data.values[key] = 1.0
				ModLoaderLog.info("Suit Blaster: %s not here yet, stand-in 1.0 until the host's lands" % key, Story.LOG)
	super()
