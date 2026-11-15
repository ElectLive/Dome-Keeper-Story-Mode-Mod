extends RefCounted

# Shared noxious gas numbers for the user to tune (#198). gas/gas_field.gd and
# the map generator read them. All are starting values.

# --- hidden pockets ------------------------------------------------------------
# Gas rock inside plain rock, from biome index POCKET_START_BIOME (1 = B2) down
# to the lava ocean's ceiling. One pocket per POCKET_ROCK_PER_POCKET[0] plain
# rock cells at the first gas biome, falling evenly to [1] at B8 (more gas
# deeper). A pocket is POCKET_SIZE cells, plus one for every POCKET_GROW_ROWS
# rows of depth.
const POCKET_START_BIOME := 1
const POCKET_LAST_BIOME := 7
const POCKET_ROCK_PER_POCKET := [260.0, 130.0]
const POCKET_SIZE := [3, 6]
const POCKET_GROW_ROWS := 40.0
const VOLUME_PER_ROCK_CELL := 3.0      # cells of gas released by one gas rock tile
const CRACK_SECONDS := 0.18            # a breached pocket bursts: each gas rock cell next to a broken one breaks this much later

# --- the gas -------------------------------------------------------------------
const TICK := 0.02                     # seconds per simulation step
const COMPRESS := 0.5                  # how much more the upper of two full cells holds
const MAX_FLOW := 1.0                  # most gas one cell passes on in one direction a step
const RISE_SHARE := 0.7                # share of the balancing flow moved up each step
const SIDE_DIVISOR := 2.4              # sideways along a ceiling: this share of the difference a step
const DRIFT_DIVISOR := 16.0            # sideways while still rising (a loose cloud widens slowly)
const MIN_FLOW := 0.002
const MIN_MASS := 0.004
const SOURCE_RATE := 0.5               # gas a breached gas rock cell lets out a step ...
const SOURCE_PRESSURE := 3.0           # ... until its own cell holds this much (the jet)
const THIN_MASS := 0.07                # gas thinner than this that has stopped moving fades ...
const DECAY_PER_SECOND := 0.12         # ... at this rate
const MIN_Y := 0                       # the mine's top row; gas there with open sky above it leaves the mine
const VENT_PER_STEP := 1.0

# --- toxin (#202) --------------------------------------------------------------
const TOXIC_MASS := 0.12               # gas this dense in the keeper's cells poisons
const DENSE_MASS := 0.8                # at this density and above the bar fills at full rate
const TOXIN_PER_SECOND := 50.0         # full rate: 2 s from clean to recall
const TOXIN_THIN_SHARE := 0.25         # share of the full rate at TOXIC_MASS
const CLEAR_PER_SECOND := 30.0         # out of the gas
const TOXIN_MAX := 100.0
const WARN_SHARE := 0.7                # the bar flashes and the screen greens past this


static func pocket_rock_per_pocket(biome: int) -> float:
	var t: float = clampf(float(biome - POCKET_START_BIOME) / float(maxi(POCKET_LAST_BIOME - POCKET_START_BIOME, 1)), 0.0, 1.0)
	return lerpf(POCKET_ROCK_PER_POCKET[0], POCKET_ROCK_PER_POCKET[1], t)


# Share of the full toxin rate in gas of this density.
static func toxin_share(density: float) -> float:
	if density < TOXIC_MASS:
		return 0.0
	return lerpf(TOXIN_THIN_SHARE, 1.0, clampf((density - TOXIC_MASS) / (DENSE_MASS - TOXIC_MASS), 0.0, 1.0))
