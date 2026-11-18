# Handoff #261 / #263 / free second laser

Worktree wt-mp-242.

## #261 (done) — PR #264, branch `ticket/261-mp-gadget-data-order` (base `ticket/231-mp-splitscreen`)
- `net/ordered_chunker.gd` `_send_split`: a small delta to a peer with queued Data sends at once the keys no queued message to that peer holds; the rest waits behind. With a full sync queued, new keys go at once and the whole delta also waits behind it. `--heldchunker` restores #246's hold-whole.
- t253: `--give=<gadget>` (probe); client checks gadget keys present at upgradeAdded, and Suit Blaster `stand_ins == 0`. Fallback kept as insurance.
- Evidence: bigdelta shop/vanilla/devgear/probe, early probe/vanilla PASS; heldchunker probe/vanilla FAIL as expected; t242, t246 PASS.

## #263 — branch `ticket/263-split-views` (base #261 branch)
- boss/chase.gd: edge mark per local keeper (child Node2D per keeper, showForLocalKeeper); single keeper unchanged. `gap_for(k)`.
- pleas/plea_director.gd: in splitscreen, per keeper away from the dome an on-screen line in its view (pin Node2D on its camera, scale 1/zoom, `_place_pins`); `where` "world"/"screen"/"both", `views`.
- extensions/systems/camera/KeeperCamera.gd: waits for the dome instead of erroring; installer EXTENSIONS/NAMED_BY/SCENES updated (t252 PASS); log_scan allowlist entry removed. t231_title_again --vanilla x2 + split: deferral logged twice, no error.
- Scenarios: t263_split_pleas, t263_split_chase PASS (screenshots checked).

## Free second laser (user, via coordinator) — commit 161683c (#231:) on the #263 branch
- Removed Storymode._second_laser; t231_split_laser buys Health Meter -> Second Weapon (sand 35 / water 62 cells on map): PASS. t231_restart checks no free laser. PR #262 body has a note.
- Commit message has "\ + 10 water" (PowerShell ate "$280"); left as is (no history rewrite).

## Regressions (tip of #263 branch): all PASS
t231_split_keeper2/laser/lava, t161_chase, t91_pleas, t252, t231_title_again; online t231_mp_split, t223, t225, t228, t229_mp_story, t230_mp_boss_fight, t242, t246, t251 save+load, t253 bigdelta (+probe).

## Status
- Done. PRs #264 (#261) and the #263 PR (base ticket/261-mp-gadget-data-order).
