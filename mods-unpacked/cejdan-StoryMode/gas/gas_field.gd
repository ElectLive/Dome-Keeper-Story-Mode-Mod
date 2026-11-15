extends Node2D

# Noxious gas (#198). Lava upside down, and a gas: hidden pockets of gas rock
# sit in plain rock; breaking into one lets the gas out under pressure, and it
# climbs whatever the keeper has dug: up first, then along ceilings, and down
# only when squeezed. An upward dead end holds it for good; a way to the
# surface lets it out of the mine.
#
# One GasField is a child of the run's Map node (added by gas_director.gd),
# beside the lava field. Nothing here edits vanilla state.
#
# Its tuning numbers are starting values, game-design calls for the user, and
# live in data/gas.gd.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const SAVE_KEY := "story.gas"
const LAVA_FIELD := "StoryLavaField"
const TILE := 24.0
const WAKE_EPS := 0.00005
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

const COL_ROCK_SEEP := Color("9be04a")
const COL_ROCK_CORE := Color("e6ff8a")

var map
var mass: Dictionary = {}          # Vector2i -> float, cells holding gas
var rock: Dictionary = {}          # Vector2i -> true, gas rock still solid
var sources: Dictionary = {}       # Vector2i -> float, gas a breached cell still holds
var breaches := 0
var _cracks: Dictionary = {}       # gas rock about to burst -> seconds left
var vented := 0.0                  # gas that left through the surface this run
var faded := 0.0                   # gas that thinned away this run
var vent_marks: Dictionary = {}    # top-row cell -> the time gas last left through it
var revision := 0                  # goes up whenever any cell's gas changes (for the look)
# Dev only: hold the gas still.
var freeze_flow := false
var phys_us := 0
var phys_frames := 0

var _acc := 0.0
var _time := 0.0
var _awake: Dictionary = {}
var _wake_all := true
var _chamber: Rect2i = Rect2i()
var _ocean: Dictionary = {}
var _lava = null


func setup(p_map) -> void:
	map = p_map
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ocean = map.tileData.get_meta("story_ocean", {})
	var ch = map.tileData.get_meta("story_boss_chamber", null)
	_chamber = ch if ch is Rect2i else Rect2i()
	_lava = map.get_node_or_null(LAVA_FIELD)
	if not _restore(str(Data.ofOr(SAVE_KEY, ""))):
		_place_pockets()
	map.tile_destroyed.connect(_on_tile_destroyed)
	add_to_group("saveable")


# --- pockets -------------------------------------------------------------------

# Each plain rock cell decides for itself, from the level seed and its own
# coordinates, whether it seeds a pocket (as magma pockets do), so the same
# seed gives the same pockets however much of the mine has been dug, and
# nothing else the generator placed moves.
func _place_pockets() -> void:
	var td = map.tileData
	var taken := {}
	if _lava != null:
		for c in _lava.magma:
			taken[c] = true
	for pool in td.get_meta("story_pools", []):
		for c in pool:
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					taken[Vector2i(c) + Vector2i(ox, oy)] = true
	var rock_set := {}
	for c in td.get_resource_cells_by_id(Data.TILE_DIRT_START):
		if taken.has(c) or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
			continue
		if td.get_biomev(c) < GasData.POCKET_START_BIOME:
			continue
		if not _ocean.is_empty() and c.y >= int(_ocean["ceiling"]) - 1:
			continue
		rock_set[c] = true
	var rng := RandomNumberGenerator.new()
	for s in rock_set:
		var per: int = int(GasData.pocket_rock_per_pocket(td.get_biomev(s)))
		if hash([Level.levelSeed, "gas", s.x, s.y]) % per != 0:
			continue
		rng.seed = hash([Level.levelSeed, "gaspocket", s.x, s.y])
		var size: int = rng.randi_range(GasData.POCKET_SIZE[0], GasData.POCKET_SIZE[1]) + int(s.y / GasData.POCKET_GROW_ROWS)
		var cells := [s]
		var guard := 0
		while cells.size() < size and guard < 80:
			guard += 1
			var from: Vector2i = cells[rng.randi() % cells.size()]
			var n: Vector2i = from + DIRS[rng.randi() % 4]
			if rock_set.has(n) and not cells.has(n):
				cells.append(n)
		for c in cells:
			rock[c] = true


func add_pocket(cells: Array) -> void:
	for c in cells:
		rock[Vector2i(c)] = true


# Puts gas straight into open cells (playtests, and sealed caverns: #201).
func fill(cells: Array, density: float) -> void:
	for c in cells:
		mass[Vector2i(c)] = density
	wake_all()


func wake_all() -> void:
	_wake_all = true
	revision += 1


func _wake(c: Vector2i) -> void:
	_awake[c] = true
	for d in DIRS:
		_awake[c + d] = true


func _on_tile_destroyed(world_pos: Vector2) -> void:
	var c: Vector2i = map.getTileCoord(world_pos)
	_wake(c)
	revision += 1
	if not rock.has(c):
		return
	rock.erase(c)
	sources[c] = sources.get(c, 0.0) + GasData.VOLUME_PER_ROCK_CELL
	breaches += 1
	_cracks.erase(c)
	InputSystem.shake(4.0, 0.4, 20.0, world_pos)
	# The pocket was under pressure: the rest of it bursts, cell by cell.
	for d in DIRS:
		if rock.has(c + d) and not _cracks.has(c + d):
			_cracks[c + d] = GasData.CRACK_SECONDS


# Open to gas: an empty cell inside the mine, outside the boss chamber, and not
# full of lava.
func _is_open(c: Vector2i) -> bool:
	if c.y < GasData.MIN_Y or not map.is_tile_empty(c) or _chamber.has_point(c):
		return false
	return _lava == null or _lava.mass.get(c, 0.0) < 0.9


# Open sky over the mine's top row: nothing there at all.
func _is_sky(c: Vector2i) -> bool:
	return c.y < GasData.MIN_Y and map.tileData.get_resourcev(c) == -1


# --- simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if map == null or GameWorld.paused:
		return
	var t0 := Time.get_ticks_usec()
	_time += delta
	_acc += delta
	_burst(delta)
	while _acc >= GasData.TICK:
		_acc -= GasData.TICK
		if not freeze_flow:
			_step()
	_update_toxin(delta)
	phys_us += Time.get_ticks_usec() - t0
	phys_frames += 1
	queue_redraw()


func _burst(delta: float) -> void:
	for c in _cracks.keys():
		_cracks[c] -= delta
		if _cracks[c] > 0.0:
			continue
		_cracks.erase(c)
		if not rock.has(c):
			continue
		var tile = map.getTile(Vector2(c))
		if tile != null and is_instance_valid(tile):
			map.destroyTile("team1", "", tile)   # fires tile_destroyed -> breach
		else:
			rock.erase(c)


# How much of `total` the upper of two stacked cells should hold.
func _split(total: float) -> float:
	var k: float = GasData.COMPRESS
	if total <= 1.0:
		return 1.0
	if total < 2.0 + k:
		return (1.0 + total * k) / (1.0 + k)
	return (total + k) / 2.0


func _step() -> void:
	# Breached gas rock lets its gas out under pressure.
	for c in sources.keys():
		var room: float = GasData.SOURCE_PRESSURE - mass.get(c, 0.0)
		var out: float = minf(GasData.SOURCE_RATE, minf(sources[c], room))
		if out > 0.0:
			mass[c] = mass.get(c, 0.0) + out
			sources[c] -= out
			_wake(c)
			revision += 1
		if sources[c] <= 0.001:
			sources.erase(c)

	var all_awake: bool = _wake_all
	_wake_all = false
	if not all_awake and _awake.is_empty():
		return
	var work: Array = mass.keys() if all_awake else _awake.keys().filter(func(c): return mass.has(c))
	var max_flow: float = GasData.MAX_FLOW
	var dm: Dictionary = {}
	for c in work:
		var m: float = mass[c]
		if m <= 0.0:
			continue
		var rem := m
		var up: Vector2i = c + Vector2i.UP
		# The surface: gas in the mine's top row with sky above it is gone.
		if _is_sky(up):
			var out: float = minf(rem, GasData.VENT_PER_STEP)
			dm[c] = dm.get(c, 0.0) - out
			vented += out
			vent_marks[c] = _time
			rem -= out
			if rem <= 0.0:
				continue
		var up_open := _is_open(up)
		var mu: float = mass.get(up, 0.0)
		if up_open:
			var flow: float = clampf((_split(rem + mu) - mu) * GasData.RISE_SHARE, 0.0, minf(max_flow, rem))
			if flow > 0.0:
				dm[c] = dm.get(c, 0.0) - flow
				dm[up] = dm.get(up, 0.0) + flow
				rem -= flow
		if rem <= 0.0:
			continue
		# Sideways: freely once the gas rests against a ceiling or full gas, a
		# slow drift while it is still rising.
		var resting: bool = not up_open or mu >= 0.9
		var div: float = GasData.SIDE_DIVISOR if resting else GasData.DRIFT_DIVISOR
		for side in [Vector2i.LEFT, Vector2i.RIGHT]:
			var sc: Vector2i = c + side
			if not _is_open(sc):
				continue
			var flow: float = clampf((m - mass.get(sc, 0.0)) / div, 0.0, minf(max_flow, rem))
			if flow > GasData.MIN_FLOW:
				dm[c] = dm.get(c, 0.0) - flow
				dm[sc] = dm.get(sc, 0.0) + flow
				rem -= flow
		# Down: only gas squeezed past a full cell.
		if rem > 1.0:
			var down: Vector2i = c + Vector2i.DOWN
			if _is_open(down):
				var flow: float = clampf((rem - _split(rem + mass.get(down, 0.0))) * GasData.RISE_SHARE, 0.0, minf(max_flow, rem))
				if flow > GasData.MIN_FLOW:
					dm[c] = dm.get(c, 0.0) - flow
					dm[down] = dm.get(down, 0.0) + flow

	var woke: Dictionary = {}
	for c in dm:
		var o: float = mass.get(c, 0.0)
		var m: float = o + dm[c]
		_set_mass(c, o, m, woke)
	# Thin gas that has stopped moving fades (only awake cells are looked at;
	# fading keeps a cell awake). Thin gas on its way somewhere is left alone.
	for c in work:
		if not mass.has(c) or dm.has(c):
			continue
		var o: float = mass[c]
		if o < GasData.THIN_MASS:
			var lost: float = minf(o, GasData.DECAY_PER_SECOND * GasData.TICK)
			faded += lost
			_set_mass(c, o, o - lost, woke)
	if not woke.is_empty():
		revision += 1
	_awake = {}
	for c in woke:
		_wake(c)


func _set_mass(c: Vector2i, o: float, m: float, woke: Dictionary) -> void:
	if m > GasData.MIN_MASS:
		mass[c] = m
	else:
		if m > 0.0:
			faded += m
		mass.erase(c)
	if absf(m - o) > WAKE_EPS or (m <= GasData.MIN_MASS and o > 0.0):
		woke[c] = true


# --- toxin (#202) ----------------------------------------------------------------

func _update_toxin(_delta: float) -> void:
	pass


# The densest gas in the cells a rect (world space) touches.
func gas_in(world_rect: Rect2) -> float:
	var a: Vector2i = map.getTileCoord(world_rect.position)
	var b: Vector2i = map.getTileCoord(world_rect.end)
	var best := 0.0
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			best = maxf(best, mass.get(Vector2i(x, y), 0.0))
	return best


func gas_at(world_pos: Vector2) -> float:
	return mass.get(map.getTileCoord(world_pos), 0.0)


# --- save and load ---------------------------------------------------------------
# As the lava field does: serialize() puts the gas into Data (SAVE_KEY), which
# vanilla writes into the save; vanilla's loader skips this node's own entry.

func serialize() -> Dictionary:
	var cells: Array = []
	for c in mass:
		cells.append([c.x, c.y, snappedf(mass[c], 0.0001)])
	var src: Array = []
	for c in sources:
		src.append([c.x, c.y, snappedf(sources[c], 0.0001)])
	var rocks: Array = []
	for c in rock:
		rocks.append([c.x, c.y])
	Data.apply(SAVE_KEY, JSON.stringify(_save_extra({"seed": Level.levelSeed, "mass": cells, "sources": src, "rock": rocks,
		"breaches": breaches, "vented": vented, "faded": faded})))
	return {"meta.priority": 9001, "meta.kind": "storygas"}


func _save_extra(d: Dictionary) -> Dictionary:
	return d


func _restore(blob: String) -> bool:
	if blob == "":
		return false
	var d = JSON.parse_string(blob)
	if not d is Dictionary or int(d.get("seed", -1)) != Level.levelSeed:
		return false
	mass.clear()
	sources.clear()
	rock.clear()
	for e in d.get("mass", []):
		mass[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("sources", []):
		sources[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("rock", []):
		rock[Vector2i(int(e[0]), int(e[1]))] = true
	breaches = int(d.get("breaches", 0))
	vented = float(d.get("vented", 0.0))
	faded = float(d.get("faded", 0.0))
	_restore_extra(d)
	wake_all()
	ModLoaderLog.info("Gas restored from save: %d cells, %d gas rock" % [mass.size(), rock.size()], "cejdan-StoryMode")
	return true


func _restore_extra(_d: Dictionary) -> void:
	pass


# --- drawing -------------------------------------------------------------------

func _cell_origin(c: Vector2i) -> Vector2:
	return to_local(map.getTilePos(Vector2(c))) - Vector2(TILE, TILE) * 0.5


func _noise(c: Vector2i, i: int) -> float:
	return fposmod(sin(float(c.x * 157 + c.y * 271 + i * 61)) * 43758.5453, 1.0)


func _seen(c: Vector2i) -> bool:
	return map.visibleTileCoords.has(Vector2(c)) or map.visibleTileCoords.has(c)


func _draw() -> void:
	# Gas rock the player can see: green seeping cracks that breathe.
	for c in rock:
		if not map.tiles.has(Vector2(c)):
			continue
		var o := _cell_origin(c)
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2 + c.x * 1.3 + c.y * 0.7)
		for i in 5:
			var p := Vector2(3 + floor(_noise(c, i) * 17.0), 3 + floor(_noise(c, i + 9) * 17.0))
			var horizontal := _noise(c, i + 20) > 0.5
			var length: float = 3.0 + floor(_noise(c, i + 30) * 5.0)
			var size := Vector2(length, 1) if horizontal else Vector2(1, length)
			draw_rect(Rect2(o + p, size), Color(COL_ROCK_SEEP, 0.3 + 0.6 * pulse))
			draw_rect(Rect2(o + p, Vector2(1, 1)), Color(COL_ROCK_CORE, pulse))
	_draw_gas()


# Placeholder look (#200): a flat tint by density. The real look is #203.
func _draw_gas() -> void:
	for c in mass:
		if not _seen(c):
			continue
		var a: float = clampf(mass[c], 0.0, 1.5) / 1.5
		draw_rect(Rect2(_cell_origin(c), Vector2(TILE, TILE)), Color(0.45, 0.8, 0.2, 0.15 + 0.6 * a))


func total() -> float:
	var t := 0.0
	for c in mass:
		t += mass[c]
	for c in sources:
		t += sources[c]
	return t


func stats() -> Dictionary:
	return {"cells": mass.size(), "total": total(), "rock": rock.size(), "sources": sources.size(), "breaches": breaches,
		"vented": vented, "faded": faded, "awake": _awake.size()}
