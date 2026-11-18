extends RefCounted

# The boss sequence's numbers (#160-#163): Velle's chamber fight, the chase
# back to the dome and the surface finale. Feel and balance are the user's to
# tune; everything is here in one place.

# --- keeper health (#160) ----------------------------------------------------
const HEARTS := 5
const HURT_INVULNERABLE := 1.2       # seconds safe after a hit
const HURT_KNOCKBACK := 46.0         # px the keeper is thrown
const OVERHEAT_HEAT_AFTER := 0.55    # heat (share of max) left after an overheat hit

# --- the chamber fight (#160, second pass #169) -------------------------------
const CORE_HP := 30.0
# Velle's health at which phase 2 and phase 3 begin. Once every eye stalk is
# popped the great eye opens and stays open until its health crosses the next
# of these (or reaches 0): there is no timer.
const PHASE_AT := [20.0, 10.0]
# An open eye fights back with its gaze. Seconds between its volleys when it
# has just opened, per phase; each second it stays open shortens that by
# OPEN_RAGE_PER_S (a share), down to OPEN_BEAM_FASTEST.
const OPEN_BEAM_EVERY := [3.2, 2.6, 2.2]
const OPEN_BEAM_FASTEST := 0.9
const OPEN_RAGE_PER_S := 0.03
const STALKS := [2, 3, 4]             # eye stalks per phase
const STALK_HP := 2.0
const STALK_FIRE_EVERY := [3.6, 3.2, 2.8]
# The share of a stalk's shots that are thin lasers instead of orbs.
const STALK_LASER_SHARE := [0.0, 0.5, 0.8]
const ORB_SPEED := [52.0, 60.0, 68.0]
const ATTACK_EVERY := [3.8, 3.0, 2.4]
const DAMAGE := {
	"bomb": {"stalk": 3.0, "core": 5.0, "radius": 56.0},
	"mine": {"stalk": 3.0, "core": 5.0, "radius": 56.0},
	"blast": {"stalk": 2.0, "core": 3.0, "radius": 0.0},   # radius from the suit's own
}
# Old mining charges shake loose from the roof: one every few seconds (faster
# while the eye is open), up to a cap; one more for every stalk popped, and
# BOMBS_ON_OPEN at once when the eye opens.
const BOMB_EVERY := 3.0
const BOMB_EVERY_OPEN := 2.2
const BOMB_CAP := 5
const BOMBS_ON_OPEN := 2
# Each new phase shakes a heart loose; it waits this long to be picked up.
const HEART_ON_PHASE := true
const HEART_SECONDS := 25.0
# The Suit Blaster recharges this fast in the chamber (seconds per charge).
const BLASTER_RECHARGE := 12.0

# --- the chase (#161) --------------------------------------------------------
const CHASE_TENTACLES := 3
# Tentacle speed as a share of the keeper's own top speed: when right behind
# the keeper, at a middle distance, and when far behind (rubber band).
const CHASE_SPEED_NEAR := 0.86
const CHASE_SPEED_MID := 1.0
const CHASE_SPEED_FAR := 1.6
const CHASE_NEAR_PX := 60.0
const CHASE_FAR_PX := 320.0
const CHASE_HEAD_START := 2.5        # seconds before the tentacles set off
const CHASE_RECOIL := 1.3            # seconds a tip hangs back after it lands a hit

# --- the surface finale (#162, second pass #171) ------------------------------
# Tuned for a dome with about Laser III (110 damage a second); a base laser
# (15) cannot win. Health is fixed, not scaled to the run: by now every run
# has had the same chance to gear up.
const FINALE_TENTACLE_HP := 420.0
const FINALE_EYE_HP := 1500.0          # Velle's great eye, in the last round
const FINALE_FLYER_HP := 120.0         # an eye that tore free of a tentacle
# A tentacle comes up with this many eyes; one tears free and becomes a flyer
# every FINALE_EYE_POP_EVERY seconds, until it has none left or is dead (#173).
const FINALE_TENTACLE_EYES := 4
const FINALE_EYE_POP_EVERY := 5.0
# The great eye hangs this many px above the dome's foot. Its stalk is drawn
# on this layer (absolute z), behind the dome.
const FINALE_EYE_HEIGHT := 132.0
const FINALE_STALK_Z := 1
const FINALE_SLAM_DAMAGE := 30         # to the dome; the great eye hits twice as hard
const FINALE_SLAM_EVERY := 5.5
const FINALE_FLYER_DAMAGE := 10        # one bolt
const FINALE_FLYER_EVERY := 3.4
# The great eye's gaze: it charges this long, then burns the dome, unless it
# loses GAZE_BREAK of its full health while charging (then it flinches).
const FINALE_GAZE_CHARGE := 3.0
const FINALE_GAZE_DAMAGE := 140
const FINALE_GAZE_BREAK := 0.14
# Fury: every second of the battle shortens all their waits by this share,
# down to FURY_FLOOR of the listed times. A slow dome is buried.
const FINALE_FURY_PER_S := 0.004
const FINALE_FURY_FLOOR := 0.45
