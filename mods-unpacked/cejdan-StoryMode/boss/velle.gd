extends Node2D

# Velle in the boss chamber (#160): a mound of flesh rooted in the chamber
# floor, covered in eyes (the game's teleport-cave eye art), with one great
# lidded eye, eye stalks and tentacles. Everything is drawn in code and tested
# against the keeper's position; nothing here is a physics body.
#
# The loop: pop every eye stalk (bombs, mines or the Suit Blaster) and the
# great eye opens. It stays open until it has been hurt enough to end the
# phase (#169: no timer), but an open eye fights back with its gaze, faster
# the longer it is left open, so nothing is gained by waiting. Velle's health
# sets the phase (data/boss.gd); each phase adds stalks, attacks and lasers:
#
#   phase 1  stalks spit orbs; tentacle sweeps and lunges. Open: one gaze beam.
#   phase 2  half the stalks' shots are thin lasers; eyes open in the walls and
#            fire a cross through the keeper. Open: twin beams, then a wall of
#            light that sweeps one half of the chamber.
#   phase 3  mostly lasers; the walls fire a grid. Open: triple beams, then
#            two walls of light that close on the space above the eye.
#
# The fight is the brutal one as listed; other difficulties change the numbers
# (data/boss.gd, "difficulty"): normal and easy fire fewer lasers at once in
# phase 3, You Asked For It hardens phases 1 and 2.
#
# Old mining charges fall from the roof all through the fight: on a timer,
# whenever a stalk pops, and a couple at once when the eye opens. A charge
# that falls out through a hole in the floor comes straight back down from
# the roof. Each new phase also shakes a heart loose.
#
# The boss director owns this node, feeds it explosions (`explosion()`), and
# listens for `defeated`.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")

signal defeated
signal phase_changed(phase: int)
signal eye_opened

const STALK_HOMES := {
	2: [Vector2(0.2, 0.36), Vector2(0.8, 0.36)],
	3: [Vector2(0.18, 0.42), Vector2(0.5, 0.2), Vector2(0.82, 0.42)],
	4: [Vector2(0.14, 0.55), Vector2(0.34, 0.2), Vector2(0.66, 0.2), Vector2(0.86, 0.55)],
	5: [Vector2(0.12, 0.6), Vector2(0.28, 0.25), Vector2(0.5, 0.16), Vector2(0.72, 0.25), Vector2(0.88, 0.6)],
}
const BODY_EYES: Array = [Vector2(-40, -12), Vector2(-27, -34), Vector2(-52, -2), Vector2(27, -36), Vector2(42, -14),
	Vector2(54, -3), Vector2(-14, -52), Vector2(15, -53), Vector2(-24, -8), Vector2(25, -9)]

var arena: Rect2
var base: Vector2            # the mound's foot: centre of the chamber floor
var health: Node = null      # boss/keeper_health.gd

var hp: float = Boss.CORE_HP
var phase: int = 0           # 0..2
var state: String = "rise"   # rise, fight, open, roar, dying, dead
var state_t: float = 0.0
var lid: float = 0.0         # the great eye: 0 shut .. 1 open
var rise: float = 0.0
var time: float = 0.0

var stalks: Array = []
var orbs: Array = []
var attacks: Array = []
var fx: Array = []
var bombs: Array = []
var pickups: Array = []      # hearts shaken loose at a phase change
var chamber: Rect2i = Rect2i()
var _atk_t: float = 3.0
var _bomb_t: float = 2.0
var _open_t: float = 0.0     # seconds the eye has been open
var _open_atk_t: float = 0.0
var _volley: int = 0
var _white: float = 0.0
var _wall_open: float = 0.0
var _hit_flash: float = 0.0
var _clang: float = 0.0
var _ring_t: float = -1.0
var _shock: float = -1.0
var _last_attack: String = ""
var _rng := RandomNumberGenerator.new()

# Counters for playtests.
var stats: Dictionary = {"stalks_popped": 0, "core_hits": 0, "orbs": 0, "attacks": {}, "bombs_spawned": 0, "opens": 0, "blocked": 0,
	"rays": 0, "sweeps": 0, "bombs_returned": 0, "hearts_dropped": 0, "hearts_taken": 0, "open_seconds": 0.0}
# Playtests can stop the bombs or the attacks to look at one thing.
var spawn_bombs: bool = true
var attack_enabled: bool = true


func setup(p_arena: Rect2, p_health: Node, p_chamber: Rect2i = Rect2i()) -> void:
	arena = p_arena
	health = p_health
	chamber = p_chamber
	base = Vector2(arena.get_center().x, arena.end.y)
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()


func eye_pos() -> Vector2:
	return base + Vector2(0, -36.0 * rise)


func is_open() -> bool:
	return state == "open" and lid > 0.5


func alive_stalks() -> int:
	var n: int = 0
	for s: Dictionary in stalks:
		if s["alive"]:
			n += 1
	return n


func _kp() -> Vector2:
	var k = Keepers.first()
	if k == null or not is_instance_valid(k):
		return arena.get_center()
	return to_local(k.global_position)


# ---------------------------------------------------------------- update

func _physics_process(delta: float) -> void:
	if GameWorld.paused:
		return
	time += delta
	state_t += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	_clang = maxf(0.0, _clang - delta)
	_white = maxf(0.0, _white - delta * 1.6)
	if state in ["fight", "open", "roar"]:
		_wall_open = minf(1.0, _wall_open + delta * 0.8)
	var kp: Vector2 = _kp()
	match state:
		"rise":
			rise = minf(1.0, state_t / 2.4)
			if fposmod(time, 0.12) < delta:
				InputSystem.shake(4.0, 0.15, 30.0)
				_burst(base + Vector2(_rng.randf_range(-50, 50), -4), 3, Pix.FLESH_LIGHT, 40.0)
			if state_t >= 2.6:
				_grow_stalks()
				_set_state("fight")
		"fight":
			lid = move_toward(lid, 0.0, delta * 3.0)
			_update_stalks(delta, kp)
			_schedule_attacks(delta, kp)
			if not stalks.is_empty() and alive_stalks() == 0 and _all_stalks_gone():
				_open_eye()
		"open":
			# Open until hurt enough to end the phase (_damage_core).
			lid = move_toward(lid, 1.0, delta * 2.5)
			_open_t += delta
			stats["open_seconds"] += delta
			_update_stalks(delta, kp)
			if _ring_t >= 0.0:
				_ring_t -= delta
				if _ring_t < 0.0:
					_ring_burst()
			_open_atk_t -= delta
			if _open_atk_t <= 0.0 and attack_enabled:
				var busy: float = _open_volley(kp)
				var rage: float = maxf(0.0, 1.0 - Boss.OPEN_RAGE_PER_S * _open_t)
				_open_atk_t = busy + maxf(Boss.OPEN_BEAM_FASTEST, float(Boss.OPEN_BEAM_EVERY[phase]) * rage)
		"roar":
			lid = move_toward(lid, 0.0, delta * 6.0)
			if _shock >= 0.0:
				_shock += delta
			if state_t < 0.7 and kp.distance_to(base) < 150.0:
				_shove_keeper((kp - eye_pos()).normalized() * 70.0 * delta)
			if state_t >= 1.6:
				_shock = -1.0
				_grow_stalks()
				_set_state("fight")
				_atk_t = 1.2
		"dying":
			lid = move_toward(lid, 1.0, delta * 2.0)
			if fposmod(time, 0.16) < delta:
				var p: Vector2 = base + Vector2(_rng.randf_range(-48, 48), _rng.randf_range(-60, -6))
				_burst(p, 8, [Pix.IRIS, Pix.SUCKER, Pix.VIOLET_LIGHT][_rng.randi() % 3], 80.0)
				InputSystem.shake(10.0, 0.2, 26.0)
				if fposmod(time, 0.48) < 0.16:
					Sfx.play("pop", -6.0, _rng.randf_range(0.7, 1.1))
			if state_t >= 3.8:
				_set_state("dead")
				rise = 0.45
				_burst(eye_pos(), 40, Pix.IRIS, 140.0)
				InputSystem.shake(30.0, 0.8, 18.0)
				Sfx.play("boom", -2.0, 0.7)
				defeated.emit()
		"dead":
			pass
	_update_orbs(delta, kp)
	_update_attacks(delta, kp)
	_update_fx(delta)
	_update_pickups(delta, kp)
	if state in ["fight", "open", "roar"]:
		_update_bombs(delta)
		# The body itself hurts.
		var d: Vector2 = kp - (base + Vector2(0, -22))
		if (d.x / 56.0) * (d.x / 56.0) + (d.y / 40.0) * (d.y / 40.0) < 1.0:
			_hurt(base + Vector2(0, -10), "body")
	queue_redraw()


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0


func _hurt(from: Vector2, cause: String) -> void:
	if health != null and state != "dying" and state != "dead":
		health.hurt(from, cause)


func _shove_keeper(step: Vector2) -> void:
	var k = Keepers.first()
	if k != null and is_instance_valid(k) and k.has_method("move_and_collide") and not k.disabled:
		k.move_and_collide(step)


# ---------------------------------------------------------------- stalks

func _grow_stalks() -> void:
	stalks.clear()
	var n: int = Boss.stalks(phase)
	var homes: Array = STALK_HOMES[n]
	for i in n:
		var h: Vector2 = arena.position + Vector2(homes[i].x * arena.size.x, homes[i].y * arena.size.y)
		var anchor: Vector2
		if homes[i].y < 0.35:
			anchor = Vector2(h.x + (20.0 if i % 2 == 0 else -20.0), arena.position.y)
		else:
			anchor = Vector2(arena.position.x if homes[i].x < 0.5 else arena.end.x, h.y + 26.0)
		stalks.append({"anchor": anchor, "home": h, "pos": anchor, "hp": Boss.STALK_HP, "alive": true, "grow": 0.0,
			"fire_t": 1.6 + i * 0.7 + _rng.randf() * 0.8, "charge": -1.0, "seed": _rng.randf() * TAU, "flash": 0.0, "gone": 0.0})
	Sfx.play("grow", -8.0, 0.8)


func _all_stalks_gone() -> bool:
	for s: Dictionary in stalks:
		if s["gone"] < 0.5:
			return false
	return true


func _update_stalks(delta: float, kp: Vector2) -> void:
	for s: Dictionary in stalks:
		s["flash"] = maxf(0.0, s["flash"] - delta)
		if not s["alive"]:
			s["gone"] = minf(1.0, s["gone"] + delta * 1.6)
			continue
		s["grow"] = minf(1.0, s["grow"] + delta * 1.4)
		var sway: Vector2 = Vector2(sin(time * 0.9 + s["seed"]) * 14.0, cos(time * 1.3 + s["seed"]) * 9.0)
		var lean: Vector2 = (kp - s["home"]).limit_length(8.0 + 10.0 * phase)
		var goal: Vector2 = s["home"] + sway + lean
		s["pos"] = s["anchor"].lerp(goal, ease(s["grow"], 0.4))
		if s["grow"] < 1.0:
			continue
		if kp.distance_to(s["pos"]) < 13.0:
			_hurt(s["pos"], "stalk")
		if state != "fight" or not attack_enabled:
			continue
		if s["charge"] >= 0.0:
			s["charge"] -= delta
			if s["charge"] < 0.0:
				_spit(s["pos"], kp)
		else:
			s["fire_t"] -= delta
			if s["fire_t"] <= 0.0 and _rng.randf() < Boss.stalk_laser_share(phase):
				# A thin laser instead of an orb.
				attacks.append(_ray(s["pos"], kp, 0.8, 0.25, 0.35, 3.0, "stalk", s))
				s["fire_t"] = Boss.stalk_fire_every(phase) * _rng.randf_range(0.85, 1.25)
			elif s["fire_t"] <= 0.0:
				s["charge"] = 0.7
				s["fire_t"] = Boss.stalk_fire_every(phase) * _rng.randf_range(0.85, 1.25)


func _spit(from: Vector2, kp: Vector2) -> void:
	var dir: Vector2 = (kp - from).normalized()
	orbs.append({"p": from + dir * 10.0, "v": dir * Boss.ORB_SPEED[phase], "life": 7.0, "r": 4.0})
	stats["orbs"] += 1
	Sfx.play("spit", -12.0, _rng.randf_range(0.9, 1.2))


func _pop_stalk(s: Dictionary) -> void:
	s["alive"] = false
	s["charge"] = -1.0
	stats["stalks_popped"] += 1
	_burst(s["pos"], 18, Pix.IRIS, 110.0)
	_burst(s["pos"], 10, Pix.SUCKER, 70.0)
	InputSystem.shake(12.0, 0.25, 24.0)
	Sfx.play("pop", -4.0, _rng.randf_range(0.85, 1.15))
	# Its thrashing shakes a charge loose.
	if state == "fight" and spawn_bombs and multiplayer.is_server():
		spawn_bomb(Vector2(_bomb_x(), arena.position.y + 16.0))


func _open_eye() -> void:
	_set_state("open")
	_open_t = 0.0
	_open_atk_t = 2.2
	_volley = 0
	_ring_t = 1.6 if phase == 1 else -1.0   # phase 3 keeps the space above the eye clear for the jaws
	attacks.clear()
	stats["opens"] += 1
	_white = 0.5
	InputSystem.shake(18.0, 0.6, 20.0)
	Sfx.play("open", -4.0, 0.9)
	Sfx.play("roar", -8.0, 1.3)
	# The whole chamber shudders: charges fall either side of the eye.
	if spawn_bombs and multiplayer.is_server():
		for i in Boss.BOMBS_ON_OPEN:
			var side: float = -1.0 if i % 2 == 0 else 1.0
			spawn_bomb(Vector2(base.x + side * _rng.randf_range(96.0, 150.0), arena.position.y + 16.0))
	_bomb_t = Boss.BOMB_EVERY_OPEN
	eye_opened.emit()


# What the open eye does next. Returns how long it is busy with it.
func _open_volley(kp: Vector2) -> float:
	_volley += 1
	var odd: bool = _volley % 2 == 1
	if odd or phase == 0:
		var n: int = Boss.open_beams(phase)
		start_attack(["beam1", "beam2", "beam"][clampi(n, 1, 3) - 1], kp)
		return [0.6, 1.4, 2.0][clampi(n, 1, 3) - 1]
	if phase == 1 or not Boss.T_JAWS[Boss.tier()]:
		start_attack("wall", kp)
	else:
		start_attack("jaws", kp)
	return 3.6


func _ring_burst() -> void:
	var n: int = 10 if phase == 1 else 14
	var off: float = _rng.randf() * TAU
	for i in n:
		var dir: Vector2 = Vector2.RIGHT.rotated(off + TAU * i / n)
		if dir.y > 0.35:
			continue
		orbs.append({"p": eye_pos() + dir * 18.0, "v": dir * Boss.ORB_SPEED[phase] * 0.8, "life": 7.0, "r": 4.0})
	stats["orbs"] += n
	Sfx.play("spit", -8.0, 0.7)


# ---------------------------------------------------------------- orbs

func _update_orbs(delta: float, kp: Vector2) -> void:
	for i in range(orbs.size() - 1, -1, -1):
		var o: Dictionary = orbs[i]
		o["p"] += o["v"] * delta
		o["life"] -= delta
		var out: bool = not arena.grow(-3.0).has_point(o["p"])
		if out or o["life"] <= 0.0:
			_burst(o["p"], 4, Pix.VIOLET_LIGHT, 40.0)
			orbs.remove_at(i)
			continue
		if kp.distance_to(o["p"]) < o["r"] + 5.0:
			_hurt(o["p"] - o["v"].normalized() * 6.0, "orb")
			_burst(o["p"], 6, Pix.VIOLET_LIGHT, 60.0)
			orbs.remove_at(i)


# ---------------------------------------------------------------- attacks

const POOLS: Array = [
	["sweep", "lunge"],
	["sweep", "lunge", "cross", "pull", "cross"],
	["lunge", "erupt", "grid", "sweep", "grid"],
]


func _schedule_attacks(delta: float, kp: Vector2) -> void:
	if not attack_enabled:
		return
	_atk_t -= delta
	if _atk_t > 0.0:
		return
	_atk_t = Boss.attack_every(phase) * _rng.randf_range(0.85, 1.2)
	var pool: Array = POOLS[mini(POOLS.size() - 1, phase + int(Boss.T_POOL_SHIFT[Boss.tier()]))]
	var kind: String = pool[_rng.randi() % pool.size()]
	if kind == _last_attack and pool.size() > 1:
		kind = pool[(pool.find(kind) + 1) % pool.size()]
	start_attack(kind, kp)


# Starts one attack by name (also called by playtests).
func start_attack(kind: String, kp: Vector2) -> void:
	_last_attack = kind
	stats["attacks"][kind] = int(stats["attacks"].get(kind, 0)) + 1
	match kind:
		"sweep":
			var a: Vector2 = eye_pos() + Vector2(0, 6)
			var dir: Vector2 = (kp - a).normalized()
			if dir.y > 0.2:
				dir = Vector2(signf(dir.x) if dir.x != 0.0 else 1.0, 0.2).normalized()
			attacks.append(_strike(a, _to_wall(a, dir), 0.9, 0.2, 0.4, 0.5, 7.0, 0.0))
		"lunge":
			var horizontal: bool = _rng.randf() < 0.5
			attacks.append(_lunge(kp, horizontal, 0.0))
			if phase >= 2 and Boss.T_DOUBLE_LUNGE[Boss.tier()]:
				attacks.append(_lunge(kp, not horizontal, -0.45))
		"erupt":
			for i in 3:
				attacks.append({"kind": "erupt", "t": -0.55 * i, "aimed": false})
		"pull":
			attacks.append({"kind": "pull", "t": 0.0})
			Sfx.play("pull", -6.0, 0.6)
		"beam1":
			attacks.append(_ray(eye_pos(), kp, 1.0, 0.35, 0.5, 8.0, "eye"))
		"beam2":
			for i in 2:
				attacks.append(_ray(eye_pos(), kp, 0.9, 0.3, 0.45, 8.0, "eye", {}, -0.75 * i))
		"beam":
			for i in 3:
				attacks.append(_ray(eye_pos(), kp, 0.8, 0.3, 0.45, 8.0, "eye", {}, -0.62 * i))
		"cross":
			# Eyes open in the walls: one line across, one line down, both
			# through where the keeper is now.
			_wall_ray(kp, true, 0.0)
			_wall_ray(kp, false, -0.25)
		"grid":
			if int(Boss.T_GRID_RAYS[Boss.tier()]) >= 5:
				for i in 3:
					_wall_ray(kp + Vector2((i - 1) * 96.0, 0), false, -0.12 * i)
				_wall_ray(kp, true, -0.4)
				var y2: float = kp.y - 72.0 if kp.y - 72.0 > arena.position.y + 20.0 else kp.y + 72.0
				_wall_ray(Vector2(kp.x, y2), true, -0.52)
			else:
				# The thinner grid: two down, one across.
				var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
				_wall_ray(kp, false, 0.0)
				_wall_ray(kp + Vector2(side * 96.0, 0), false, -0.15)
				_wall_ray(kp, true, -0.45)
		"wall":
			attacks.append(_sweep_beam(1.0 if kp.x >= base.x else -1.0, 1.75))
		"jaws":
			attacks.append(_sweep_beam(-1.0, 1.29))
			attacks.append(_sweep_beam(1.0, 1.29))


# A laser along a line: a warning for `tele`, a bright lock, then it burns for
# `fire` seconds. `track` "eye" or "stalk" keeps it aimed at the keeper until
# it locks (from the great eye, or from the stalk `s`); "" is a fixed line.
func _ray(a: Vector2, toward: Vector2, tele: float, lock: float, fire: float, w: float, track: String = "", s: Dictionary = {}, delay: float = 0.0) -> Dictionary:
	stats["rays"] += 1
	var dir: Vector2 = (toward - a).normalized() if toward.distance_to(a) > 0.5 else Vector2.UP
	return {"kind": "ray", "t": delay, "a": a, "b": _to_wall(a, dir), "tele": tele, "lock": lock, "fire": fire, "w": w,
		"track": track, "stalk": s, "wall_eye": false, "locked": false, "fired": false}


# A fixed laser from an eye that opens in the wall: across the chamber at
# p.y (`across`), or down it at p.x.
func _wall_ray(p: Vector2, across: bool, delay: float) -> void:
	var a: Vector2
	var b: Vector2
	if across:
		var y: float = clampf(p.y, arena.position.y + 10.0, arena.end.y - 10.0)
		var from_left: bool = _rng.randf() < 0.5
		a = Vector2(arena.position.x if from_left else arena.end.x, y)
		b = Vector2(arena.end.x if from_left else arena.position.x, y)
	else:
		var x: float = clampf(p.x, arena.position.x + 10.0, arena.end.x - 10.0)
		a = Vector2(x, arena.position.y)
		b = Vector2(x, arena.end.y)
	var r: Dictionary = _ray(a, b, 1.0, 0.25, 0.4, 3.0, "", {}, delay)
	r["wall_eye"] = true
	attacks.append(r)


# A wall of light from the great eye: it starts along the floor on one side
# (`side` -1 left, +1 right) and sweeps up to `to` radians above it.
func _sweep_beam(side: float, to: float) -> Dictionary:
	stats["sweeps"] += 1
	return {"kind": "sweep", "t": 0.0, "side": side, "from": -0.3, "to": to, "tele": 1.2, "dur": 2.2, "fired": false}


static func sweep_angle(a: Dictionary) -> float:
	return lerpf(a["from"], a["to"], clampf((a["t"] - a["tele"]) / a["dur"], 0.0, 1.0))


func _sweep_dir(side: float, ang: float) -> Vector2:
	return Vector2(side * cos(ang), -sin(ang))


func _strike(a: Vector2, b: Vector2, tele: float, ext: float, hold: float, retract: float, width: float, delay: float) -> Dictionary:
	return {"kind": "strike", "t": delay, "a": a, "b": b, "tele": tele, "ext": ext, "hold": hold, "retract": retract,
		"w": width, "seed": _rng.randf() * TAU, "struck": false}


func _lunge(kp: Vector2, horizontal: bool, delay: float) -> Dictionary:
	if horizontal:
		var from_left: bool = _rng.randf() < 0.5
		var y: float = clampf(kp.y, arena.position.y + 14.0, arena.end.y - 50.0)
		var a := Vector2(arena.position.x if from_left else arena.end.x, y)
		var b := Vector2(arena.end.x if from_left else arena.position.x, y)
		return _strike(a, b, 0.85, 0.28, 0.3, 0.45, 6.0, delay)
	var x: float = clampf(kp.x, arena.position.x + 14.0, arena.end.x - 14.0)
	if absf(x - base.x) < 60.0:
		x = base.x + 60.0 * (1.0 if kp.x >= base.x else -1.0)
	return _strike(Vector2(x, arena.position.y), Vector2(x, arena.end.y), 0.85, 0.28, 0.3, 0.45, 6.0, delay)


# Where the ray from `a` along `dir` leaves the arena.
func _to_wall(a: Vector2, dir: Vector2) -> Vector2:
	var best: float = 600.0
	if dir.x > 0.001:
		best = minf(best, (arena.end.x - a.x) / dir.x)
	elif dir.x < -0.001:
		best = minf(best, (arena.position.x - a.x) / dir.x)
	if dir.y > 0.001:
		best = minf(best, (arena.end.y - a.y) / dir.y)
	elif dir.y < -0.001:
		best = minf(best, (arena.position.y - a.y) / dir.y)
	return a + dir * maxf(0.0, best)


static func strike_ext(a: Dictionary) -> float:
	var t: float = a["t"] - a["tele"]
	if t < 0.0:
		return 0.0
	if t < a["ext"]:
		return t / a["ext"]
	t -= a["ext"]
	if t < a["hold"]:
		return 1.0
	t -= a["hold"]
	return maxf(0.0, 1.0 - t / a["retract"])


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.001:
		return p.distance_to(a)
	var u: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * u)


func _update_attacks(delta: float, kp: Vector2) -> void:
	for i in range(attacks.size() - 1, -1, -1):
		var a: Dictionary = attacks[i]
		a["t"] += delta
		if a["t"] < 0.0:
			continue
		var done: bool = false
		match a["kind"]:
			"strike":
				var e: float = strike_ext(a)
				if e > 0.0 and not a["struck"]:
					a["struck"] = true
					InputSystem.shake(8.0, 0.2, 26.0)
					Sfx.play("whip", -8.0, _rng.randf_range(0.8, 1.1))
				if e > 0.15 and _seg_dist(kp, a["a"], a["a"].lerp(a["b"], e)) < a["w"] + 5.0:
					_hurt(a["a"].lerp(a["b"], e * 0.5), "tentacle")
				done = a["t"] >= a["tele"] + a["ext"] + a["hold"] + a["retract"]
			"erupt":
				if not a["aimed"]:
					a["aimed"] = true
					var x: float = clampf(kp.x, arena.position.x + 12.0, arena.end.x - 12.0)
					var top: float = clampf(kp.y - 16.0, arena.position.y + 8.0, arena.end.y - 70.0)
					# A spike is a strike from the floor, straight up.
					var s: Dictionary = _strike(Vector2(x, arena.end.y), Vector2(x, top), 0.75, 0.14, 0.3, 0.35, 7.0, 0.0)
					s["spike"] = true
					attacks.append(s)
				done = true
			"pull":
				if a["t"] < 2.8:
					var d: Vector2 = eye_pos() - kp
					# Drags the keeper in, but never onto the body itself.
					if d.length() > 92.0:
						_shove_keeper(d.normalized() * 34.0 * delta)
					if fposmod(time, 0.05) < delta:
						var ang: float = _rng.randf() * TAU
						var p: Vector2 = eye_pos() + Vector2.RIGHT.rotated(ang) * _rng.randf_range(90, 170)
						if arena.has_point(p):
							fx.append({"p": p, "v": (eye_pos() - p).normalized() * 120.0, "life": 0.6, "col": Pix.VIOLET_LIGHT, "s": 1.0})
				else:
					done = true
			"ray":
				var t: float = a["t"]
				var st: Dictionary = a["stalk"]
				if a["track"] == "stalk" and not st.get("alive", false):
					done = true
				elif t < a["tele"]:
					if a["track"] != "":
						var o: Vector2 = eye_pos() if a["track"] == "eye" else st["pos"]
						a["a"] = o
						if kp.distance_to(o) > 1.0:
							a["b"] = _to_wall(o, (kp - o).normalized())
				elif t < a["tele"] + a["lock"]:
					if not a["locked"]:
						a["locked"] = true
						Sfx.play("charge", -8.0 if a["w"] > 5.0 else -16.0, 1.3)
				elif t < a["tele"] + a["lock"] + a["fire"]:
					if not a["fired"]:
						a["fired"] = true
						var big: bool = a["w"] > 5.0
						InputSystem.shake(16.0 if big else 5.0, 0.4 if big else 0.2, 28.0)
						Sfx.play("beam", -4.0 if big else -14.0, 0.8 if big else 1.5)
					if _seg_dist(kp, a["a"], a["b"]) < a["w"] + 3.0:
						_hurt(a["a"], "gaze" if a["track"] == "eye" else "laser")
				else:
					done = true
			"sweep":
				if state != "open":
					done = true
				elif a["t"] >= a["tele"]:
					if not a["fired"]:
						a["fired"] = true
						Sfx.play("beam", -3.0, 0.6)
					if fposmod(a["t"], 0.12) < delta:
						InputSystem.shake(6.0, 0.15, 30.0)
					var sdir: Vector2 = _sweep_dir(a["side"], sweep_angle(a))
					if _seg_dist(kp, eye_pos(), _to_wall(eye_pos(), sdir)) < 9.0:
						_hurt(eye_pos(), "gaze")
					done = a["t"] >= a["tele"] + a["dur"] + 0.25
		if done:
			attacks.remove_at(i)


# ---------------------------------------------------------------- damage

# An explosion at `pos` (this node's space). kind: bomb, mine, blast.
# `radius` overrides the kind's own (the Suit Blaster's comes from its upgrade).
func explosion(pos: Vector2, kind: String, radius: float = 0.0) -> void:
	if state == "rise" or state == "dying" or state == "dead":
		return
	var d: Dictionary = Boss.DAMAGE.get(kind, Boss.DAMAGE["bomb"])
	var r: float = radius if radius > 0.0 else float(d["radius"])
	for s: Dictionary in stalks:
		if s["alive"] and s["grow"] >= 0.6 and pos.distance_to(s["pos"]) <= r + 10.0:
			s["hp"] -= float(d["stalk"])
			s["flash"] = 0.25
			if s["hp"] <= 0.0:
				_pop_stalk(s)
	if pos.distance_to(eye_pos()) <= r + 34.0:
		if is_open():
			_damage_core(float(d["core"]))
		elif state == "fight" or state == "open":
			# The lid holds: sparks, no damage.
			_clang = 0.5
			stats["blocked"] += 1
			_burst(eye_pos(), 10, Pix.VIOLET_LIGHT, 90.0)
			Sfx.play("clang", -6.0, 1.0)


func _damage_core(amount: float) -> void:
	var before: float = hp
	hp = maxf(0.0, hp - amount)
	_hit_flash = 0.35
	stats["core_hits"] += 1
	_burst(eye_pos(), 24, Pix.IRIS, 130.0)
	_burst(eye_pos(), 12, Pix.SCLERA, 180.0)
	InputSystem.shake(22.0, 0.45, 22.0)
	Sfx.play("hurt", -2.0, _rng.randf_range(0.8, 1.0))
	_hitstop(0.05, 0.07)
	ModLoaderLog.info("Velle hit for %.0f: %.0f / %.0f" % [amount, hp, Boss.CORE_HP], "cejdan-StoryMode")
	if hp <= 0.0:
		attacks.clear()
		orbs.clear()
		for s: Dictionary in stalks:
			if s["alive"]:
				_pop_stalk(s)
		_set_state("dying")
		pickups.clear()
		_white = 1.0
		_hitstop(0.2, 0.9)
		Sfx.play("roar", 0.0, 0.6)
		return
	var new_phase: int = phase
	for i in Boss.PHASE_AT.size():
		if hp <= float(Boss.PHASE_AT[i]):
			new_phase = i + 1
	if new_phase != phase and before > hp:
		phase = new_phase
		attacks.clear()
		orbs.clear()
		_shock = 0.0
		_white = 0.8
		_hitstop(0.25, 0.45)
		_drop_heart()
		_set_state("roar")
		InputSystem.shake(30.0, 1.0, 16.0)
		Sfx.play("roar", -1.0, 0.85 - 0.1 * phase)
		ModLoaderLog.info("Velle: phase %d" % (phase + 1), "cejdan-StoryMode")
		phase_changed.emit(phase)


# A beat of slow motion on a big hit (real seconds, whatever the time scale).
# Left alone when something else, a playtest say, has changed the game speed.
func _hitstop(scale: float, real_sec: float) -> void:
	if not is_equal_approx(Engine.time_scale, 1.0) or not is_inside_tree():
		return
	Engine.time_scale = scale
	await get_tree().create_timer(real_sec, true, false, true).timeout
	if is_equal_approx(Engine.time_scale, scale):
		Engine.time_scale = 1.0


# ---------------------------------------------------------------- hearts

# A heart torn out of the wounded eye; it drifts up and waits to be taken.
func _drop_heart() -> void:
	if not Boss.HEART_ON_PHASE:
		return
	var side: float = -1.0 if _kp().x < base.x else 1.0
	pickups.append({"p": eye_pos() + Vector2(0, -20), "v": Vector2(side * 70.0, -150.0), "t": 0.0})
	stats["hearts_dropped"] += 1


func _update_pickups(delta: float, kp: Vector2) -> void:
	var inner: Rect2 = arena.grow(-14.0)
	for i in range(pickups.size() - 1, -1, -1):
		var h: Dictionary = pickups[i]
		h["t"] += delta
		h["v"] *= 1.0 - delta * 2.2
		h["p"] += h["v"] * delta
		h["p"] = Vector2(clampf(h["p"].x, inner.position.x, inner.end.x), clampf(h["p"].y, inner.position.y, inner.end.y))
		if h["t"] > 0.5 and kp.distance_to(h["p"]) < 15.0 and health != null and health.heal():
			stats["hearts_taken"] += 1
			_burst(h["p"], 14, Color("ff3b4f"), 90.0)
			Sfx.play("heart", -4.0, 1.2)
			pickups.remove_at(i)
		elif h["t"] > Boss.HEART_SECONDS:
			pickups.remove_at(i)


# ---------------------------------------------------------------- bombs

func live_bombs() -> int:
	var n: int = 0
	for i in range(bombs.size() - 1, -1, -1):
		if not is_instance_valid(bombs[i]) or bombs[i].is_queued_for_deletion():
			bombs.remove_at(i)
		else:
			n += 1
	return n


func _update_bombs(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_return_lost_bombs()
	if not spawn_bombs:
		return
	_bomb_t -= delta
	if _bomb_t > 0.0:
		return
	_bomb_t = Boss.BOMB_EVERY_OPEN if state == "open" else Boss.BOMB_EVERY
	if live_bombs() >= Boss.BOMB_CAP:
		return
	spawn_bomb(Vector2(_bomb_x(), arena.position.y + 16.0))


# Where the next charge falls: clear of Velle's body, and over floor that is
# still there when it can be.
func _bomb_x() -> float:
	var x: float = base.x + 120.0
	for tries in 12:
		x = _rng.randf_range(arena.position.x + 16.0, arena.end.x - 16.0)
		if absf(x - base.x) > 78.0 and (tries >= 8 or floor_at(x)):
			break
	return x


# Is the chamber floor still there under x?
func floor_at(x: float) -> bool:
	if chamber.size == Vector2i.ZERO or Level.map == null:
		return true
	var col: int = chamber.position.x + clampi(int((x - arena.position.x) / 24.0), 0, chamber.size.x - 1)
	return not Level.map.is_tile_empty(Vector2i(col, chamber.end.y))


# A charge that fell out of the chamber (through a hole blown in the floor)
# comes straight back down from the roof.
func _return_lost_bombs() -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var b = bombs[i]
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			bombs.remove_at(i)
			continue
		if b.activated or b.isCarried():
			continue
		var p: Vector2 = to_local(b.global_position)
		if p.y > arena.end.y + 8.0 or p.x < arena.position.x - 8.0 or p.x > arena.end.x + 8.0:
			bombs.remove_at(i)
			b.queue_free()
			stats["bombs_returned"] += 1
			spawn_bomb(Vector2(_bomb_x(), arena.position.y + 16.0))


# An old mining charge shaken loose from the roof at `pos`; it falls to the
# floor and lies there until the keeper picks it up.
func spawn_bomb(pos: Vector2) -> Node:
	for i in 10:
		fx.append({"p": Vector2(pos.x + _rng.randf_range(-5, 5), arena.position.y + _rng.randf_range(0, 12)),
			"v": Vector2(_rng.randf_range(-8, 8), _rng.randf_range(150, 260)), "life": 0.9, "col": Color("8a7f9c"), "s": 1.0})
	var bomb = Level.drops.network_spawn({"type": CONST.CAVEBOMB, "position": to_global(pos), "team": "team1"})
	if bomb != null:
		bomb.set_meta("story_calm", true)
		bombs.append(bomb)
		stats["bombs_spawned"] += 1
	Sfx.play("drop", -14.0, _rng.randf_range(0.9, 1.1))
	return bomb


# ---------------------------------------------------------------- fx

func _burst(p: Vector2, n: int, col: Color, speed: float) -> void:
	for i in n:
		var v: Vector2 = Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(0.3, 1.0) * speed
		fx.append({"p": p, "v": v, "life": _rng.randf_range(0.3, 0.8), "col": col, "s": float(1 + _rng.randi() % 2)})


func _update_fx(delta: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f["p"] += f["v"] * delta
		f["v"] *= 1.0 - delta * 1.5
		f["life"] -= delta
		if f["life"] <= 0.0 or f["p"].y > arena.end.y:
			fx.remove_at(i)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var kp: Vector2 = _kp()
	_draw_wall_eyes(kp)
	_draw_telegraphs()
	_draw_root_tentacles()
	_draw_strikes()
	_draw_body(kp)
	_draw_stalks(kp)
	_draw_orbs()
	_draw_beams()
	_draw_pickups()
	# Idle charges are dark on dark rock: a soft amber ring marks each one.
	for b in bombs:
		if is_instance_valid(b) and not b.activated and not b.isCarried():
			var bp: Vector2 = to_local(b.global_position)
			var pulse: float = 0.5 + 0.5 * sin(time * 5.0 + bp.x * 0.1)
			draw_arc(bp, 10.0 + pulse * 2.0, 0.0, TAU, 20, Color(Pix.IRIS, 0.35 + 0.35 * pulse), 1.0)
			Pix.disc(self, bp, 9.0, Color(Pix.IRIS, 0.10))
	for f: Dictionary in fx:
		draw_rect(Rect2(f["p"].round(), Vector2(f["s"], f["s"])), Color(f["col"], clampf(f["life"] * 3.0, 0.0, 1.0)))
	if _shock >= 0.0:
		var r: float = _shock * 190.0
		draw_arc(eye_pos(), r, PI, TAU, 40, Color(Pix.VIOLET_LIGHT, clampf(1.0 - _shock / 1.2, 0.0, 1.0)), 3.0)
		draw_arc(eye_pos(), r * 0.8, PI, TAU, 40, Color(Pix.VIOLET, clampf(0.7 - _shock / 1.2, 0.0, 1.0)), 2.0)
	if _white > 0.0:
		draw_rect(arena, Color(1, 1, 1, minf(0.7, _white * 0.7)))
	_draw_health_bar()


# Eyes in the chamber walls: more of them open with every phase.
const WALL_EYES: Array = [Vector2(0.0, 0.3), Vector2(1.0, 0.3), Vector2(0.25, 0.0), Vector2(0.75, 0.0),
	Vector2(0.0, 0.62), Vector2(1.0, 0.62), Vector2(0.1, 0.0), Vector2(0.9, 0.0),
	Vector2(0.0, 0.12), Vector2(1.0, 0.12), Vector2(0.42, 0.0), Vector2(0.58, 0.0)]


func _draw_wall_eyes(kp: Vector2) -> void:
	if state == "rise" or state == "dead":
		return
	var n: int = mini(WALL_EYES.size(), 4 * (phase + 1))
	for i in n:
		var p: Vector2 = arena.position + Vector2(WALL_EYES[i].x * arena.size.x, WALL_EYES[i].y * arena.size.y)
		p += Vector2(5.0 if WALL_EYES[i].x == 0.0 else (-5.0 if WALL_EYES[i].x == 1.0 else 0.0), 5.0 if WALL_EYES[i].y == 0.0 else 0.0)
		# The newest four are still opening.
		var open: float = 1.0 if i < 4 * phase else _wall_open
		if state == "dying":
			open = clampf(1.0 - state_t * 0.6 + i * 0.05, 0.0, 1.0)
		if open <= 0.05:
			continue
		Pix.disc(self, p, 6.0, Pix.EDGE)
		if open < 0.6:
			draw_rect(Rect2((p + Vector2(-4, 0)).round(), Vector2(8, 1)), Pix.FLESH_LIGHT)
		else:
			Pix.eye(self, p, Pix.eye_frame_toward(p, kp, time, i * 0.53), 0.5)


func _draw_pickups() -> void:
	for h: Dictionary in pickups:
		var p: Vector2 = h["p"] + Vector2(0, sin(h["t"] * 3.0) * 3.0)
		var fade: float = clampf((Boss.HEART_SECONDS - h["t"]) / 3.0, 0.0, 1.0)
		if fade < 1.0 and fposmod(h["t"] * 6.0, 1.0) < 0.4:
			continue
		Pix.disc(self, p, 9.0 + sin(h["t"] * 5.0), Color(1.0, 0.25, 0.35, 0.22))
		Pix.disc(self, p, 6.0, Color(1.0, 0.25, 0.35, 0.3))
		Pix.heart(self, p + Vector2(-3.5, -3.0), true)


func _shake_off() -> Vector2:
	if state == "dying":
		return Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1)).round()
	if _hit_flash > 0.0:
		return Vector2(_rng.randf_range(-1, 1), 0).round()
	return Vector2.ZERO


func _draw_body(kp: Vector2) -> void:
	if rise <= 0.02:
		return
	var o: Vector2 = base + _shake_off()
	var breathe: float = sin(time * 1.6) * 1.5
	var r: float = rise
	var dead: bool = state == "dead"
	var body: Color = Pix.FLESH if not dead else Color("15101c")
	var mid: Color = Pix.FLESH_MID if not dead else Color("231a30")
	# Outline, then flesh: side lobes and the main mound, cut at the floor.
	for pass_i in 2:
		var grow: float = 1.0 if pass_i == 0 else 0.0
		var col: Color = Pix.EDGE if pass_i == 0 else body
		Pix.ellipse(self, o + Vector2(-40, -14 * r), 28 + grow + breathe * 0.5, 20 * r + grow, col, -1.0, 0.7)
		Pix.ellipse(self, o + Vector2(40, -14 * r), 28 + grow - breathe * 0.5, 20 * r + grow, col, -1.0, 0.7)
		Pix.ellipse(self, o + Vector2(0, -30 * r), 50 + grow + breathe, 36 * r + grow, col, -1.0, 0.83)
	# Lighter folds.
	Pix.ellipse(self, o + Vector2(-8, -40 * r), 34 + breathe, 20 * r, mid, -1.0, 0.2)
	Pix.ellipse(self, o + Vector2(-44, -19 * r), 16, 9 * r, mid, -1.0, 0.1)
	Pix.ellipse(self, o + Vector2(40, -20 * r), 16, 9 * r, mid, -1.0, 0.1)
	if r < 0.6:
		return
	# The crowd of small eyes.
	for i in BODY_EYES.size():
		var p: Vector2 = o + Vector2(BODY_EYES[i].x, BODY_EYES[i].y * r)
		if dead:
			draw_rect(Rect2((p + Vector2(-4, 0)).round(), Vector2(8, 1)), Pix.EDGE)
			continue
		if state == "dying" and state_t > 0.3 * (i + 1):
			draw_rect(Rect2((p + Vector2(-3, -1)).round(), Vector2(6, 3)), Pix.IRIS_DEEP)
			continue
		var f: int = Pix.eye_frame_toward(p, kp, time, i * 0.37)
		Pix.eye(self, p, f, 1.0, Color.WHITE if _hit_flash <= 0.0 else Color(3, 3, 3))
	_draw_great_eye(o + Vector2(0, -36.0 * r), kp, dead)


func _draw_great_eye(c: Vector2, kp: Vector2, dead: bool) -> void:
	Pix.ellipse(self, c, 21, 17, Pix.EDGE)
	Pix.ellipse(self, c, 19, 15, Pix.FLESH_LIGHT if not dead else Color("2c2238"))
	if dead:
		draw_rect(Rect2((c + Vector2(-15, 0)).round(), Vector2(30, 2)), Pix.EDGE)
		return
	if lid > 0.06:
		var ry: float = 13.0 * lid
		Pix.ellipse(self, c, 17, ry, Pix.SCLERA if _hit_flash <= 0.0 else Color.WHITE)
		var look: Vector2 = (kp - c).limit_length(60.0) / 60.0 * Vector2(6, 3)
		if state == "dying":
			look = Vector2(sin(time * 9.0) * 6.0, cos(time * 7.0) * 3.0)
		var ic: Vector2 = c + look
		var ir: float = minf(9.0, ry)
		Pix.ellipse(self, ic, 9, ir, Pix.IRIS_DEEP)
		Pix.ellipse(self, ic, 7, maxf(1.0, ir - 2.0), Pix.IRIS)
		var ph: float = maxf(1.0, round(ir * 1.5))
		draw_rect(Rect2((ic + Vector2(-1, -ph * 0.5)).round(), Vector2(3, ph)), Pix.PUPIL)
		draw_rect(Rect2((ic + Vector2(-4, -ir * 0.5)).round(), Vector2(2, 2)), Color.WHITE)
		if state == "open":
			# "Hit me": rings that pulse for as long as the eye can be hurt.
			var pulse: float = 0.6 + 0.4 * sin(time * 9.0)
			draw_arc(c, 25.0, 0.0, TAU, 36, Color(Pix.IRIS, pulse), 2.0)
			var out: float = fposmod(time * 0.9, 1.0)
			draw_arc(c, 25.0 + out * 16.0, 0.0, TAU, 36, Color(Pix.IRIS, (1.0 - out) * 0.6), 1.0)
	else:
		# Shut: a seam, and the barrier's violet shimmer over the lid.
		draw_rect(Rect2((c + Vector2(-16, 0)).round(), Vector2(32, 1)), Pix.EDGE)
		draw_rect(Rect2((c + Vector2(-13, 1)).round(), Vector2(26, 1)), Color(Pix.VIOLET, 0.6 + 0.3 * sin(time * 4.0)))
		for i in 3:
			var sx: float = fposmod(time * (14.0 + 5.0 * i) + i * 11.0, 30.0) - 15.0
			draw_rect(Rect2((c + Vector2(sx, -6 + i * 5)).round(), Vector2(1, 1)), Pix.VIOLET_LIGHT)
	if _clang > 0.0:
		draw_arc(c, 23.0 + (0.5 - _clang) * 20.0, 0.0, TAU, 28, Color(Pix.VIOLET_LIGHT, _clang * 2.0), 2.0)


func _draw_root_tentacles() -> void:
	if rise < 0.5 or state == "dead":
		return
	for i in 4:
		var side: float = -1.0 if i < 2 else 1.0
		var reach: float = (58.0 if i % 2 == 0 else 86.0) * rise
		var a: Vector2 = base + Vector2(side * 42.0, -6.0)
		var b: Vector2 = base + Vector2(side * (42.0 + reach), -8.0 - 10.0 * sin(time * 1.1 + i * 1.9))
		var pts: PackedVector2Array = Pix.tentacle_points(a, b, time, 5.0, i * 2.3, 1.0, -side * 8.0)
		Pix.tentacle(self, pts, 5.0, 1.0, Pix.FLESH)


func _draw_stalks(kp: Vector2) -> void:
	for s: Dictionary in stalks:
		var alpha: float = 1.0
		var ext: float = 1.0
		if not s["alive"]:
			ext = 1.0 - s["gone"]
			if ext <= 0.02:
				continue
		var bend: float = 18.0 * sin(s["seed"])
		var pts: PackedVector2Array = Pix.tentacle_points(s["anchor"], s["pos"], time, 6.0, s["seed"], ext, bend)
		var tip: Vector2 = Pix.tentacle(self, pts, 5.0, 3.0, Pix.FLESH_MID, alpha)
		if not s["alive"]:
			continue
		var mod: Color = Color.WHITE
		if s["flash"] > 0.0:
			mod = Color(3, 3, 3)
		elif s["charge"] >= 0.0:
			# Charging a spit: the eye swells and glows.
			var c: float = 1.0 - s["charge"] / 0.7
			Pix.disc(self, tip, 9.0 + c * 4.0, Color(Pix.VIOLET, 0.35 + 0.3 * c))
			mod = Color(1.0 + c, 1.0 + c * 0.6, 1.0 + c)
		Pix.disc(self, tip, 9.0, Pix.EDGE)
		Pix.eye(self, tip, Pix.eye_frame_toward(tip, kp, time, s["seed"]), 1.0, mod)


func _draw_orbs() -> void:
	for o: Dictionary in orbs:
		var p: Vector2 = o["p"]
		var tail: Vector2 = -o["v"].normalized()
		for i in 3:
			Pix.disc(self, p + tail * (3.0 + i * 3.0), 2.0 - i * 0.5, Color(Pix.VIOLET, 0.5 - i * 0.14))
		Pix.disc(self, p, o["r"] + 1.0, Pix.EDGE)
		Pix.disc(self, p, o["r"], Pix.VIOLET if fposmod(time * 8.0, 1.0) < 0.5 else Pix.VIOLET_LIGHT)
		draw_rect(Rect2((p + Vector2(-1, -1)).round(), Vector2(2, 2)), Pix.IRIS)


func _dashes(a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	var d: Vector2 = b - a
	var n: int = int(d.length() / 8.0)
	if n < 1:
		return
	var off: float = fposmod(time * 3.0, 1.0)
	for i in n:
		var u0: float = (float(i) + off) / n
		var u1: float = minf(1.0, u0 + 0.5 / n)
		if u0 < 1.0:
			draw_line((a + d * u0).round(), (a + d * u1).round(), col, width)


func _draw_telegraphs() -> void:
	for a: Dictionary in attacks:
		if a["t"] < 0.0:
			continue
		if a["kind"] == "strike" and a["t"] < a["tele"]:
			var f: float = a["t"] / a["tele"]
			var blink: float = 0.35 + 0.65 * absf(sin(a["t"] * (10.0 + 14.0 * f)))
			draw_line(a["a"], a["b"], Color(Pix.WARN, 0.10 + 0.14 * f), a["w"] * 2.0)
			_dashes(a["a"], a["b"], Color(Pix.WARN, blink), 1.0)
			if a.get("spike", false):
				draw_arc(a["b"], 7.0 + 5.0 * (1.0 - f), 0, TAU, 16, Color(Pix.WARN, blink), 1.0)
		elif a["kind"] == "sweep" and a["t"] < a["tele"]:
			# The half of the chamber the wall of light will cross.
			var f2: float = a["t"] / a["tele"]
			var blink2: float = 0.4 + 0.6 * absf(sin(a["t"] * (8.0 + 12.0 * f2)))
			for i in 9:
				var ang: float = lerpf(a["from"], a["to"], i / 8.0)
				var d2: Vector2 = _sweep_dir(a["side"], ang)
				draw_line(eye_pos(), _to_wall(eye_pos(), d2), Color(Pix.WARN, 0.07 + 0.08 * f2), 14.0)
			_dashes(eye_pos(), _to_wall(eye_pos(), _sweep_dir(a["side"], a["from"])), Color(Pix.WARN, blink2), 2.0)
		elif a["kind"] == "pull" and a["t"] < 2.8:
			for i in 3:
				var r: float = 150.0 - fposmod(time * 70.0 + i * 50.0, 150.0)
				draw_arc(eye_pos(), r, PI, TAU, 32, Color(Pix.VIOLET, 0.25 * (r / 150.0)), 1.0)


func _draw_strikes() -> void:
	for a: Dictionary in attacks:
		if a["kind"] != "strike" or a["t"] < 0.0:
			continue
		var e: float = strike_ext(a)
		if e <= 0.0:
			# Winding up: a stub quivers at the root.
			if a["t"] > a["tele"] * 0.4:
				var dir: Vector2 = (a["b"] - a["a"]).normalized()
				var pts0: PackedVector2Array = Pix.tentacle_points(a["a"], a["a"] + dir * 16.0, time * 4.0, 2.0, a["seed"])
				Pix.tentacle(self, pts0, a["w"], 3.0, Pix.FLESH_MID)
			continue
		var pts: PackedVector2Array = Pix.tentacle_points(a["a"], a["b"], time * 1.5, 3.0, a["seed"], e)
		var tip: Vector2 = Pix.tentacle(self, pts, a["w"], 2.5, Pix.FLESH_MID)
		if a.get("spike", false) and e > 0.9:
			Pix.eye(self, tip + Vector2(0, 4), int(time * 8.0) % 4, 1.0)


func _draw_beams() -> void:
	for a: Dictionary in attacks:
		if a["t"] < 0.0:
			continue
		if a["kind"] == "sweep":
			if a["t"] >= a["tele"]:
				var to2: Vector2 = _to_wall(eye_pos(), _sweep_dir(a["side"], sweep_angle(a)))
				var fl: float = 0.8 + 0.2 * sin(time * 40.0)
				draw_line(eye_pos(), to2, Color(Pix.IRIS_DEEP, 0.8), 15.0 * fl)
				draw_line(eye_pos(), to2, Color(Pix.IRIS, 1.0), 9.0 * fl)
				draw_line(eye_pos(), to2, Color.WHITE, 3.0)
				if fposmod(time, 0.04) < 0.02:
					_burst(to2, 2, Pix.IRIS, 70.0)
			continue
		if a["kind"] != "ray":
			continue
		var from: Vector2 = a["a"]
		var to: Vector2 = a["b"]
		var t: float = a["t"]
		var w: float = a["w"]
		if a["wall_eye"]:
			# The eye in the wall it comes from.
			var grow: float = clampf(t / 0.3, 0.0, 1.0)
			Pix.disc(self, from, 7.0 * grow, Pix.EDGE)
			if grow >= 1.0:
				Pix.eye(self, from, int(time * 10.0) % 4, 0.5, Color(1.6, 1.2, 1.2))
		if t < a["tele"]:
			_dashes(from, to, Color(Pix.WARN, 0.5 + 0.5 * sin(t * 30.0)), 1.0)
			draw_line(from, to, Color(Pix.WARN, 0.08), w * 2.0)
		elif t < a["tele"] + a["lock"]:
			draw_line(from, to, Color(1, 1, 1, 0.9), 1.0)
			draw_line(from, to, Color(Pix.WARN, 0.25), w + 1.0)
		elif t < a["tele"] + a["lock"] + a["fire"]:
			var f: float = 1.0 - (t - a["tele"] - a["lock"]) / a["fire"]
			draw_line(from, to, Color(Pix.IRIS_DEEP, 0.8), (w * 1.5) * f + 3.0)
			draw_line(from, to, Color(Pix.IRIS, 1.0), w * f + 2.0)
			draw_line(from, to, Color.WHITE, w * 0.35 * f + 1.0)


func _draw_health_bar() -> void:
	if state == "rise" or state == "dead":
		return
	var w: float = 180.0
	var p: Vector2 = Vector2(arena.get_center().x - w * 0.5, arena.position.y + 7.0).round()
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 6)), Color(0.03, 0.02, 0.06, 0.85))
	var frac: float = hp / Boss.CORE_HP
	var col: Color = Pix.SUCKER if _hit_flash <= 0.0 else Color.WHITE
	draw_rect(Rect2(p, Vector2(round(w * frac), 4)), col)
	draw_rect(Rect2(p, Vector2(round(w * frac), 1)), Pix.VIOLET_LIGHT)
	# Phase marks.
	for at in Boss.PHASE_AT:
		var x: float = round(w * float(at) / Boss.CORE_HP)
		draw_rect(Rect2(p + Vector2(x, -1), Vector2(1, 6)), Color(0.03, 0.02, 0.06, 1.0))
	# An eye for a name tag.
	Pix.disc(self, p + Vector2(-12, 2), 8.0, Color(0.03, 0.02, 0.06, 0.85))
	Pix.eye(self, p + Vector2(-12, 2), int(time * 4.0) % 4 if is_open() else 4 + int(time * 1.5) % 4, 0.5)
