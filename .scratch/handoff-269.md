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

## #272 done (branch pushed; PR body draft in scratchpad pr272.md)
- t26/t99: B4 room dig mines a gem -> first_gem early (#186); _expect reads it. t99 TIMEOUT 600. PASS.
- t116: overheat recall (#187) bumped marker; save buys Heat Shielding IV. PASS.
- t47: seed 12345 hole under shaft; _lava seals. PASS.
- stale scenarios deleted; t200 boot gas:true + dev_gas_finder Story.has_user_arg. PASS.
- Regressions all PASS: t11, t13, t41, t44, t160_boss_fight, t162_finale, t252, t231_split_keeper2, t223, t232 save/load, t265_mp_heat.
- Old list (done): t11_money, t13_bronze, t41_save, t44_heat_shield, t160_boss_fight, t162_finale, t252_class_names, t231_split_keeper2, t223, t232 save/load, t265_mp_heat pair.
