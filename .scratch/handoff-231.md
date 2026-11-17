# Handoff #231: local splitscreen (every local keeper)

Branch `ticket/231-mp-splitscreen` (worktree wt-mp-242), stacked on #251's PR #260.

## Vanilla splitscreen (findings)
- Title Splitscreen button sets `Network.multiplayer_mode = OFFLINE_SPLITSCREEN` and opens the loadout; each device that presses a key joins (`MultiplayerLoadoutInputProcessor.new_device_detected` -> `addNewDevice`). Online, `Options.enableSplitScreen` does the same on an instance.
- Gamepad device index = joypad device + 1. Gamepad keepers move with the left stick.
- `stages/level/Viewports.gd`: one `ViewportContainer` per local keeper, each a world SubViewport (shared World2D) plus a UI SubViewport with that player's `PlayerCanvas` (HUD).
- Per-view visibility: world SubViewport `canvas_cull_mask` = bit 0 + the keeper's bit; `Level.viewports.showForLocalKeeper(k, item)`. A CanvasLayer under the map shows only in the first view; set `custom_viewport` to the keeper's `ViewportContainer.viewport`.
- With 2+ keepers vanilla adds the dome's secondary station; its laser is the shop's Second Weapon (domesecondweapon, behind Sand Repair).

## Done (committed + pushed as WIP)
- Dev boot `splitscreen: true` (loadout; with `nethost` sets Options.enableSplitScreen). Harness: `join_device`, `pad`, `pad_press`, `pad_stick`, `local_keepers`, `teleport_tile(c, k)`, `snap_camera(k)`.
- `Story.local_keepers()`, `Story.view_rects()`, `Story.on_any_view()`.
- Per local keeper: lava heat (`heats`, `heat_of`), passive rate, recall spots, recall, heat bar; gas toxin (`toxins`, `toxin_of`), fire heat, toxin bars, vignette per view (custom_viewport), muffle by worst keeper; gas look per view; heat talk per keeper; depth watch over all keepers; boss overheated(keeper), hearts over each local keeper, hit flash per view, camera hold per keeper.
- Lava lag on P2: lava culled cells to the first viewport's rect; now the union of all split views (chains, pleas too).
- Aux laser: Story Mode gives domesecondweapon when the team has 2+ keepers (Storymode._second_laser). Before: station 2 had no laser until bought.
- Black screen on restart: NOT reproduced (pause-menu restart single/split, lose -> Another Run split). Trying with the welcome log on (`-Extra "--welcome"`).

## Scenarios
t231_split_probe, t231_split_keeper2 (PASS), t231_split_laser (PASS before free-laser change; rerun), t231_restart, t231_split_restart, t231_split_again, t231_mp_split_host/client (new, not yet run).

## To do
- Rerun laser/restart; mp pair; regressions list from brief; PR into ticket/251-mp-client-clients.
