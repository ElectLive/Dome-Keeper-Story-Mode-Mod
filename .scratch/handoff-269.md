# Handoff: #269 domes, #270 drone cargo, #272 old scenarios

Worktree `wt-mp-242`. Stacked branches: `ticket/269-story-domes` (PR #276, base #275), `ticket/270-drone-cargo` (PR #277), `ticket/272-old-scenarios` (in progress).

## #269 done (PR #276)
- Loadout offers dome1-4 (vanilla's `Data.loadoutDomes`). dome5 not offered: unreleased in vanilla, `ShieldBattery.gd:95` errors every frame with the shield, no icon, no health tree.
- Prices in `data/prices.gd` (block after `domesupplementresurrection2`). `dev/boss_dev.gd` has DOME_GEAR.
- t269_dome2/3/4 PASS, t269_mp_dome pair PASS, t28_loadout updated and PASS.
- log_scan allowlist: vanilla dome swap, WASAPI.
- t162_finale with `--dome=dome3` plays through; its laser-aim bot fails "kills it".

## #270 done (PR #277)
- TransportDrone + Squidley extensions, util/carry_art.gd. t270_drone_cargo PASS, t252 PASS.

## #272 todo
- t26_wired / t99_story beat order; t116_seed_reload; t47_water_lava; delete stale list; t200_dev_key without --gas.
- Then regressions: t11_money, t13_bronze, t41_save, t44_heat_shield, t160_boss_fight, t162_finale, t252_class_names, t231_split_keeper2, t223, t232 save/load, t265_mp_heat pair.
