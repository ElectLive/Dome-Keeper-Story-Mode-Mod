# Handoff: #230 boss sequence for a team (slice 1: Velle's chamber fight)

Written by the parent session from the paused Fable agent's work (it stopped at a usage limit without a note). Branch `ticket/230-mp-boss-fight`, WIP commit `1372ad3` on top of `ticket/227-mp-lava`.

## Design (in the WIP)

- Host keeps authority over the sequence, state and hearts. `boss/boss_director.gd`:
  - The fight starts when **any** keeper is in the chamber; each instance seals in its own keepers once they are in (`_held`, `_seal(delta)` over `Keepers.local.keepers`); a teammate outside can still come in.
  - `_net_host()`: Velle's state to clients at 15 Hz (`_net_velle`, unreliable_ordered, `velle.net_state()` → `PackedFloat32Array`), events (`_net_events`, reliable, from `velle.take_events()` with `collect_events`), a reliable "sure" state on deaths (`_net_velle_now`), hits (`_net_hurt` → `health.net_hit`), and every 2 s the state + hearts (`_net_boss`).
  - **Why `_net_boss` repeats (the "client reads state as empty" oddity, explained):** vanilla's Data sync loses a change made while a client's full Data sync is in flight: the full sync overwrites it and the change is never resent. The test `t230_mp_boss_fight_client` reproduces it ("vanilla's Data race").
  - Client side `_client_process()`: follows the state, builds the boss layer and a **puppet** Velle (`velle.puppet = true`, AI skipped, `net_apply` / `play_events`), seals its own keeper, plays fight/chase music and Velle's sfx.
  - Overheat in the fight: a client sends `_net_overheated(playerId)`; the host costs a heart (`_overheat`). `me()` = this instance's own first keeper.
  - Hearts: one shared team pool (interim design, Data `team1.story.hearts`); at zero `_team_down()` hides every keeper.
- `boss/keeper_health.gd`: hits per keeper (`hurt(from, cause, keeper)`, `set_safe`, `net_hit`, `hit` signal).
- `boss/velle.gd`: puppet mode, `net_state` / `net_apply`, event collection and replay; attacks target any keeper on the host.

## Verified (last run, 12:48 today, `mp_playtest.ps1 t230_mp_boss_fight_host t230_mp_boss_fight_client`)

All 17 host checks and 27 client checks passed, 0 script errors on either side. Highlights: the fight starts with only the client's keeper in the chamber; the host's keeper at the dome isn't pulled in; Velle hits the client's keeper (team 5 → 4 hearts, the keeper is thrown and blinks); the client's Suit Blaster pops a stalk; the client's overheat costs a heart and doesn't recall; boss state, phase, health, stalks, attacks (lunge, gaze) and the open eye match on the client; the won fight moves both to the chase; fight and chase music and Velle's sfx play on the client. Screenshots in `playtest_out/t230_mp_boss_fight_*`: the client draws Velle, its beam, stalks, boss bar and hearts like the host.

## Not done / next steps

1. **Single-player regressions** were not run on the WIP: `t160_boss_fight`, `t161_chase`, the other `t16*`/`t17*`/`t19*` boss scenarios (`ls dev/scenarios | grep -E "t1(6|7|8|9)"`), `t45_lava_death`, `t06_story_run`. Run each through `playtest_out/run_locked.ps1`. A failure that also fails on the base branch predates this work.
2. **Client's chamber background is black** (host shows the rock and the chamber; client shows only Velle on black): the chamber and the dev shaft are revealed on the host only (`_dev_boss` uses `tileCoordsToReveal` + `floodRevealTiles` and `boss_dev.carve`). In real play the client reveals what it digs, so check whether this is dev-only; at least reveal the chamber visually on a client when the fight starts.
3. Commit as `#230: Multiplayer: Velle's chamber fight for a team` (squash the WIP is not needed; add a proper commit on top), push, PR into `ticket/227-mp-lava` titled `#230 (1/3): ...`.
4. Then slice 2, **the chase** (`boss/chase.gd`: tentacles hunt `Keepers.first()`; targets, grabs and the "home" check need any keeper / every keeper), and slice 3, **the finale** (`boss/finale.gd`, `surface_tentacle.gd`, `eye_flyer.gd`, `great_eye.gd`: custom Monster nodes added with `add_child`, not through `MonsterSynchronizer`, so a client sees nothing), each as its own commit and stacked PR, same puppet + stream pattern.
5. Known single-player bug seen in the probe: #237 (`velle.gd _update_orbs` index error when the keeper dies mid-fight).

## Commands

- Online: `& "<worktree>\mods-unpacked\cejdan-StoryMode\dev\mp_playtest.ps1" t230_mp_boss_fight_host t230_mp_boss_fight_client` (takes the machine-wide playtest lock).
- Single player: `& "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\playtest_out\run_locked.ps1" "<worktree>\mods-unpacked\cejdan-StoryMode\dev\playtest.ps1" <scenario>`.
- Output: `C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\playtest_out\<scenario>\`.
