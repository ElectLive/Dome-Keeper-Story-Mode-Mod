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
# - Data a client got from a big message could be older than a small change
#   that overtook it; the host sends what went stale again (#242, _host_resend).
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

# The settled resend (#242): see _host_resend.
const RESEND_PREFIXES := ["team1.story.", "story.", "team1.inventory.", "team1.suit."]
# The host's own save blobs (save_blob): never sent.
const HOST_ONLY := ["story.lava", "story.gas"]
const RESEND_SETTLE := 1.0     # seconds after the last chunked Data message to a peer left
const RESEND_BATCH := 700      # bytes per message: under the chunker's 900, so sent whole

var _client_story := false     # a client's prices and drops are Story Mode's

# peer id -> {"vals": key -> value the chunked Data messages to it carry,
# "full": one of them was a full sync, "story": it reached LEVEL_STAGE_SYNC,
# "out": msec one was last seen in flight}
var _resend_wait: Dictionary = {}
var _resend_read: Dictionary = {}   # chunker request ids already read
var _resend_synced: Dictionary = {} # peer id -> true while in LEVEL_STAGE_SYNC
# Playtests: false turns the resend off (t242 shows the race without it);
# every resend made, newest last.
static var resend_on := true
static var resends: Array = []


static func online() -> bool:
	return Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SINGLEPLAYER \
		and Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SPLITSCREEN


static func is_client() -> bool:
	return Network.is_client()


# The lava's and the gas's save blob (story.lava, story.gas: tens of KB) goes
# into Data for vanilla's save. Online, Data.apply would also send it to every
# client as one big delta at each autosave (every wave's start and end), which
# holds up the chunker's other Data messages to them (#246); clients get the
# lava and gas from the host's stream instead, so the host keeps it to itself.
static func save_blob(key: String, blob: String) -> void:
	if online() and not is_client():
		Data.server_apply(key, blob)
	else:
		Data.apply(key, blob)


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
		_host_resend()


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


# --- the settled resend (#242) -------------------------------------------------
# Vanilla sends Data to a client in two ways: a full copy of Data.values when it
# reaches a stage (Network: client.full_data_sync; at the start of a run and on
# a late join), and each network tick a delta of what changed (DataSynchronizer;
# what changed while the client was loading goes out in one go when it reaches
# LEVEL_STAGE_SYNC). Both go through the chunker: a message under 900 bytes is
# sent at once, a bigger one a few chunks a frame. So a small delta the host
# sends after a big message can reach the client first, and the big message's
# older values then overwrite it; vanilla doesn't send the key again until it
# changes. Seen: the boss state, money and water set as a client came into sync
# read "" and 0 there for good.
#
# So the host reads every chunked Data message to a client while it is in
# flight, and once none is left and they have had a moment to land, sends that
# client once more, as vanilla's own delta message, every key whose value now
# differs from what those messages carried (and, after a full sync, keys that
# weren't in it). After the client reaches LEVEL_STAGE_SYNC it also gets every
# Story Mode key (story, money and inventory, suit) whatever they carried.
# The resend goes in messages small enough to be sent whole, so they keep their
# order with later deltas.

func _host_resend() -> void:
	var now: int = Time.get_ticks_msec()
	var flying: Dictionary = {}
	var outgoing: Dictionary = Network.chunker.outgoing_rpcs
	for id in outgoing:
		var r = outgoing[id]
		if r.is_sent() or (r.request_type != Chunker.ChunkRequestType.DATA_FULL_SYNC and r.request_type != Chunker.ChunkRequestType.DATA_DELTA_SYNC):
			continue
		flying[r.target_peer_id] = true
		if _resend_read.has(id):
			continue
		_resend_read[id] = true
		var w: Dictionary = _wait(r.target_peer_id)
		var full: bool = r.request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC
		var vals: Dictionary = _message_values(r, full)
		if full:
			w["full"] = true
			w["vals"] = vals    # a full sync replaces everything before it
		else:
			w["vals"].merge(vals, true)
	for id in _resend_read.keys():
		if not outgoing.has(id):
			_resend_read.erase(id)
	var peers: Dictionary = {}
	for c in Network.clients:
		var p: int = c.peer_id
		peers[p] = true
		var in_sync: bool = c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC
		if not in_sync:
			_resend_synced.erase(p)
			continue
		if not _resend_synced.has(p):
			_resend_synced[p] = true
			_wait(p)["story"] = true
		if not _resend_wait.has(p):
			continue
		var w: Dictionary = _resend_wait[p]
		if flying.has(p) or not w.has("out"):
			w["out"] = now
			continue
		if now - int(w["out"]) < int(RESEND_SETTLE * 1000.0):
			continue
		_resend_wait.erase(p)
		if resend_on:
			_resend(p, w)
	for p in _resend_wait.keys():
		if not peers.has(p):
			_resend_wait.erase(p)
	for p in _resend_synced.keys():
		if not peers.has(p):
			_resend_synced.erase(p)


func _wait(peer: int) -> Dictionary:
	if not _resend_wait.has(peer):
		_resend_wait[peer] = {"vals": {}, "full": false, "story": false}
	return _resend_wait[peer]


# The Data values a chunked message carries: its bound arguments are
# (tick, var_to_bytes(changes)) for a delta, (size, zstd bytes) or (tick, size,
# zstd bytes) for a full sync.
func _message_values(r, full: bool) -> Dictionary:
	var buf := PackedByteArray()
	for ch: PackedByteArray in r.chunks:
		buf.append_array(ch)
	var args = bytes_to_var(buf)
	if not args is Array or args.size() < 2 or not args[-1] is PackedByteArray:
		return {}
	var bytes: PackedByteArray = args[-1]
	if full:
		if not args[-2] is int:
			return {}
		bytes = bytes.decompress(args[-2], FileAccess.CompressionMode.COMPRESSION_ZSTD)
	var vals = bytes_to_var(bytes)
	return vals if vals is Dictionary else {}


func _resend(peer: int, w: Dictionary) -> void:
	var vals: Dictionary = w["vals"]
	var keys: Array = []
	var stale := 0
	for k in Data.values:
		if k in HOST_ONLY:
			continue
		if vals.has(k):
			if not _same(vals[k], Data.values[k]):
				keys.append(k)
				stale += 1
				continue
		elif w["full"]:
			keys.append(k)
			stale += 1
			continue
		if w["story"] and _story_key(String(k)):
			keys.append(k)
	if keys.is_empty():
		return
	var batch: Dictionary = {}
	var size := 0
	var messages := 0
	for k in keys:
		var n: int = var_to_bytes(Data.values[k]).size() + String(k).length() + 8
		if size + n > RESEND_BATCH and not batch.is_empty():
			_send_delta(peer, batch)
			messages += 1
			batch = {}
			size = 0
		batch[k] = Data.values[k]
		size += n
	if not batch.is_empty():
		_send_delta(peer, batch)
		messages += 1
	resends.append({"peer": peer, "keys": keys.size(), "stale": stale, "messages": messages, "story": w["story"], "msec": Time.get_ticks_msec()})
	ModLoaderLog.info("Data resent to peer %d once its big messages landed: %d keys (%d changed since), %d messages" % [peer, keys.size(), stale, messages], Story.LOG)


# Vanilla's delta message, to one client (DataSynchronizer.on_network_tick).
func _send_delta(peer: int, batch: Dictionary) -> void:
	Network.chunker.send(peer, Chunker.ChunkRequestType.DATA_DELTA_SYNC, Data.synchronizer.remote_data_call.bind(Network.tick_count, var_to_bytes(batch)))


static func _story_key(k: String) -> bool:
	for pre: String in RESEND_PREFIXES:
		if k.begins_with(pre):
			return true
	return false


static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


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


# --- lava (#227) ---------------------------------------------------------------
# The RPCs go through this node: it sits at the same path on every peer from
# start-up, while a map's LavaField only exists during a run (an RPC to a node a
# peer doesn't have is an error). A client without a field drops the cells; it
# asks for a full snapshot once its field is built.

static var _inst = null


func _enter_tree() -> void:
	_inst = self


static func _lava():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null("StoryLavaField")


# Host -> every client: changed lava cells.
static func lava_cells(data: PackedByteArray) -> void:
	if _inst != null:
		_inst.rpc("_lava_cells", data, false)


@rpc("authority", "call_remote", "reliable")
func _lava_cells(data: PackedByteArray, full: bool) -> void:
	var f = _lava()
	if f != null and f.net_client:
		f.net_apply(data, full)


# Client -> host: send me all the lava.
static func lava_full_request() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_lava_full_request")


@rpc("any_peer", "call_remote", "reliable")
func _lava_full_request() -> void:
	var f = _lava()
	if f != null and not f.net_client:
		rpc_id(multiplayer.get_remote_sender_id(), "_lava_cells", f.net_full(), true)


# Host -> every client: lava water turned to rock.
static func lava_harden(cells: PackedVector2Array) -> void:
	if _inst != null and online():
		_inst.rpc("_lava_harden", cells)


@rpc("authority", "call_remote", "reliable")
func _lava_harden(cells: PackedVector2Array) -> void:
	var f = _lava()
	if f != null and f.net_client:
		f.net_harden(cells)


# Client -> host: my keeper died in the heat (the host takes the money, plays the beat).
static func lava_died(player_id: String) -> void:
	if _inst != null:
		_inst.rpc_id(1, "_lava_died", player_id)


@rpc("any_peer", "call_remote", "reliable")
func _lava_died(player_id: String) -> void:
	var f = _lava()
	var k = Keepers.getKeeper(player_id) if Keepers.hasKeeper(player_id) else null
	if f == null or k == null or k.peerId != multiplayer.get_remote_sender_id():
		return
	f.team_death(k)


# Client -> host: my keeper broke into the boss chamber (#95 wakes the horror).
static func chamber_reached() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_chamber_reached")


@rpc("any_peer", "call_remote", "reliable")
func _chamber_reached() -> void:
	if Story.is_story():
		load("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd").wake()


# --- gas (#228) ----------------------------------------------------------------
# As the lava: the host's GasField streams, a client's draws.

static func _gas():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null("StoryGasField")


# Host -> every client: gas that changed (or all of it, `full`).
static func gas_cells(data: PackedByteArray, full: bool) -> void:
	if _inst != null:
		_inst.rpc("_gas_cells", data, full)


@rpc("authority", "call_remote", "reliable")
func _gas_cells(data: PackedByteArray, full: bool) -> void:
	var f = _gas()
	if f != null and f.net_client:
		f.net_apply(data, full)


# Client -> host: send me all the gas.
static func gas_full_request() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_gas_full_request")


@rpc("any_peer", "call_remote", "reliable")
func _gas_full_request() -> void:
	var f = _gas()
	if f != null and not f.net_client:
		rpc_id(multiplayer.get_remote_sender_id(), "_gas_cells", f.net_full(), true)


# Client -> host: I bought Vent the Dome (vanilla tells only the buyer's
# instance that an upgrade was bought; the dome's gas is the host's).
static func gas_vent() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_gas_vent")


@rpc("any_peer", "call_remote", "reliable")
func _gas_vent() -> void:
	var f = _gas()
	if f != null and not f.net_client and f.dome != null:
		f.dome.vent()


# --- tiles the host breaks itself (#228) ---------------------------------------
# Vanilla sends clients a tile's hits (Tile.hit), not Map.destroyTile, which is
# how gas rock bursts and magma melts. Host -> every client: break this tile
# too. A client only breaks tiles it has made, and one deep in rock may be
# unrevealed there, so it is revealed everywhere first, as vanilla does.
static func tile_break(map, c: Vector2i) -> void:
	if _inst == null or not online() or is_client():
		return
	map.networkRevealTile(Vector2(c), 0.0)
	_inst.rpc("_tile_break", c)


@rpc("authority", "call_remote", "reliable")
func _tile_break(c: Vector2i) -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.isMapReady():
		return
	if not map.tiles.has(Vector2(c)):
		map.revealTile(Vector2(c))
	var tile = map.tiles.get(Vector2(c))
	if tile != null and is_instance_valid(tile):
		map.destroyTile("team1", "", tile)
