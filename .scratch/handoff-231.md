# Handoff #231: local splitscreen (every local keeper)

Branch `ticket/231-mp-splitscreen` (worktree wt-mp-242), stacked on #251's PR #260.

## Done
- Dev boot `splitscreen: true` (+ `--loadout`): loadout in OFFLINE_SPLITSCREEN.
- Harness: `join_device(i)` (0 keyboard, 1.. gamepads), `pad`, `pad_hold`, `pad_press`, `pad_stick`, `local_keepers()`, `teleport_tile(c, k)`, `snap_camera(k)`.
- `t231_split_probe`: two devices join, Story Mode, run starts, two split views. PASS.

## Vanilla splitscreen (findings)
- Title Splitscreen button sets `Network.multiplayer_mode = OFFLINE_SPLITSCREEN` and opens the loadout; each device that presses a key joins (`MultiplayerLoadoutInputProcessor.new_device_detected` -> `addNewDevice`).
- Gamepad device index = joypad device + 1. Gamepad keepers move with the left stick (`stick_move`), not the d-pad.
- `stages/level/Viewports.gd`: one `ViewportContainer` per local keeper (`viewportContainersByKeeperId`), each with a world SubViewport (shared World2D) and a UI SubViewport holding that player's `PlayerCanvas` (HUD).
- Per-view visibility: world SubViewport `canvas_cull_mask` = bit 0 (all) + the keeper's bit (`Const.CANVAS_LAYER_BIT_*_LOCAL_PLAYER`, index in Keepers.local). `Level.viewports.hideForAllLocalPlayersExcept([k], item)` / `showForLocalKeeper`.
- A CanvasLayer added under the map renders only in the first view (originalViewport); use `custom_viewport`.

## To do (plan)
- Per-keeper heat (lava_field), toxin (gas_field), toxin_fx vignette per view, gas_look per view, heat_talk per keeper, depth watch over all keepers, boss overheated(keeper)/camera per keeper, chains/pleas view checks.
- User additions (comment on #231): P2 aux laser; lava drawn late on P2's view; restart-run black screen.
- t231_* scenarios, regressions, PR.
