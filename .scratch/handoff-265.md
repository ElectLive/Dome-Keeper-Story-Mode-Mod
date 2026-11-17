# Handoff #265: Heat Shielding per keeper

Branch `ticket/265-heat-shield-per-keeper` in `wt-mp-242`, stacked on `ticket/263-split-views` (PR #266).

## Vanilla (read)
- `GameWorld.prepareLevelStart`: per-player limits `<playerId>.mining` / `.carry`; team limits per dome.
- Keeper root `keeper1` is added per player (`LevelKeeperSpawner`: `addUpgrade(keeperId, playerId)`), so
  `makeInstancedUpgrade(.., "player1")` prefixes id, limits, predecessors and property keys
  (`player1.keeper1.drillStrength`); `updateAvailableUpgrades("player1")` then makes `player1.drill1`
  (limit `player1.mining`, predecessor `player1.keeper1`). The team instance `team1.drill1` never appears
  (its predecessor `team1.keeper1` doesn't exist).
- `TechTree.calculateTracks` shows `team1.<id>` or `<playerId>.<id>`: each player's own keeper track.
- Keepersuit gadget picked in a run (`LevelStage.addGadgetUpgrade`): `<playerId>.suitblaster`, the picker only
  ("keeper exclusive gadget"); loadout keepersuit gadgets go to every keeper; team props applied once.

## Plan / status
- [ ] yaml: storyHeatShield1 + storySuitblaster `limit: [storykeeper]`, `predecessors: [keeper1]`
- [ ] mod_main.prepareGameMode: `<playerId>.storykeeper` for each Story keeper
- [ ] LavaData.shield_tier(keeper|playerId), readers pass the keeper
- [ ] Storymode: blaster to the buyer; load: limits + old-save migration (team tier -> every keeper)
- [ ] story_net resend: player suit keys
- [ ] boss dev gear: every keeper tier 4
- [ ] harness.buy: keeper's own prefix
- [ ] scenarios t265_*; update t44/t161/t229/t230/t237/mp_scenario/t22/t253
- [ ] regressions, PR
