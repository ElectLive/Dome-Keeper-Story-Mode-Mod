extends "res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t231_restart.gd"

# #231: Restart Run in a splitscreen Story Mode run (two local keepers).

const TIMEOUT := 360


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await start_split(h):
		return
	await h.hold("ui_down", 2.0)
	await h.pad_stick(1, Vector2(0.4, 1), 2.0)
	await h.shot("before")
	await restart(h)
	h.check("two local keepers after the restart", h.local_keepers().size() == 2, h.local_keepers().map(func(k): return k.playerId))


# Two devices join in the splitscreen loadout and start a Story Mode run.
static func start_split(h) -> bool:
	GameWorld.figuredOutMovementInLoadout = true
	if not h.check("keyboard joined", await h.join_device(0)):
		return false
	if not h.check("gamepad joined", await h.join_device(1)):
		return false
	await h.wait(1.0)
	Level.stage.gameModeSelected("storymode")
	await h.wait(1.5)
	Level.stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	if not h.check("splitscreen run started", started):
		return false
	h.mute_beats()
	h.disable_waves()
	await h.wait(2.0)
	return h.check("two local keepers", h.local_keepers().size() == 2, h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
