extends "res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t196_finale_breath.gd"

# Ticket 196: the keeper sits at the console and leaves its menu alone. After
# the breath the menu takes Battle by itself, so the bells ring over a running
# world with the keeper at the weapon.


func run(h) -> void:
	var boss = await start(h)
	var fin = boss.finale
	var m = boss.music
	var k = h.keeper()
	var st = _station(Level.getDome("team1"))
	st.useHit(k)
	await h.until(func(): return fin.activity() == "console", 3.0)
	var b0: float = h.now()
	await h.wait(1.0)
	await h.shot("idle_at_the_console")
	h.check("the breath while the menu is open", fin.step == "breath" and GameWorld.paused, [fin.step, GameWorld.paused])
	await h.until(func(): return fin.step == "rumble", Boss.FINALE_BREATH + 3.0)
	var took: float = snappedf(h.now() - b0, 0.01)
	h.check("after %.0f s idle the bells start" % Boss.FINALE_BREATH, fin.step == "rumble" and fin.bells_by == "console" and took >= Boss.FINALE_BREATH - 0.2 and took < Boss.FINALE_BREATH + 0.6, [fin.bells_by, took])
	await h.wait(0.5)
	h.check("the menu took Battle: at the weapon, the world running", fin.activity() == "battle" and not GameWorld.paused and k.isInsideStation, [fin.activity(), GameWorld.paused])
	h.check("the bell intro plays", m.intro_time() >= 0.0, m.playing())
	await h.shot("bells_at_the_weapon")
