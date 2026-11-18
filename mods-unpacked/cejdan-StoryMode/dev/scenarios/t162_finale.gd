extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Tickets 162 and 171: the final battle on the surface. Starts with the keeper
# in the dome, sees the ground crack and the tentacles break out, shoots one
# with the real laser from the station with real input, sees its eye tear free
# and shoot the dome, sees a slam hurt the dome, plays all three rounds, the
# great eye's gaze (fired, and broken), and watches the monsters arrive, finish
# the horror and thank the keeper in runes. Then the saved ending starts.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const BossText = preload("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"seed": 12345}


func _station(node: Node):
	for c in node.get_children():
		if c is DomeStation:
			return c
		var s = _station(c)
		if s != null:
			return s
	return null


# Kills everything alive, flyers set free along the way included.
func _kill_all(h, fin) -> void:
	for pass_i in 12:
		var any: bool = false
		for m in fin.alive:
			if is_instance_valid(m) and not m.dead and not m.invulnerable:
				m.hit("laser", 99999.0, 0.0)
				any = true
		await h.wait(0.4)
		if not any and fin.living() == 0:
			break


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = Director.instance()
	var dome = Level.getDome("team1")
	var k = h.keeper()
	h.check("the keeper starts in the dome", k.isInsideDome)
	# Jump to the end of the chase.
	boss._ensure_layer()
	# The dome of a keeper who got this far: Laser III (the battle is tuned for it).
	load("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd").give_gear()
	await h.frames(5)
	boss._stop_waves()
	boss._set_state("finale")
	boss._start_finale()
	var started: bool = await h.until(func(): return Director.current() == "finale", 5.0)
	h.check("the finale starts", started, Director.current())
	if not started:
		return
	var fin = boss.finale
	var Tentacle = load("res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd")
	var Flyer = load("res://mods-unpacked/cejdan-StoryMode/boss/eye_flyer.gd")
	h.check("the hearts are put away: the keeper is home", not boss.health.visible)
	await h.wait(1.0)
	await h.shot("ground_cracking_early")
	await h.wait(1.2)
	await h.shot("ground_cracking_late")
	await h.until(func(): return fin.step == "round1", 6.0)
	await h.burst("breaking_out", 8, 3)
	await h.wait(1.2)
	await h.shot("round1")
	h.check("round 1: two tentacles beside the dome", fin.living() == 2, fin.living())
	h.check("they are real monster targets", fin.alive.all(func(m): return m is Monster and m.is_in_group("monster") and m.collision_layer == 128))
	h.check("the dome is at battle stations", Data.of("team1.monsters.wavepresent") == true)
	h.check("health is fixed, not scaled to the run", fin.alive.all(func(m): return m.maxHealth == Boss.FINALE_TENTACLE_HP), fin.alive.map(func(m): return m.maxHealth))
	h.check("the broken ground keeps its cracks and rubble", fin.alive.all(func(m): return m._cracks.size() >= 7 and m.debris.size() > 10))

	# ---- the real laser, real input
	var st = _station(dome)
	h.check("the dome has a weapon station", st != null)
	var left = fin.alive.filter(func(m): return m.global_position.x < dome.global_position.x)[0]
	if st != null:
		st.useHit(k)
		await h.wait(2.5)
		h.note("in station", {"keeper_in_station": k.isInsideStation, "weapons": st.getControlledWeapons().size()})
		var hurt: bool = false
		for i in 30:
			# Key-down events are edges; send them again in case the station's
			# input was not listening yet. (The first "left" also picks Battle
			# in the station's menu.)
			h.up("ui_left")
			h.up("dome1_fire")
			await h.frames(2)
			h.down("ui_left")
			h.down("dome1_fire")
			await h.wait(0.5)
			hurt = not is_instance_valid(left) or left.currentHealth < left.maxHealth
			if hurt:
				break
		await h.shot("laser_hits")
		h.check("the laser hurts a tentacle", hurt, left.currentHealth if is_instance_valid(left) else -1.0)
		var killed: bool = await h.until(func(): return not is_instance_valid(left) or left.dead, 25.0)
		h.up("ui_left")
		h.up("dome1_fire")
		await h.burst("eye_tears_free", 4, 6)
		h.check("and kills it", killed, left.currentHealth if is_instance_valid(left) else -1.0)

	# ---- its eye tears free and shoots the dome
	h.check("the dead tentacle's eye takes to the sky", fin.flyers_made == 1 and fin.flyers_alive() == 1, [fin.flyers_made, fin.flyers_alive()])
	var flyer = fin.alive.filter(func(m): return is_instance_valid(m) and m.techId == Flyer.TECH)[0]
	h.check("the flyer is a real monster target too", flyer is Monster and flyer.is_in_group("monster") and flyer.maxHealth == Boss.FINALE_FLYER_HP, flyer.maxHealth)
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead and m != flyer:
			m.next_slam = 99.0
	var hp0: float = float(Data.of("team1.dome.health"))
	var shot: bool = await h.until(func(): return flyer.hits >= 1, 12.0)
	await h.shot("flyer_over_the_dome")
	h.check("it hovers above the dome", flyer.global_position.y < dome.global_position.y - 60.0, flyer.global_position - dome.global_position)
	h.check("its bolts hurt the dome", shot and float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])

	# ---- a slam hurts the dome
	hp0 = float(Data.of("team1.dome.health"))
	var right = fin.alive.filter(func(m): return is_instance_valid(m) and not m.dead and m.techId == Tentacle.TECH)
	if not right.is_empty():
		right[0].next_slam = 0.1
		await h.wait(0.6)
		await h.shot("slam_telegraph")
		await h.wait(0.7)
		await h.burst("slam", 4, 3)
	h.check("a tentacle's slam damages the dome", float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])

	# ---- a round only ends when the flyers are dead too
	right[0].hit("laser", 99999.0, 0.0)
	await h.wait(2.5)
	h.check("with both tentacles dead the round goes on: two flyers are left", fin.step == "round1" and fin.living() == 2 and fin.flyers_alive() == 2, [fin.step, fin.living()])
	await _kill_all(h, fin)
	var lull: bool = await h.until(func(): return fin.step == "lull", 6.0)
	h.check("then the ground starts to crack again", lull, fin.step)

	# ---- round 2, round 3 with the great eye
	var r2: bool = await h.until(func(): return fin.step == "round2", 8.0)
	await h.wait(1.6)
	await h.shot("round2")
	h.check("round 2: three tentacles", r2 and fin.living() == 3, fin.living())
	await _kill_all(h, fin)
	var r3: bool = await h.until(func(): return fin.step == "round3", 12.0)
	await h.burst("great_eye_breaking_out", 6, 4)
	await h.wait(1.4)
	await h.shot("round3")
	var eye = null
	for m in fin.alive:
		if is_instance_valid(m) and m.get("great") == true:
			eye = m
	h.check("round 3: three tentacles and the great eye", r3 and fin.living() == 4 and eye != null, fin.living())
	h.check("the great eye has %d health" % Boss.FINALE_EYE_HP, eye != null and eye.maxHealth == Boss.FINALE_EYE_HP)
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead and m != eye:
			m.next_slam = 99.0

	# ---- the gaze: it burns the dome unless it is hurt enough while charging
	eye.attacks_done = 1
	eye.next_slam = 0.05
	await h.until(func(): return eye.gaze_t >= 0.0, 3.0)
	await h.wait(1.5)
	await h.shot("gaze_charging")
	hp0 = float(Data.of("team1.dome.health"))
	await h.until(func(): return eye.gazes_fired == 1, 4.0)
	await h.burst("gaze_fires", 3, 6)
	h.check("left alone, the gaze burns the dome", eye.gazes_fired == 1 and float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])
	await h.until(func(): return eye.gaze_t < 0.0, 3.0)
	eye.attacks_done = 1
	eye.next_slam = 0.05
	await h.until(func(): return eye.gaze_t >= 0.0, 3.0)
	await h.wait(1.0)
	eye.hit("laser", eye.maxHealth * Boss.FINALE_GAZE_BREAK * 0.6, 0.0)
	await h.wait(0.3)
	await h.shot("gaze_half_broken")
	h.check("some damage is not enough: it keeps charging", eye.gaze_t >= 0.0 and eye.gaze_broken_share() > 0.5 and eye.gaze_broken_share() < 1.0, eye.gaze_broken_share())
	eye.hit("laser", eye.maxHealth * Boss.FINALE_GAZE_BREAK * 0.5, 0.0)
	await h.wait(0.3)
	await h.shot("gaze_broken_flinch")
	hp0 = float(Data.of("team1.dome.health"))
	await h.wait(2.5)
	h.check("enough damage while it charges makes it flinch and lose the shot", eye.gazes_broken == 1 and eye.gazes_fired == 1 and float(Data.of("team1.dome.health")) == hp0, [eye.gazes_broken, eye.gazes_fired])

	# ---- fury
	h.note("fury", {"battle seconds": snappedf(fin.fight_t, 0.1), "waits are now this share of the listed times": snappedf(fin.fury, 0.01)})
	h.check("the longer the battle, the faster they strike", fin.fury < 1.0 and fin.alive.all(func(m): return not is_instance_valid(m) or m.dead or m.fury == fin.fury), fin.fury)
	await _kill_all(h, fin)
	await h.shot("great_eye_dying")

	# ---- the monsters come
	var came: bool = await h.until(func(): return fin.step == "allies", 8.0)
	h.check("after the final blow the surface monsters arrive", came and fin.allies.size() >= 4, fin.allies.size())
	h.check("the battle is over for the dome", Data.of("team1.monsters.wavepresent") == false)
	await h.wait(2.5)
	await h.shot("monsters_arriving")
	await h.wait(3.0)
	await h.shot("final_blows")
	await h.until(func(): return fin.step == "thanks", 6.0)
	for i in BossText.THANKS.size():
		await h.until(func(): return fin.said.size() > i, 6.0)
		await h.wait(1.2)
		await h.shot("thanks_%d" % (i + 1))
	h.check("they thank the keeper, every line", fin.said == BossText.THANKS, fin.said)
	var shown = h.get_tree().get_nodes_in_group("story-plea")
	h.note("thanks on screen", shown.map(func(n): return n.get_meta("line", "")))
	var ed = Level.mode.get_node_or_null("StoryEndings")
	var saved: bool = await h.until(func(): return ed.playing == "saved", 12.0)
	await h.wait(2.0)
	await h.shot("saved_ending")
	h.check("then the saved ending plays", saved and Director.current() == "won", [ed.playing, Director.current()])
