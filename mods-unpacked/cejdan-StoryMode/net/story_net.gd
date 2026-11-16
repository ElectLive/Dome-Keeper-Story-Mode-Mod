extends Node

# Story Mode in online multiplayer (#222). Vanilla's netcode carries the map's
# tiles, Data, the shop and the keepers to clients; this node carries the rest
# of a run's setup that only the host does (#225):
#
# - The map generator's facts (map/story_gen.gd: the lava ocean, the boss
#   chamber, pools, gas caverns, ...) are meta on the map data, and vanilla
#   sends clients only the tile layers. The host puts them in Data (MAP_META),
#   which reaches every client, a late joiner too; a client copies them onto
#   its map. Whatever reads them on a client waits for map_meta_ready().
# - GameWorld.prepareLevelStart (and with it mod_main.prepareGameMode) runs
#   only on the host. A client applies Story Mode's prices and iron drop itself.
#
# Lives under the mod's main node (same path on every peer), and polls like the
# lava director. Offline runs (single player, splitscreen) skip all of it.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Prices = preload("res://mods-unpacked/cejdan-StoryMode/data/prices.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

const MAP_META := "story.mapmeta"
# Set on a client's map data once the host's meta is on it.
const SYNCED := "story_meta_synced"
# Map-data meta that stays on the host: the seed rides in saves (#116), the rest
# are generator reports for playtests.
const LOCAL_ONLY := ["story_seed"]

var _client_story := false     # a client's prices and drops are Story Mode's


static func online() -> bool:
	return Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SINGLEPLAYER \
		and Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SPLITSCREEN


static func is_client() -> bool:
	return Network.is_client()


# True once `map`'s story meta can be read: always on the host and offline; on
# a client, once the host's copy has arrived.
static func map_meta_ready(map) -> bool:
	if not is_client():
		return true
	return map != null and map.tileData != null and map.tileData.has_meta(SYNCED)


func _process(_delta: float) -> void:
	if not online():
		return
	if is_client():
		_client_prices()
		if Story.is_story():
			_client_meta()
	elif Story.is_story():
		_host_meta()


# --- host ----------------------------------------------------------------------

func _host_meta() -> void:
	var td = _host_map_data()
	if td == null or not td.has_meta("story_ocean"):
		return
	var have = Data.ofOr(MAP_META, "")
	if have is String and have != "" and have.begins_with("{\"seed\": %d," % Level.levelSeed):
		return
	var metas: Dictionary = {}
	for k: StringName in td.get_meta_list():
		var v = td.get_meta(k)
		if String(k) in LOCAL_ONLY or v is Object:
			continue
		metas[String(k)] = v
	# var_to_str keeps Rect2i and Vector2i; the seed leads, so a check is cheap.
	Data.apply(MAP_META, "{\"seed\": %d, \"meta\": %s}" % [Level.levelSeed, var_to_str(metas)])
	ModLoaderLog.info("Story map facts shared with clients (%d keys)" % metas.size(), Story.LOG)


# The run's map data: the landing stage's while it lands, then the level's.
func _host_map_data():
	if Level.map != null and is_instance_valid(Level.map) and Level.map.tileData != null:
		return Level.map.tileData
	var st = StageManager.currentStage
	if st != null and is_instance_valid(st) and st is LandingStage and st.levelStartData != null:
		var td = st.levelStartData.tileData
		if td != null and is_instance_valid(td):
			return td
	return null


# --- client --------------------------------------------------------------------

func _client_meta() -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or map.tileData == null or map.tileData.has_meta(SYNCED):
		return
	var blob = Data.ofOr(MAP_META, "")
	if not blob is String or not blob.begins_with("{\"seed\": %d," % Level.levelSeed):
		return
	var at: int = blob.find("\"meta\": ")
	var metas = str_to_var(blob.substr(at + 8, blob.length() - at - 9))
	if not metas is Dictionary:
		push_error("Story Mode: the host's map facts did not parse")
		return
	for k: String in metas:
		map.tileData.set_meta(k, metas[k])
	map.tileData.set_meta(SYNCED, true)
	ModLoaderLog.info("Story map facts from the host applied (%d keys)" % metas.size(), Story.LOG)


# Story Mode's prices and iron drop for a Story Mode run, vanilla's otherwise;
# the host's mod_main.prepareGameMode does the same.
func _client_prices() -> void:
	var story: bool = Story.is_story()
	if story == _client_story:
		return
	_client_story = story
	Prices.apply(story)
	Minerals.use_story_iron(story)
	ModLoaderLog.info("Client: Story Mode prices %s" % ("on" if story else "off"), Story.LOG)
