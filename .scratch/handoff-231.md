# Handoff #231: local splitscreen (every local keeper)

Branch `ticket/231-mp-splitscreen` (worktree wt-mp-242), stacked on #251's PR #260. WIP commits pushed.

## Vanilla splitscreen (findings)
- Title Splitscreen button sets `Network.multiplayer_mode = OFFLINE_SPLITSCREEN` and opens the loadout; each device that presses a key joins (`MultiplayerLoadoutInputProcessor.new_device_detected` -> `addNewDevice`). Online, `Options.enableSplitScreen` does the same on one instance.
- Gamepad device index = joypad device + 1; gamepad keepers walk with the left stick.
- `stages/level/Viewports.gd`: one `ViewportContainer` per local keeper: world SubViewport (shared World2D) + UI SubViewport with that player's `PlayerCanvas` (vanilla HUD per view).
- Per-view drawing: world SubViewport `canvas_cull_mask` = bit 0 + the keeper's bit; `Level.viewports.showForLocalKeeper(k, item)`. A CanvasLayer under the map shows in the first view only; `custom_viewport` errors on level teardown.
- 2+ keepers: dome gets a secondary station; its laser is the shop's Second Weapon (domesecondweapon, behind Sand Repair).

## Done
- Per local keeper: heat, passive heat, recall spot + recall, heat bar, toxin, fire heat, toxin bar, vignette (world rect in its view), muffle = worst keeper, gas look per view, heat lines, depth watch (all keepers), boss: overheated(keeper), hearts over each local keeper, hit flash per view, chamber camera per keeper.
- Lava late on P2: lava drew only cells in the first viewport's rect; now the union of every split view (chains, pleas too). Dev `single_view_cull` / `--oldcull` shows the old bug.
- Aux laser: station 2 had no laser until Second Weapon was bought. The free grant (Storymode._second_laser) was dropped later at the user's call: Second Weapon stays vanilla's shop upgrade.
- Vanilla run after a Story run in the same loadout got Story lava/gas (stale MODE_FLAG in modeConfig): mod_main.prepareGameMode erases it.
- Black screen on restart: not reproduced (pause-menu restart single/split +- welcome log, lose -> Another Run split/single/vanilla, title path, 1920x1080). User's log 2026-11-17 08:05 ends at "Start Stage: loadout" after a lost splitscreen run (main build).

## Scenarios
t231_split_probe, t231_split_keeper2, t231_split_laser, t231_split_lava (+ --oldcull), t231_restart / t231_split_restart (+ --welcome), t231_split_again (+ --single), t231_title_again (+ --single / --vanilla), t231_mp_split_host/client.

## Known
- KeeperCamera.updateCameraRestPosition script error, sometimes, when the loadout reopens with lobby members (Another Run in splitscreen): Level.domesByTeamId empty when a keeper camera inits. Vanilla code ordering; not allowlisted.

## Status
- Done: PR #262 (base ticket/251-mp-client-clients). Regressions pass (t26_wired as on #255). log_scan allowlists vanilla's loadout-reopen camera error (seen in Relic Hunt twice).
