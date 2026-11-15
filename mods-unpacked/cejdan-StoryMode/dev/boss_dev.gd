extends RefCounted

# Dev-only helpers for the `--boss` commands (#170): the gear a keeper really
# has by the time the boss is reached, and a drilled way home for the chase.

# Every upgrade a keeper at the boss has bought: all of the drill and the
# jetpack, and a dome that can fight (Laser III, faster aim, more health).
const GEAR: Array = [
	"drill1", "drill2", "drill3", "drill4",
	"jetpackspeed1", "jetpackspeed2", "jetpackspeed3", "jetpackspeed4",
	"jetpackstrength1", "jetpackstrength2", "jetpackstrength3", "jetpackstrength4",
	"laserstrength1", "laserstrength2", "laserstrength3",
	"lasermove1", "lasermove2", "laseraimline",
	"domehealthmeter", "dome1health1", "dome1health2",
]


# Gives the keeper GEAR for free. Returns the ids that were added.
# `laser_level` 0..3 stops the laser's strength there (playtests of weaker domes).
static func give_gear(extra: Array = [], laser_level: int = 3) -> Array:
	var keeper = Keepers.first()
	var given: Array = []
	for raw: String in GEAR + extra:
		if raw.begins_with("laserstrength") and int(raw.substr(13)) > laser_level:
			continue
		var id: String = raw
		if not GameWorld.upgrades.has(id):
			for prefix: String in [keeper.teamId + ".", keeper.playerId + "."]:
				if GameWorld.upgrades.has(prefix + raw):
					id = prefix + raw
					break
		if not GameWorld.upgrades.has(id) or GameWorld.boughtUpgrades.has(id):
			continue
		GameWorld.serverAddUpgrade(id, keeper.teamId)
		given.append(raw)
	# The Suit Blaster is a keeper gadget, kept under the player's own id.
	var blaster: String = keeper.playerId + ".suitblaster"
	if not GameWorld.boughtUpgrades.has(blaster):
		GameWorld.serverAddUpgrade(blaster, keeper.teamId)
		given.append("suitblaster")
	return given


# The cells of a winding shaft, two tiles wide, from the top of the boss
# chamber `ch` up to the dome's own shaft: the way a player would have drilled
# down. Bottom to top. The same seed gives the same path. It keeps clear of
# the cells in `avoid` (the enclosed lava pools, which would flood it).
static func path_cells(ch: Rect2i, path_seed: int, avoid: Dictionary = {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = path_seed
	var cells: Array = []
	var x: int = ch.position.x + ch.size.x / 2 - 4
	var y: int = ch.position.y - 1
	var reach: int = maxi(3, ch.size.x / 2 - 2)
	var run: int = rng.randi_range(5, 10)
	while y >= 1:
		cells.append(Vector2i(x, y))
		cells.append(Vector2i(x + 1, y))
		run -= 1
		var to: int = x
		if y <= 12:
			# The last stretch comes in under the dome.
			if run <= 0:
				to = 0
		elif not _clear(x, y - 1, avoid):
			# A pool ahead: step aside to the nearest clear column.
			for d in range(1, reach * 2):
				var found: bool = false
				for side: int in [1, -1]:
					var nx: int = x + d * side
					if nx >= -reach and nx < reach and _clear(nx, y - 1, avoid) and _row_clear(x, nx, y, avoid):
						to = nx
						found = true
						break
				if found:
					break
			run = rng.randi_range(5, 12)
		elif run <= 0:
			run = rng.randi_range(5, 12)
			var want: int = clampi(x + rng.randi_range(2, 6) * (1 if rng.randf() < 0.5 else -1), -reach, reach - 1)
			if _clear(want, y - 1, avoid) and _row_clear(x, want, y, avoid):
				to = want
		var step: int = signi(to - x)
		while x != to:
			x += step
			cells.append(Vector2i(x, y))
			cells.append(Vector2i(x + 1, y))
		y -= 1
	return cells


# Is the two-wide column at x free of `avoid` for the next rows up from y?
static func _clear(x: int, y: int, avoid: Dictionary) -> bool:
	for dy in 5:
		for dx in range(-1, 3):
			if avoid.has(Vector2i(x + dx, y - dy)):
				return false
	return true


static func _row_clear(x0: int, x1: int, y: int, avoid: Dictionary) -> bool:
	for x in range(mini(x0, x1) - 1, maxi(x0, x1) + 3):
		for dy in range(-1, 2):
			if avoid.has(Vector2i(x, y + dy)):
				return false
	return true


# Every cell of the map's enclosed lava pools, as a set.
static func pool_cells() -> Dictionary:
	var out: Dictionary = {}
	for pool in Level.map.tileData.get_meta("story_pools", []):
		for c in pool:
			out[Vector2i(c)] = true
	return out


# Opens `cells` in the live map.
static func carve(cells: Array) -> void:
	var map = Level.map
	map.tileCoordsToReveal.append_array(cells)
	map.floodRevealTiles()
	if map.has_method("finish_flood"):
		map.finish_flood()
	var v: Array = []
	for c: Vector2i in cells:
		v.append(Vector2(c))
	map.freeTiles(v)


# Anything freeTiles would not take: metal and the gate (broken the way a
# Suit Blaster blast breaks them) and special tiles (destroyed outright).
# Call a few frames after carve().
static func carve_leftovers(cells: Array) -> int:
	var metal = load("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
	var n: int = 0
	for c: Vector2i in cells:
		var t = Level.map.getTile(Vector2(c))
		if t == null or not is_instance_valid(t) or Level.map.is_tile_empty(c):
			continue
		n += 1
		if metal.is_metal(t.type):
			metal.record_circle(Vector2(c), 0.5)
			t.exploded = true
			t.hit(Vector2.UP, t.health + 1.0, "team1")
		else:
			Level.map.destroyTile("team1", "", t)
	return n


# The path's cells that are still rock.
static func blocked(cells: Array) -> Array:
	return cells.filter(func(c): return not Level.map.is_tile_empty(c))
