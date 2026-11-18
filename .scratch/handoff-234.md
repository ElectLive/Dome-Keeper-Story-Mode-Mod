# Handoff #234: online co-op end to end

Branch `ticket/234-mp-end-to-end` in `wt-mp-242`, stacked on `ticket/265-heat-shield-per-keeper` (PR #271).

## Scenarios
- `t234_mp_e2e_host` / `_client` / `_leaver` (-Client2), run:
  `mp_playtest.ps1 t234_mp_e2e_host t234_mp_e2e_client -Client2 t234_mp_e2e_leaver -Timeout 1100`
- Horror-defeated ending: `t230_mp_boss_finale_host/_client` (a run ends only once): PASS.

## Result (run 5)
- Every check passes on all three instances (89 PASS, exit 0 each). VERDICT FAIL only from the client's
  `unknown data team1.drill.drillrampup` (x3): the Mine Driller arriving before its Data, i.e. #268's symptom.
- Teleporter disconnect: vanilla `TeleporterStation.on_keeper_removed` error still logged (host x4, client x1), allowlisted.

## Fixes
- LevelStage ext: a leaving player's shop-choice mark is dropped (`on_level_keeper_removed`).
- LevelStage ext: the gadget choice opened from the shop takes the focus from the shop panel (select/arrows
  worked the shop behind it, single player too); the focus goes back to the panel on close. t132_broke PASS.
- log_scan: vanilla DomeArmor unlisten allowlisted.

## Filed
- #273 silent refusal of a stale gadget pick (both at once)
- #274 RPC to an auto-named Map/@Node2D@N/Synchronizer, seen once

## Notes for scenario authors
- A client keeper's long teleport drops what it carries on the host; the host re-picks them under the dome
  (`_bring_home`), then the client flies up through the Teleporter's cellar.
- Sand Repair can't be bought at full health (vanilla); Second Weapon only needs it to be in the shop.
