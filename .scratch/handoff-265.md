# Handoff #265: Heat Shielding per keeper

Branch `ticket/265-heat-shield-per-keeper` in `wt-mp-242`, stacked on `ticket/263-split-views` (PR #266).

## Vanilla (read)
- `GameWorld.prepareLevelStart`: per-player limits `<playerId>.mining` / `.carry`; team limits per dome.
- Keeper root `keeper1` is added per player (`LevelKeeperSpawner`: `addUpgrade(keeperId, playerId)`), so
  `makeInstancedUpgrade(.., "player1")` prefixes id, limits, predecessors and property keys
  (`player1.keeper1.drillStrength`); `updateAvailableUpgrades("player1")` then makes `player1.drill1`
  (limit `player1.mining`, predecessor `player1.keeper1`). The team instance `team1.drill1` never appears.
- `TechTree.calculateTracks` shows `team1.<id>` or `<playerId>.<id>`: each player's own keeper track
  ("These upgrades apply only to your keeper.").
- Keepersuit gadget picked in a run (`LevelStage.addGadgetUpgrade`): `<playerId>.suitblaster`, the picker only
  ("keeper exclusive gadget"); loadout keepersuit gadgets go to every keeper; team props applied once.

## Done
- yaml: storyHeatShield1 + storySuitblaster `limit: [storykeeper]`, `predecessors: [keeper1]`
- mod_main.prepareGameMode: `<playerId>.storykeeper` per Story keeper (gamemode/keeper_upgrades.gd)
- LavaData.shield_tier(keeper|playerId|null), readers pass the keeper (lava_field, gas fire, heat_talk)
- Storymode: blaster entry grants the buyer only; savegame_loaded -> KeeperUpgrades.after_load (limits, old-save
  migration: team tier -> every keeper, team entries dropped, own blaster entry marked bought)
- story_net resend: `<playerId>.suit.*`
- boss dev gear: every keeper's gear incl. Heat Shielding IV + blaster
- harness.buy(id, k): keeper's own prefix
- scenarios: t265_split_heat PASS, t265_mp_heat pair PASS, t265_old_save/old_load (+ --reload) PASS,
  t265_mp_oldsave pair + `t232_mp_load_* -Extra "--slot=32 --notes=user://t265_saved.json"` PASS, t44 PASS

## Left
- regressions (scratchpad regress.ps1), PR
