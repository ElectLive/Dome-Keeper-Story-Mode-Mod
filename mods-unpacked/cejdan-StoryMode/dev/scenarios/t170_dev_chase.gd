extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 170: the `--boss` dev commands. Runs `--boss=chase` the way the
# command line does and checks what the 2026-11-14 playtest found missing: the
# chase really starts (it used to jump straight to the finale), the keeper has
# the gear of a keeper who reached the boss, and a winding shaft is open from
# the chamber to the dome. Then flies that shaft home with real input, chased.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Dev = preload("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd")
const TIMEOUT := 420

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"seed": 12345}


func _steer(h, dir: Vector2) -> void:
	var want: Dictionary = {"ui_left": dir.x < -0.35, "ui_right": dir.x > 0.35, "ui_up": dir.y < -0.35, "ui_down": dir.y > 0.35}
	for a: String in want:
		if want[a] and not _held.get(a, false):
			h.down(a)
		elif not want[a] and _held.get(a, false):
			h.up(a)
		_held[a] = want[a]


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = Director.instance()
	var k = h.keeper()
	h.check("the keeper starts in the dome", k.isInsideDome)
	boss._dev_boss("chase")
	await h.wait(1.5)
	h.snap_camera()
	h.check("`--boss=chase` starts the chase and stays in it", Director.current() == "chase", Director.current())
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	h.check("the keeper is in Velle's chamber", ch.has_point(h.keeper_tile()), h.keeper_tile())
	await h.shot("chase_start")

	# ---- gear
	var gear: Dictionary = {"drill": Data.of(k.playerId + ".keeper1.drillStrength"), "speed": Data.of(k.playerId + ".keeper1.maxSpeed"),
		"laser dps": Data.of("team1.laser.dps"), "dome health": Data.of("team1.dome.maxhealth"), "heat shield": Data.ofOr(k.playerId + ".suit.heatshield", 0),
		"suit blaster": GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster")}
	h.note("gear", gear)
	h.check("max drill (102) and max speed (140)", int(gear["drill"]) == 102 and int(gear["speed"]) == 140, gear)
	h.check("Laser III (110 dps) and a stronger dome", int(gear["laser dps"]) == 110 and int(gear["dome health"]) >= 1400, gear)
	h.check("Heat Shielding IV and the Suit Blaster", int(gear["heat shield"]) == 4 and gear["suit blaster"], gear)

	# ---- the drilled way home
	var path: Array = boss.dev_path
	await h.until(func(): return Dev.blocked(path).is_empty(), 10.0)
	var blocked: Array = Dev.blocked(path)
	h.note("blocked cells", blocked.map(func(c): return [c, Level.map.tileData.get_resourcev(c), Level.map.tileData.get_hardnessv(c), Level.map.getTile(Vector2(c)) != null]))
	h.check("a shaft is open from the chamber to the dome (%d cells)" % path.size(), not path.is_empty() and blocked.is_empty(), blocked.slice(0, 8))
	var xs: Dictionary = {}
	var overlay: Dictionary = {}
	for c: Vector2i in path:
		xs[c.x] = true
		overlay[c] = Color(1, 0.2, 0.9)
	h.check("the shaft winds: it is not one straight line", xs.size() >= 8, xs.keys())
	h.map_png("path", {}, 4, null, overlay)
	var pools: Dictionary = Dev.pool_cells()
	h.check("it keeps clear of the lava pools (%d pool cells)" % pools.size(), not pools.is_empty() and path.all(func(c): return not pools.has(c)))

	# ---- the tentacles come
	var chase = boss.chase
	var moving: bool = await h.until(func(): return float(chase.heads[0]) > 30.0, 8.0)
	h.check("the tentacles set off after the keeper", moving, [chase.heads, chase.wait])
	await h.shot("tentacles_coming")

	# ---- fly the shaft home, chased
	boss.health.invulnerable = 0.0
	var centre: Array = []
	var seen: Dictionary = {}
	for c: Vector2i in path:
		# One waypoint per row or sideways step: the middle of the two-wide shaft.
		if seen.has(Vector2i(c.x - 1, c.y)):
			continue
		seen[c] = true
		centre.append(Level.map.getTilePos(Vector2(c)) + Vector2(12, 0))
	# Then straight up the dome's own shaft and in.
	centre.append(Level.map.getTilePos(Vector2(0, 1)))
	centre.append(Level.map.getTilePos(Vector2(0, -3)))
	var hit_at: Array = []
	boss.health.hurt_taken.connect(func(_left, _cause): hit_at.append([snappedf(h.now(), 0.1), h.keeper_tile()]))
	var stuck_t: float = h.now()
	var stuck_wp: int = -1
	var stuck_shots: int = 0
	var wp: int = 0
	var t0: float = h.now()
	var next_shot: float = 8.0
	var min_gap: float = 1e9
	while not k.isInsideDome and Director.current() == "chase" and h.now() - t0 < 240.0:
		await h.frames(1)
		while wp < centre.size() - 1 and k.global_position.distance_to(centre[wp]) < 14.0:
			wp += 1
		_steer(h, centre[wp] - k.global_position)
		if wp != stuck_wp:
			stuck_wp = wp
			stuck_t = h.now()
		elif h.now() - stuck_t > 1.5 and stuck_shots < 2:
			stuck_shots += 1
			stuck_t = h.now()
			var around: Array = []
			var kt: Vector2i = h.keeper_tile()
			for dy in range(-2, 2):
				var row: String = ""
				for dx in range(-3, 4):
					row += "." if Level.map.is_tile_empty(kt + Vector2i(dx, dy)) else "#"
				around.append(row)
			h.note("stuck", {"tile": kt, "wp": wp, "wp_tile": Level.map.getTileCoord(centre[wp]), "pos": k.global_position, "wp_pos": centre[wp], "around": around, "carrying": k.carriedCarryables.size(),
				"blocked": Dev.blocked(path).map(func(c): var t = Level.map.getTile(Vector2(c)); return [c, Level.map.tileData.get_resourcev(c), Level.map.tileData.get_hardnessv(c), t.type if t != null else "no tile", t.health if t != null else -1])})
			await h.shot("stuck")
		if chase.wait <= 0.0:
			min_gap = minf(min_gap, chase.gap)
		if h.now() - t0 > next_shot:
			next_shot += 20.0
			var wc: Vector2i = Level.map.getTileCoord(centre[wp])
			h.note("flying", {"t": snappedf(h.now() - t0, 0.1), "tile": h.keeper_tile(), "wp": wp, "wp_tile": wc, "wp_open": Level.map.is_tile_empty(wc),
				"hearts": boss.health.hearts(), "gap": snappedf(chase.gap, 1.0), "blocked": Dev.blocked(path).slice(0, 6), "vel": k.move if "move" in k else null})
			await h.shot("flying_%03ds" % int(h.now() - t0))
	if not k.isInsideDome:
		_steer(h, Vector2.UP)
		await h.until(func(): return k.isInsideDome, 20.0)
	_steer(h, Vector2.ZERO)
	var took: float = snappedf(h.now() - t0, 0.1)
	h.note("flight home", {"seconds": took, "closest the tips got (px)": snappedf(min_gap, 1.0), "hits": chase.hits, "hearts": boss.health.hearts(), "waypoint": [wp, centre.size()], "hit at": hit_at})
	h.check("the keeper can fly the shaft all the way home", k.isInsideDome, [h.keeper_tile(), wp, centre.size()])
	await h.wait(0.5)
	h.check("reaching the dome starts the finale", Director.current() == "finale", Director.current())
	await h.shot("home")
