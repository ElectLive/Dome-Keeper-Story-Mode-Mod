extends Node2D

# The final battle on the surface (#162, #171, third pass #173). The keeper
# made it home; the ground splits beside the dome and the tentacles break out.
# Three rounds of tentacles (boss/surface_tentacle.gd, real targets for the
# dome's weapon). Each tentacle comes up with a row of eyes, and every few
# seconds one tears free as a flyer that shoots the dome (boss/eye_flyer.gd),
# so the dome fights the ground and the sky at once; a round ends when the
# flyers are dead too. The longer the battle runs the faster they all strike
# (fury).
#
# In the last round Velle's great eye (boss/great_eye.gd) rises behind the
# dome and hangs straight above it. Beaten, it closes, and stays up until
# everything else is dead. Then it sways and falls to one side of the dome
# (step "fall"). The surface monsters come in from that side only (the flyers
# among them from that side or from above), tear the remains apart and thank
# the keeper in their own language (runes unless translators are installed).
# Then `finished` fires and the boss director plays the saved ending.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const BossText = preload("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")
const TENTACLE := "res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd"
const FLYER := "res://mods-unpacked/cejdan-StoryMode/boss/eye_flyer.gd"
const GREAT := "res://mods-unpacked/cejdan-StoryMode/boss/great_eye.gd"

signal finished
signal step_changed(step: String)

# Where round tentacles come up, in px left (-) or right (+) of the dome.
const SPOTS: Array = [[-150.0, 160.0], [-215.0, -125.0, 135.0], [-200.0, -110.0, 120.0]]
const FALL_REST := 1.1        # seconds the fallen eye lies there before the monsters come
const GROUND_Y := 2.0
const RUMBLE := 2.6           # seconds of cracking ground before a round breaks out

var step: String = "rumble"   # rumble, round1, lull, round2, lull, round3, fall, allies, thanks, done
var great = null              # Velle's great eye (last round)
var fall_side: float = 1.0    # the side of the dome it falls to: +1 right, -1 left
var fight_t: float = 0.0      # seconds of battle so far (the rounds, not the pauses)
var fury: float = 1.0
var flyers_made: int = 0
var _crack_seeds: Dictionary = {}
var t: float = 0.0
var round_i: int = -1
var alive: Array = []
var allies: Array = []
var eye_at: Vector2 = Vector2.ZERO
var unit_hp: float = 60.0
var said: Array = []
var _thanks_i: int = 0
var _rng := RandomNumberGenerator.new()
var _dust: Array = []


func setup() -> void:
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	unit_hp = Boss.FINALE_TENTACLE_HP
	load(TENTACLE).register(Boss.FINALE_TENTACLE_HP)
	load(GREAT).register(Boss.FINALE_EYE_HP)
	load(FLYER).register(Boss.FINALE_FLYER_HP)
	fall_side = 1.0 if _rng.randf() < 0.5 else -1.0
	# The dome goes to battle stations, as for a wave.
	Data.apply("team1.monsters.wavepresent", true)
	Data.apply("team1.monsters.wavebattle", true)
	ModLoaderLog.info("Finale: tentacle %.0f, great eye %.0f, flyer %.0f health" % [Boss.FINALE_TENTACLE_HP, Boss.FINALE_EYE_HP, Boss.FINALE_FLYER_HP], "cejdan-StoryMode")
	InputSystem.shake(14.0, 2.0, 18.0)
	Sfx.play("burrow", 0.0, 0.6)


func _set_step(s: String) -> void:
	step = s
	t = 0.0
	ModLoaderLog.info("Finale: " + s, "cejdan-StoryMode")
	step_changed.emit(s)


func _dome():
	return Level.getDome("team1")


func _ground(offset_x: float) -> Vector2:
	var d = _dome()
	return d.global_position + Vector2(offset_x, GROUND_Y)


func _spawn_round(i: int) -> void:
	round_i = i
	var d = _dome()
	for off: float in SPOTS[i]:
		_spawn(_ground(off), d.global_position.x)
	if i == SPOTS.size() - 1:
		great = load(GREAT).make()
		great.fury = fury
		add_child(great)
		alive.append(great)
		_slow(0.3, 0.35)


# The spots of round `i`: px left (-) or right (+) of the dome.
func spots(i: int) -> Array:
	return SPOTS[i].duplicate()


func _crack_seed(off: float) -> int:
	if not _crack_seeds.has(off):
		_crack_seeds[off] = _rng.randi()
	return _crack_seeds[off]


func _spawn(pos: Vector2, dome_x: float) -> void:
	var m = load(TENTACLE).make(pos, dome_x, _crack_seed(pos.x - dome_x))
	m.fury = fury
	m.eye_freed.connect(_eye_freed)
	add_child(m)
	alive.append(m)


# An eye tears free of a living tentacle and takes to the sky over the dome.
func _eye_freed(at: Vector2) -> void:
	if not step.begins_with("round") or GameWorld.lost:
		return
	var d = _dome()
	# Its place: on the side it came from, higher with each one already up there.
	var side_left: bool = at.x < d.global_position.x
	var up: float = 0.55 + 0.32 * (flyers_alive() % 3) + _rng.randf_range(-0.08, 0.08)
	var f = load(FLYER).make(at, (PI - up) if side_left else up)
	f.fury = fury
	add_child(f)
	alive.append(f)
	flyers_made += 1


func flyers_alive() -> int:
	var n: int = 0
	for m in alive:
		if is_instance_valid(m) and not m.dead and m.techId == load(FLYER).TECH:
			n += 1
	return n


# A beat of slow motion (real seconds). Left alone when a playtest has changed
# the game speed.
func _slow(scale: float, real_sec: float) -> void:
	if not is_equal_approx(Engine.time_scale, 1.0) or not is_inside_tree():
		return
	Engine.time_scale = scale
	await get_tree().create_timer(real_sec, true, false, true).timeout
	if is_equal_approx(Engine.time_scale, scale):
		Engine.time_scale = 1.0


func living() -> int:
	var n: int = 0
	for m in alive:
		if is_instance_valid(m) and not m.dead:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if GameWorld.paused or GameWorld.lost:
		return
	t += delta
	for i in range(_dust.size() - 1, -1, -1):
		var f: Dictionary = _dust[i]
		f["v"].y += 320.0 * delta
		f["p"] += f["v"] * delta
		f["life"] -= delta
		if f["life"] <= 0.0:
			_dust.remove_at(i)
	if step.begins_with("round"):
		fight_t += delta
		fury = maxf(Boss.FINALE_FURY_FLOOR, 1.0 - Boss.FINALE_FURY_PER_S * fight_t)
		for m in alive:
			if is_instance_valid(m) and not m.dead:
				m.fury = fury
	match step:
		"rumble", "lull":
			# The ground works itself open where they will come up.
			if fposmod(t, 0.2) < delta:
				InputSystem.shake(5.0 + t * 5.0, 0.22, 24.0)
			if fposmod(t, 0.7) < delta:
				Sfx.play("drop", -12.0 + t * 3.0, _rng.randf_range(0.6, 0.9))
			if fposmod(t, 0.09) < delta and t > 0.5:
				var offs: Array = spots(round_i + 1)
				var at: Vector2 = to_local(_ground(offs[_rng.randi() % offs.size()]))
				_dust.append({"p": at + Vector2(_rng.randf_range(-14, 14), 0), "v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-110, -40) * (0.5 + t / RUMBLE)),
					"life": _rng.randf_range(0.3, 0.7), "col": Color("3b2f44")})
			if t >= RUMBLE:
				_spawn_round(round_i + 1)
				if round_i == SPOTS.size() - 1:
					Sfx.play("roar", 0.0, 0.75)
				_set_step("round%d" % (round_i + 1))
		"round1", "round2", "round3":
			if t > 1.5 and living() == 0:
				if round_i < SPOTS.size() - 1:
					_set_step("lull")
				else:
					# Everything else is dead: the closed eye comes down.
					Data.apply("team1.monsters.wavepresent", false)
					Data.apply("team1.monsters.wavebattle", false)
					if is_instance_valid(great):
						great.fall(fall_side)
					_set_step("fall")
		"fall":
			if not is_instance_valid(great):
				_call_allies()
				_set_step("allies")
			elif great.fallen and great.fall_t >= great.FALL_SWAY + great.FALL_DROP + FALL_REST:
				eye_at = great.global_position
				_call_allies()
				_set_step("allies")
		"allies":
			_move_allies(delta)
			if t >= 7.5:
				_set_step("thanks")
		"thanks":
			_move_allies(delta)
			if _thanks_i < BossText.THANKS.size() and t >= 0.4 + _thanks_i * 3.6:
				_say(_thanks_i)
				_thanks_i += 1
			if t >= 0.4 + BossText.THANKS.size() * 3.6 + 0.6:
				_set_step("done")
				finished.emit()
	queue_redraw()


# ---------------------------------------------------------------- the monsters come

const ALLY_KINDS: Array = [
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 60.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 52.0],
	["res://content/monster/flyer/Flyer.tscn", "fly", "shoot", -70.0, 70.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 56.0],
	["res://content/monster/flyer/Flyer.tscn", "fly", "shoot", -95.0, 64.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 48.0],
]


func _call_allies() -> void:
	var d = _dome()
	var n_walk: int = 0
	var n_fly: int = 0
	for i in ALLY_KINDS.size():
		var k: Array = ALLY_KINDS[i]
		if not ResourceLoader.exists(k[0]):
			continue
		# The game's own monster, with its brain taken out: only its looks walk.
		var m: Node2D = load(k[0]).instantiate()
		for c in m.get_children():
			for sig: Dictionary in c.get_signal_list():
				for con: Dictionary in c.get_signal_connection_list(sig["name"]):
					if con["callable"].get_object() == m:
						c.disconnect(sig["name"], con["callable"])
		m.set_script(null)
		m.remove_from_group("monster")
		if m is Area2D:
			m.collision_layer = 0
			m.monitorable = false
		# They all come from the side the eye fell to, so nobody crosses the
		# dome. Walkers stop on the ground on either side of the eye (the
		# first ones walk past it); flyers hang over it, half of them coming
		# down from above.
		var flies: bool = float(k[3]) < 0.0
		var ground_y: float = d.global_position.y + GROUND_Y
		var stand: Vector2
		var from: Vector2
		if flies:
			stand = Vector2(eye_at.x + fall_side * (10.0 - 34.0 * n_fly), ground_y + float(k[3]))
			from = Vector2(stand.x + fall_side * 40.0, stand.y - 330.0) if n_fly % 2 == 0 else Vector2(eye_at.x + fall_side * 470.0, stand.y - 40.0)
			n_fly += 1
		else:
			var slot: float = [-36.0, 38.0, -54.0, 56.0][n_walk % 4]
			stand = Vector2(eye_at.x + fall_side * slot, ground_y)
			from = Vector2(eye_at.x + fall_side * (230.0 + 40.0 * n_walk), ground_y)
			n_walk += 1
		m.global_position = from
		add_child(m)
		var spr = m.get_node_or_null("Sprite2D")
		if spr != null:
			Style.init(spr)
			spr.flip_h = fall_side < 0.0
			if spr.sprite_frames != null and spr.sprite_frames.has_animation(k[1]):
				spr.play(k[1])
		allies.append({"node": m, "stand": stand, "from": from, "speed": float(k[4]) * (1.25 if not flies else 1.6), "walk": k[1], "attack": k[2], "there": false, "side": fall_side, "flies": flies})
	Sfx.play("eerie", -4.0, 1.0)


func _move_allies(delta: float) -> void:
	for a: Dictionary in allies:
		var m: Node2D = a["node"]
		if not is_instance_valid(m):
			continue
		if not a["there"]:
			m.global_position = m.global_position.move_toward(a["stand"], a["speed"] * delta)
			if m.global_position.distance_to(a["stand"]) < 1.0:
				a["there"] = true
				var spr = m.get_node_or_null("Sprite2D")
				if spr != null:
					# Face the eye.
					spr.flip_h = m.global_position.x < eye_at.x
				if spr != null and spr.sprite_frames != null and spr.sprite_frames.has_animation(a["attack"]):
					spr.play(a["attack"])
		elif step == "allies" and fposmod(t + a["speed"] * 0.01, 0.5) < delta:
			# The final blows.
			for i in 5:
				_dust.append({"p": to_local(eye_at) + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-14, 0)),
					"v": Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-150, -40)), "life": _rng.randf_range(0.4, 0.9), "col": Pix.IRIS})
			if _rng.randf() < 0.5:
				Sfx.play("pop", -10.0, _rng.randf_range(0.9, 1.3))


func _say(i: int) -> void:
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	if pd == null:
		return
	var at = null
	if not allies.is_empty():
		var a: Dictionary = allies[i % allies.size()]
		if is_instance_valid(a["node"]):
			at = a["node"].global_position + Vector2(0, -44.0 - 14.0 * (i % 2))
	said.append(pd.say("arrive", at, BossText.THANKS[i], 3.8))


func _draw() -> void:
	for f: Dictionary in _dust:
		draw_rect(Rect2(f["p"].round(), Vector2(2, 2)), Color(f.get("col", Color("5a4a66")), clampf(f["life"] * 2.0, 0.0, 1.0)))
	if step == "rumble" or step == "lull":
		# The ground splits where they are about to come up: cracks spread
		# and light up from below, and the soil heaves.
		var grow: float = clampf(t / (RUMBLE * 0.85), 0.0, 1.0)
		var Tentacle = load(TENTACLE)
		var offs: Array = spots(round_i + 1)
		for i in offs.size():
			var off: float = offs[i]
			var p: Vector2 = to_local(_ground(off))
			var big: bool = false
			var glow: float = grow * (0.55 + 0.45 * sin(t * (10.0 + 14.0 * grow) + i))
			Tentacle.draw_light(self, p, _crack_seed(off), grow, glow * grow, big)
			Tentacle.draw_cracks(self, p, Tentacle.crack_lines(_crack_seed(off), big), grow, glow)
			# A mound pushing up, shuddering.
			var heave: float = grow * grow * (9.0 if big else 6.0)
			var jit: float = sin(t * 47.0 + i * 3.0) * grow
			Pix.ellipse(self, p + Vector2(jit, 1), (16.0 if big else 11.0) * (0.5 + 0.5 * grow), heave, Color("2a2130"), -1.0, 0.0)
			draw_rect(Rect2((p + Vector2(-2, -heave)).round(), Vector2(4, 1)), Color(Pix.VIOLET_LIGHT, glow))
