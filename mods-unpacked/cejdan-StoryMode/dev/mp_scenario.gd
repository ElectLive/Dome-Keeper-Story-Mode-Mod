extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Shared steps for online multiplayer scenarios (#223), run in pairs by
# dev/mp_playtest.ps1: a host scenario (boot `nethost: true`) and a client
# scenario (boot `netjoin: true`).

const DEV_SHARE := "story.dev.share"


# Host: waits in the loadout for `players` lobby members, picks Story Mode,
# starts the run and waits until it is playable. False if any step failed.
func host_start(h, players: int = 2) -> bool:
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	var joined: bool = await h.until(func(): return Lobby.members.size() >= players, 120.0)
	h.check("players joined the lobby", joined, Lobby.members.size())
	if not joined:
		return false
	var spawned: bool = await h.until(func():
		if Level.loadout.keepers.size() < players:
			return false
		for lk in Level.loadout.keepers:
			if lk.keeper == null:
				return false
		return true, 30.0)
	h.check("loadout keepers spawned", spawned, Level.loadout.keepers.size())
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	h.check("story mode selected", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return false
	h.mute_beats()
	h.disable_waves()
	return true


# Host: shares values with the client scenario through Data (synced).
func share(key: String, value) -> void:
	var d: Dictionary = {}
	var have = Data.ofOr(DEV_SHARE, "")
	if have is String and have != "":
		d = JSON.parse_string(have)
	d[key] = value
	Data.apply(DEV_SHARE, JSON.stringify(d))


# Client: a value the host shared, waiting for it up to `timeout` seconds.
func shared(h, key: String, timeout: float = 30.0):
	var get_it := func():
		var have = Data.ofOr(DEV_SHARE, "")
		if not have is String or have == "":
			return null
		return JSON.parse_string(have).get(key)
	await h.until(func(): return get_it.call() != null, timeout)
	return get_it.call()


# Host: stays up until every client has left (or `timeout`).
func host_wait_clients_left(h, timeout: float = 180.0) -> void:
	var left: bool = await h.until(func(): return Network.clients.is_empty(), timeout)
	h.note("clients left", left)


func keeper_rows(h) -> Array:
	var rows: Array = []
	for k in Keepers.getAll():
		rows.append({"player": k.playerId, "peer": k.peerId, "local": k.peerId == h.multiplayer.get_unique_id(), "tile": Level.map.getTileCoord(k.global_position)})
	return rows
