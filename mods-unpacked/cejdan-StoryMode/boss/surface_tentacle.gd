extends "res://content/monster/Monster.gd"

# A tentacle on the surface, in the final battle (#162, second pass #171). It
# is a real Monster (an Area2D in the "monster" group on the monster layer), so
# every dome weapon aims at it, hits it and kills it the vanilla way; only its
# looks and its behaviour are the mod's.
#
# It breaks out of the ground beside the dome: the earth splits, rock is thrown
# up, and the tentacle whips out past its full height before it settles. It
# sways, and slams the dome after a telegraph. When it dies the eye at its tip
# tears free (`eye_freed`) and the finale turns it into a flyer.
#
# `great` makes it Velle's great eye on a thick stalk: far more health, a slam
# twice as hard, and the gaze: it charges a beam at the dome for a few seconds,
# and only enough damage in that time makes it flinch and lose the shot.
#
# Built in code by make(); nothing here needs a scene file.

const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")

const TECH := "storytentacle"
const TECH_EYE := "storygreateye"

signal eye_freed(at: Vector2)

static var _uid: int = 900000

var great: bool = false
var height: float = 96.0
var dome_dir: float = 1.0        # +1 when the dome is to the right
var time: float = 0.0
var emerge_t: float = 0.0        # seconds since it broke the ground
var emerge: float = 0.0          # 0 underground .. 1 fully out (overshoots on the way)
var slam_t: float = -1.0         # seconds into a slam, -1 when idle
var next_slam: float = 3.0
var gaze_t: float = -1.0         # seconds into the gaze (great eye), -1 when idle
var gaze_hp: float = 0.0         # health when the gaze began
var flinch: float = 0.0
var attacks_done: int = 0
var fury: float = 1.0            # the finale shortens every wait as the fight drags on
var flash: float = 0.0
var sink: float = 0.0
var slams: int = 0
var gazes_fired: int = 0
var gazes_broken: int = 0
var seed_f: float = 0.0
var crack_seed: int = 0
var debris: Array = []
var _cracks: Array = []
var _burst_flash: float = 0.0
var _hitbox: CollisionShape2D = null
var _did_hit: bool = false

const EMERGE_TIME := 0.75
const SLAM_TELE := 1.0
const SLAM_STRIKE := 0.18
const SLAM_HOLD := 0.35
const SLAM_BACK := 0.6
const GAZE_FIRE := 0.7
const EARTH: Array = [Color("2a2130"), Color("3b2f44"), Color("1c1622"), Color("4a3d52")]


# Registers the two kinds' monster data.
static func register(tentacle_hp: float, eye_hp: float) -> void:
	for pair: Array in [[TECH, tentacle_hp, CONST.MONSTER_MEDIUM], [TECH_EYE, eye_hp, CONST.MONSTER_LARGE]]:
		var id: String = pair[0]
		Data.apply(id + ".health", pair[1])
		Data.apply(id + ".tier", 3)
		Data.apply(id + ".size", pair[2])
		Data.apply(id + ".fullstunthreshold", 100000.0)
		Data.apply(id + ".stunpriority", 0)
		Data.apply(id + ".minstunlevel", 0.85)


# A new tentacle at `pos` (global), not yet in the tree. `p_crack_seed` is the
# seed the finale drew its warning cracks from, so the break matches them.
static func make(pos: Vector2, dome_x: float, is_great: bool, p_crack_seed: int = 0):
	var m: Area2D = Area2D.new()
	m.set_script(load("res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd"))
	m.name = "StoryGreatEye" if is_great else "StoryTentacle"
	m.great = is_great
	m.techId = TECH_EYE if is_great else TECH
	m.teamId = "team1"
	m.height = 124.0 if is_great else randf_range(84.0, 108.0)
	m.dome_dir = 1.0 if dome_x > pos.x else -1.0
	m.seed_f = randf() * TAU
	m.crack_seed = p_crack_seed
	m.collision_layer = 128
	m.collision_mask = 0
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.add_to_group("monster")
	_uid += 1
	m.UID = _uid
	# The vanilla Monster wants an animated sprite with the flash material; the
	# tentacle draws itself, so the sprite is one clear pixel.
	var spr := AnimatedSprite2D.new()
	spr.name = "Sprite2D"
	var frames := SpriteFrames.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	frames.add_frame("default", ImageTexture.create_from_image(img))
	spr.sprite_frames = frames
	spr.material = load("res://content/monster/FlashMaterial.tres")
	m.add_child(spr)
	m.sprite = spr
	var box := CollisionShape2D.new()
	box.name = "HitboxDefault"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(34.0 if is_great else 22.0, m.height)
	box.shape = shape
	box.position = Vector2(0, -m.height * 0.5)
	m.add_child(box)
	m._hitbox = box
	m.global_position = pos
	return m


# ---------------------------------------------------------------- the break

# The cracks around a break: jagged lines from the middle, along the surface
# and down into the ground. Each is a list of points (this node's space).
static func crack_lines(crack_seed: int, big: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed
	var out: Array = []
	var n: int = 9 if big else 7
	for i in n:
		# Fanned from flat-left, down through the soil, to flat-right.
		var ang: float = lerpf(0.0, PI, (i + 0.5) / n) + rng.randf_range(-0.15, 0.15)
		var dir: Vector2 = Vector2(-cos(ang), sin(ang) * 0.75)
		var flat: bool = i == 0 or i == n - 1
		var length: float = rng.randf_range(22.0, 40.0) * (1.5 if big else 1.0) * (2.2 if flat else 1.0)
		var pts: PackedVector2Array = PackedVector2Array()
		var p: Vector2 = Vector2(rng.randf_range(-4, 4), 1.0)
		pts.append(p)
		var steps: int = 4 + rng.randi() % 3
		for j in steps:
			p += dir.rotated(rng.randf_range(-0.6, 0.6)) * (length / steps)
			p.y = maxf(p.y, 1.0)
			pts.append(p)
		out.append(pts)
	return out


# Draws `lines` from `origin`, the first `grow` (0..1) of each; `glow` (0..1)
# lights them violet from inside.
static func draw_cracks(ci: CanvasItem, origin: Vector2, lines: Array, grow: float, glow: float) -> void:
	for pass_i in 2:
		for pts: PackedVector2Array in lines:
			var total: float = float(pts.size() - 1) * clampf(grow, 0.0, 1.0)
			for j in pts.size() - 1:
				var part: float = clampf(total - j, 0.0, 1.0)
				if part <= 0.0:
					break
				var a: Vector2 = (origin + pts[j]).round()
				var b: Vector2 = (origin + pts[j].lerp(pts[j + 1], part)).round()
				var w: float = 3.0 if j == 0 else (2.0 if j < 3 else 1.0)
				if pass_i == 0:
					# The split itself, and the glow spilling out of it.
					ci.draw_line(a, b, Color("0a0612"), w + 2.0)
					if glow > 0.0:
						ci.draw_line(a, b, Color(Pix.VIOLET, glow * 0.45), w + 4.0)
				elif glow > 0.0:
					ci.draw_line(a, b, Color(Pix.VIOLET_LIGHT, minf(1.0, glow * 1.2)), maxf(1.0, w - 1.0))


# Shafts of light standing up out of the split ground at `origin`.
static func draw_light(ci: CanvasItem, origin: Vector2, crack_seed: int, grow: float, glow: float, big: bool) -> void:
	if glow <= 0.0 or grow <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed + 77
	var n: int = 9 if big else 6
	var spread: float = 44.0 if big else 30.0
	for i in n:
		var x: float = rng.randf_range(-spread, spread) * clampf(grow * 1.3, 0.0, 1.0)
		var hgt: float = rng.randf_range(26.0, 64.0) * (1.6 if big else 1.0) * grow
		var w: float = float(1 + rng.randi() % 3)
		var flick: float = 0.75 + 0.25 * sin(grow * 40.0 + i * 1.7)
		for k in 4:
			var y0: float = -hgt * k / 4.0
			ci.draw_rect(Rect2(Vector2(origin.x + x - w * 0.5, origin.y + y0 - hgt / 4.0).round(), Vector2(w, ceil(hgt / 4.0))),
				Color(Pix.VIOLET_LIGHT, glow * flick * [0.5, 0.32, 0.18, 0.08][k]))


func init():
	next_slam = 2.2 + randf() * 2.2
	invulnerable = true
	_cracks = crack_lines(crack_seed, great)
	_burst_flash = 1.0
	# Rock thrown up by the break, and a column of dust.
	var n: int = 60 if great else 38
	for i in n:
		var up: float = randf_range(140.0, 400.0) * (1.25 if great else 1.0)
		debris.append({"p": Vector2(randf_range(-12, 12), -2.0), "v": Vector2(randf_range(-170, 170), -up), "s": float(2 + randi() % 5),
			"col": EARTH[randi() % EARTH.size()], "life": randf_range(2.5, 5.0), "rest": false})
	for i in 14:
		debris.append({"p": Vector2(randf_range(-16, 16), -2.0), "v": Vector2(randf_range(-40, 40), randf_range(-90, -30)), "s": float(3 + randi() % 3),
			"col": Color(0.42, 0.36, 0.47, 0.5), "life": randf_range(0.6, 1.3), "rest": false, "dust": true})
	Sfx.play("grow", -3.0, 0.7 if great else randf_range(0.9, 1.2))
	Sfx.play("boom", -4.0 if great else -8.0, 0.8 if great else randf_range(1.0, 1.3))
	InputSystem.shake(30.0 if great else 16.0, 0.8 if great else 0.5, 20.0, global_position)


static func _back_out(x: float) -> float:
	var c1: float = 2.6
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _update_debris(delta: float) -> void:
	_burst_flash = maxf(0.0, _burst_flash - delta * 3.5)
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		d["life"] -= delta
		if d["life"] <= 0.0:
			debris.remove_at(i)
			continue
		if d["rest"]:
			continue
		if d.get("dust", false):
			d["v"] *= 1.0 - delta * 1.5
			d["p"] += d["v"] * delta
			continue
		d["v"].y += 620.0 * delta
		d["p"] += d["v"] * delta
		if d["p"].y >= 0.0 and d["v"].y > 0.0:
			d["p"].y = 0.0
			if d["v"].y > 120.0:
				d["v"] = Vector2(d["v"].x * 0.5, -d["v"].y * 0.3)   # one bounce
			else:
				d["rest"] = true


# ---------------------------------------------------------------- behaviour

func _slam_bend() -> float:
	# 0 upright .. 1 bent onto the dome; negative while rearing back.
	if slam_t < 0.0:
		return 0.0
	if slam_t < SLAM_TELE:
		return -0.35 * sin(slam_t / SLAM_TELE * PI * 0.5)
	var t: float = slam_t - SLAM_TELE
	if t < SLAM_STRIKE:
		return lerpf(-0.35, 1.0, t / SLAM_STRIKE)
	t -= SLAM_STRIKE
	if t < SLAM_HOLD:
		return 1.0
	t -= SLAM_HOLD
	return maxf(0.0, 1.0 - t / SLAM_BACK)


# The tip, in this node's space.
func tip() -> Vector2:
	var h: float = height * emerge * (1.0 - sink)
	var bend: float = _slam_bend()
	var sway: float = sin(time * 1.3 + seed_f) * 9.0
	var reach: float = absf(_dome_gap()) - 26.0
	var x: float = sway + dome_dir * reach * maxf(bend, 0.0) + dome_dir * 30.0 * minf(bend, 0.0)
	var y: float = -h * (1.0 - 0.62 * maxf(bend, 0.0))
	if flinch > 0.0:
		x -= dome_dir * 14.0 * flinch
	return Vector2(x, y)


func _dome_gap() -> float:
	var dome = Level.getDome(teamId)
	return (dome.global_position.x - global_position.x) if dome != null else dome_dir * 150.0


func _dome_top() -> Vector2:
	var dome = Level.getDome(teamId)
	if dome == null:
		return Vector2(dome_dir * 150.0, -40.0)
	return to_local(dome.getCupolaClosestPos(to_global(tip()), teamId))


func subProcess(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	flinch = maxf(0.0, flinch - delta * 1.2)
	_update_debris(delta)
	if emerge_t < EMERGE_TIME:
		emerge_t += delta
		emerge = _back_out(clampf(emerge_t / EMERGE_TIME, 0.0, 1.0))
		if emerge_t >= EMERGE_TIME:
			emerge = 1.0
			invulnerable = false
	elif slam_t >= 0.0:
		slam_t += delta
		if slam_t >= SLAM_TELE + SLAM_STRIKE and not _did_hit:
			_did_hit = true
			_hit_dome()
		if slam_t >= SLAM_TELE + SLAM_STRIKE + SLAM_HOLD + SLAM_BACK:
			slam_t = -1.0
			next_slam = Boss.FINALE_SLAM_EVERY * randf_range(0.8, 1.25) * fury
	elif gaze_t >= 0.0:
		_update_gaze(delta)
	else:
		next_slam -= delta
		if next_slam <= 0.0:
			attacks_done += 1
			_did_hit = false
			if great and attacks_done % 2 == 0:
				gaze_t = 0.0
				gaze_hp = currentHealth
				Sfx.play("charge", -2.0, 0.6)
			else:
				slam_t = 0.0
	if _hitbox != null:
		var t: Vector2 = tip()
		_hitbox.position = Vector2(t.x * 0.5, t.y * 0.5)
	queue_redraw()


# How much of the damage that breaks the gaze has been dealt (0..1).
func gaze_broken_share() -> float:
	return clampf((gaze_hp - currentHealth) / (maxHealth * Boss.FINALE_GAZE_BREAK), 0.0, 1.0)


func _update_gaze(delta: float) -> void:
	gaze_t += delta
	if gaze_t < Boss.FINALE_GAZE_CHARGE:
		if gaze_broken_share() >= 1.0:
			# Hurt enough: it flinches and the shot is lost.
			gaze_t = -1.0
			gazes_broken += 1
			flinch = 1.0
			flash = 0.3
			next_slam = Boss.FINALE_SLAM_EVERY * 0.9 * fury
			Sfx.play("hurt", 0.0, 0.7)
			InputSystem.shake(18.0, 0.4, 22.0, global_position)
		return
	if not _did_hit:
		_did_hit = true
		gazes_fired += 1
		var dome = Level.getDome(teamId)
		if dome != null and multiplayer.is_server():
			dome.requestMeleeDamage(int(Boss.FINALE_GAZE_DAMAGE), to_global(_dome_top()), self)
		InputSystem.shake(34.0, 0.7, 26.0)
		Sfx.play("beam", 2.0, 0.6)
	if gaze_t >= Boss.FINALE_GAZE_CHARGE + GAZE_FIRE:
		gaze_t = -1.0
		next_slam = Boss.FINALE_SLAM_EVERY * randf_range(0.8, 1.1) * fury


func _hit_dome() -> void:
	var dome = Level.getDome(teamId)
	if dome == null or not multiplayer.is_server():
		return
	slams += 1
	var dmg: int = int(Boss.FINALE_SLAM_DAMAGE * (2.0 if great else 1.0))
	dome.requestMeleeDamage(dmg, to_global(tip()), self)
	InputSystem.shake(26.0 if great else 16.0, 0.4, 20.0, global_position)
	Sfx.play("whip", -2.0, 0.7 if great else 1.0)


func handleDamage():
	flash = 0.1


func animateDeath():
	Sfx.play("die" if great else "pop", -2.0, 0.8 if great else randf_range(0.8, 1.1))
	InputSystem.shake(24.0 if great else 12.0, 0.6, 18.0, global_position)
	slam_t = -1.0
	gaze_t = -1.0
	var tw := create_tween()
	if great:
		# The great eye slumps to the ground and lies there, for the surface
		# monsters to finish.
		tw.tween_property(self, "sink", 0.8, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	# Its eye tears free.
	eye_freed.emit(to_global(tip()))
	tw.tween_property(self, "sink", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): remainingFreeBlockers = 0)


func _process(_delta: float) -> void:
	if dead:
		time += _delta
		_update_debris(_delta)
		queue_redraw()


func leave(_delta: float):
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# The broken ground stays, even once the tentacle is gone.
	var after: float = clampf(1.0 - emerge_t / 2.2, 0.0, 1.0) if not dead else 0.0
	draw_cracks(self, Vector2.ZERO, _cracks, 1.0, after)
	draw_light(self, Vector2.ZERO, crack_seed, 1.0, after * after, great)
	for i in 7:
		var rx: float = (i - 3) * 6.0 + sin(seed_f + i) * 2.0
		Pix.disc(self, Vector2(rx, -1.0 - absf(sin(seed_f * 3.0 + i)) * 3.0), 3.0 + (i % 2), EARTH[i % EARTH.size()])
	if emerge > 0.01 and sink < 0.99:
		_draw_body()
	for d: Dictionary in debris:
		var a: float = clampf(d["life"] * 1.5, 0.0, 1.0) * d["col"].a
		draw_rect(Rect2((d["p"] - Vector2(d["s"], d["s"]) * 0.5).round(), Vector2(d["s"], d["s"])), Color(d["col"], a))
	if _burst_flash > 0.0:
		var r: float = (26.0 if great else 18.0) * (1.6 - _burst_flash * 0.6)
		Pix.ellipse(self, Vector2(0, -2), r * 1.8, r * 0.7, Color(Pix.VIOLET_LIGHT, _burst_flash * 0.8), -1.0, 0.2)
		# A column of light where it came through.
		var cw: float = (22.0 if great else 14.0) * _burst_flash
		var chh: float = 170.0 if great else 120.0
		draw_rect(Rect2(Vector2(-cw, -chh).round(), Vector2(cw * 2.0, chh)), Color(Pix.VIOLET_LIGHT, _burst_flash * 0.35))
		draw_rect(Rect2(Vector2(-cw * 0.4, -chh).round(), Vector2(cw * 0.8, chh)), Color(1, 1, 1, _burst_flash * 0.6))
		# The shock runs out along the ground both ways.
		var run: float = (1.0 - _burst_flash) * 70.0
		draw_rect(Rect2(Vector2(-run - 10.0, -1).round(), Vector2(10, 2)), Color(Pix.SCLERA, _burst_flash))
		draw_rect(Rect2(Vector2(run, -1).round(), Vector2(10, 2)), Color(Pix.SCLERA, _burst_flash))


func _draw_body() -> void:
	var t: Vector2 = tip()
	var bend: float = _slam_bend()
	var col: Color = Pix.FLESH_MID
	if flash > 0.0:
		col = Color.WHITE
	elif dead:
		col = Color("231a30")
	var pts: PackedVector2Array = Pix.tentacle_points(Vector2.ZERO, t, time, 7.0 * (1.0 - absf(bend) * 0.6), seed_f, 1.0, -dome_dir * 16.0 * (1.0 - maxf(bend, 0.0)) + dome_dir * 34.0 * maxf(bend, 0.0))
	var w0: float = 13.0 if great else 9.0
	var tipp: Vector2 = Pix.tentacle(self, pts, w0, 6.0 if great else 3.5, col)
	var look: Vector2 = Vector2(_dome_gap(), -30.0)
	var n: int = pts.size()
	if not dead:
		for j in range(6, n - 6, 9):
			Pix.eye(self, pts[j], Pix.eye_frame_toward(pts[j], look, time, j * 0.3 + seed_f), 0.5)
	if great:
		_draw_great(tipp, look)
	elif dead:
		# A torn stump: the eye has gone.
		Pix.disc(self, tipp, 5.0, Pix.EDGE)
		Pix.disc(self, tipp, 3.0, Pix.IRIS_DEEP)
	else:
		Pix.disc(self, tipp, 9.0, Pix.EDGE)
		Pix.eye(self, tipp, Pix.eye_frame_toward(tipp, look, time, seed_f), 1.0, Color.WHITE if flash <= 0.0 else Color(3, 3, 3))
	# The slam's warning: the tip glows red while it rears back.
	if slam_t >= 0.0 and slam_t < SLAM_TELE:
		var f: float = slam_t / SLAM_TELE
		var blink: float = 0.4 + 0.6 * absf(sin(slam_t * (10.0 + 16.0 * f)))
		draw_arc(tipp, 13.0 + 4.0 * (1.0 - f), 0.0, TAU, 20, Color(Pix.WARN, blink), 2.0)
	if great and gaze_t >= 0.0:
		_draw_gaze(tipp)


func _draw_gaze(c: Vector2) -> void:
	var target: Vector2 = _dome_top()
	if gaze_t < Boss.FINALE_GAZE_CHARGE:
		var f: float = gaze_t / Boss.FINALE_GAZE_CHARGE
		# Light gathers into the eye.
		for i in 3:
			var r: float = 46.0 - fposmod(time * 40.0 + i * 15.0, 46.0)
			draw_arc(c, 24.0 + r, 0.0, TAU, 28, Color(Pix.IRIS, 0.5 * (1.0 - r / 46.0) + 0.1), 1.0)
		var blink: float = 0.4 + 0.6 * absf(sin(gaze_t * (6.0 + 22.0 * f)))
		draw_line(c, target, Color(Pix.WARN, 0.10 + 0.25 * f), 8.0 * f + 2.0)
		draw_line(c, target, Color(Pix.WARN, blink), 1.0)
		# How close the dome's fire is to breaking it: a ring that burns away.
		var left: float = 1.0 - gaze_broken_share()
		draw_arc(c, 30.0, -PI * 0.5, -PI * 0.5 + TAU * left, 40, Color(Pix.SCLERA, 0.9), 3.0)
		draw_arc(c, 30.0, -PI * 0.5 + TAU * left, -PI * 0.5 + TAU, 40, Color(Pix.EDGE, 0.6), 3.0)
	else:
		var f2: float = 1.0 - (gaze_t - Boss.FINALE_GAZE_CHARGE) / GAZE_FIRE
		draw_line(c, target, Color(Pix.IRIS_DEEP, 0.8), 20.0 * f2 + 4.0)
		draw_line(c, target, Color(Pix.IRIS, 1.0), 13.0 * f2 + 2.0)
		draw_line(c, target, Color.WHITE, 5.0 * f2 + 1.0)
		Pix.disc(self, target, 14.0 * f2 + 4.0, Color(1, 1, 1, 0.8 * f2))


func _draw_great(c: Vector2, look: Vector2) -> void:
	Pix.ellipse(self, c, 22, 18, Pix.EDGE)
	Pix.ellipse(self, c, 20, 16, Pix.FLESH_LIGHT if not dead else Color("2c2238"))
	if dead:
		draw_rect(Rect2((c + Vector2(-15, 0)).round(), Vector2(30, 2)), Pix.EDGE)
		return
	var squint: float = 1.0 - 0.7 * flinch
	Pix.ellipse(self, c, 17, 13 * squint, Pix.SCLERA if flash <= 0.0 else Color.WHITE)
	var ic: Vector2 = c + (look - c).limit_length(80.0) / 80.0 * Vector2(6, 3)
	var charging: bool = gaze_t >= 0.0
	Pix.ellipse(self, ic, 9, 9 * squint, Pix.IRIS_DEEP if not charging else Pix.WARN)
	Pix.ellipse(self, ic, 7, 7 * squint, Pix.IRIS if not charging or fposmod(time * 10.0, 1.0) < 0.5 else Color.WHITE)
	draw_rect(Rect2((ic + Vector2(-1, -7 * squint)).round(), Vector2(3, 14 * squint)), Pix.PUPIL)
	draw_rect(Rect2((ic + Vector2(-4, -5 * squint)).round(), Vector2(2, 2)), Color.WHITE)
