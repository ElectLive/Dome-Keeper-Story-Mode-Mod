# Handoff: #229 Multiplayer: every player sees the story

Branch `ticket/229-mp-story` (based on `ticket/227-mp-lava`), worktree `wt-ticket-9`. Work in progress, committed as `#229: WIP handoff`. No PR yet.

## Design chosen

- **Close rule: "all".** A beat or log closes for the team once every player has closed their own box (the issue's Done-when). One const switches it: `CLOSE_RULE` in `beats/story_beats.gd` (`"all"` or `"any"`). A player who is done sees "Waiting for the other players..." at the foot of the screen (`story.beat.waiting` in `text/strings.gd`) while the game stays paused.
- **Paging is per player.** Each player pages and closes their own box at their own pace; pages are not synced.
- **State in Data, not RPCs, for open/close.** The host alone queues beats and decides when one opens. While one is open it keeps `"<serial>:<id>"` in `team1.story.beatopen` (`OPEN`). Every instance follows that key in `_follow_team()` (each frame): a client opens its own box when the key is set, and force-closes it when the key clears or changes. A late client gets it too, since it is Data.
- **Pause: each instance pauses itself while `OPEN` is set** (`GameWorld.pause(true)` + the stage's `Tween.stop_all()` + `monster` group `pause`, the same three things vanilla's `groupPause` does), enforced every frame because vanilla's `checkForGroupPause` may unpause when someone's pause menu closes. On clear: unpause, and the host calls `stage.checkForGroupPause()` so vanilla's own all-in-pause-menu pause comes back if it applies.
- `showingChoicePopup` is true only while this player's own box is open (so the pause menu can open while waiting). A client's box does not open over its pause menu or another choice popup (`_client_can_show`); it opens when that closes. This covers the #236 builder's note (client box staying open over other popups after the host closed): the old stuck box is gone, and a box never opens on top of another popup.
- The host waits up to `SYNC_WAIT` (20 s) for clients still loading the level before opening a queued beat, so the welcome log isn't over before they arrive (measured: client in sync 1.6 s after the host's run started on localhost).
- The host's depth watch (`_watch_depth`) checks every keeper online (`Keepers.getAll()`), so a client's keeper entering B2 fires the depth beat. Offline it is `Keepers.first()` as before.
- Offline (single player, splitscreen) takes the old code paths: every new branch is behind `_online()`.

## RPCs and where they live

| Node (child of the Story Mode mode node unless said) | RPC | Direction | What |
|---|---|---|---|
| `StoryBeats` (`beats/story_beats.gd`) | `_ack(serial)` | client -> host | "I closed my box of beat number serial" |
| mode node (`gamemode/Storymode.gd`) | `_net_ending_start(lost)` | host -> clients | an ending starts: take controls (`_stop_play`), set `_ending`/`_lost`, `settling()` for 4 frames so the ending's box integrates after `stopKeeperInput` cleared the processors |
| mode node | `_end_won(title, subtitle)` | host -> clients | the same function runs on every instance: `handleGameWon`, music, end screen |
| mode node | `_end_fallen()` | host -> clients | the lost (boss) ending's tail: end screen "fallen" |
| `StoryEndings` (`endings/ending_director.gd`) | `_net_cards(cards, mood)` | host -> clients | narration cards; each instance runs them at its own pace; `close_cards()` closes a client's leftover cards when the end screen comes |
| `StoryPleas` (`pleas/plea_director.gd`) | `_net_say(kind, at, line, life)` | host -> clients | the host picks every plea line; a client's own director says nothing by itself online |
| `StorySalePops` (`hud/sale_pops.gd`) | `_net_pop(amount, color)` | host -> clients | every pop the host queues (minerals and bones) |
| `StoryHeatTalk` (`hud/heat_talk.gd`) | `_net_line(player_id, text, color, kind)` | client -> host -> other clients; host -> clients | a keeper's heat line shows over that keeper on the other screens (`_remote`, `shown_remote`) |

Host -> clients sends go through `Network.rpc_if_state(..., LEVEL_STAGE_SYNC)` like vanilla, so peers not yet in the level don't get "node not found".

Also in `Storymode.gd init()`: online, the host connects `GameWorld.upgradeAdded` to `_on_upgrade_bought`, because vanilla's `remoteBuyUpgrade` (a client's purchase) never emits `upgradeBought` on the host. Without it a client buying Retire Rich paid $1M and nothing happened (seen in the first run), and a client buying the Suit Blaster entry would not grant the gadget.

## Done and verified

Online pair `t229_mp_story_host` / `t229_mp_story_client` (run 2: host 34/34 checks, client 33/34; the one fail was a race in the scenario itself, fixed, see results below for run 3):

- welcome log opens on both, both paused, the client's keeper stands still with a key held; the host closes first, the beat stays open and paused, host sees the waiting line; the client closes, beat recorded as played, both unpause, doesn't reopen
- depth beat `biome_b2` fired by the client's keeper in B2 (host keeper at the dome); client closes first and sees the waiting line; host closes last; both unpause
- sale pops: 3 iron sold on the host, 3 pops on the client, money 15 on both
- plea: the host's line shows on the client, same line; the client's own `say()` returns ""
- heat line: host's shows on the client, client's on the host (called `_say` directly, not through real heat)
- Retire Rich bought by the client: ending starts on the host; `doom_thanks` opens on both; last words; cards; end screen "The Planet Is Lost" on both (client's has "Disconnect from Host")
- screenshots looked at: client welcome, client waiting, client plea/heat/pop, client cards, client end screen, host waiting

RESULTS_PLACEHOLDER

## Half-done / not verified

- `t229_mp_lose_host` / `t229_mp_lose_client` (dome falls -> lost end screen on both) are written but **never run**. Expectation, unverified: it already works, because `Data.listen(self, "team1.dome.health")` in `init()` runs on every instance and `_lose()` is not host-guarded.
- `_end_fallen` / `keeper_lost` (boss death ending) online: written, not run (the boss online is #230).
- The saved ending (`horror_defeated`) online: goes through the same `_net_ending_start` / `_net_cards` / `_end_won`; not run online.
- Miner's log from bones (`BonesDrop.shred` -> `StoryBeats.fire("log_b<n>")`) online: same queue as the welcome log, pop goes through `SalePops.pop`; not run online.
- Real heat (walking into B4+) producing a heat line on the other screen: only the RPC path was exercised by calling `_say`.
- Pleas from a real wave online (`wavepresent`, monster deaths): only a direct `say()` on the host was exercised. A monster's `died` on the host picks last words and sends the position.
- "any" close rule: not run.
- A client joining while a beat is open, a client disconnecting while the team waits on it (`_rule_met` drops peers no longer in `Network.clients`), and a save made with a beat open then loaded online (the host clears a stale `OPEN`; the beat reopens from the queue): reasoned, not run. Saves and drop-in are #232.
- Pause menu opened while waiting for the others (vanilla `groupUnpause` then our re-pause next frame): not run.

## Surprises

- Vanilla never emits `upgradeBought` on the host for a client's purchase (see above).
- `Level.stage.pause()` is a no-op online (`GameWorld.can_pause_game()`); only `GameWorld.pause(true)` pauses.
- `h.read_beat` is not usable on the host with the "all" rule (the host's `open_id` stays set until the team is done); the t229 scenarios use `close_mine(h)` (press select until this player's `_box` is gone).
- Git Bash heredocs with GDScript in them broke here once (quote parsing); patch scripts were written to files and run with Python.

## Next steps

1. Read the results section above; fix anything failing.
2. Run the dome-loss pair: `& "<wt>\mods-unpacked\cejdan-StoryMode\dev\mp_playtest.ps1" t229_mp_lose_host t229_mp_lose_client`; look at both `*_lost.png`.
3. If time: an online bones log check, and a pause-menu-while-waiting check.
4. `CLAUDE.md` still says "Story Mode is single-player only"; the multiplayer playtest paragraph could mention that beats are team-wide online (not changed here).
5. Squash into one commit `#229: Multiplayer: every player sees the story` (a new commit on top is fine; the repo rule is no history rewrites, so ask before squashing a pushed WIP), push, PR into `ticket/227-mp-lava` linking #229 and #222, naming the close rule ("all", per-player paging, team pause) and the list above of what was not verified. Don't merge.

## Commands

```powershell
# online pair (takes the machine-wide lock itself)
& "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\wt-ticket-9\mods-unpacked\cejdan-StoryMode\dev\mp_playtest.ps1" t229_mp_story_host t229_mp_story_client -Timeout 600
# single-player regression through the lock
& "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\playtest_out\run_locked.ps1" "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\wt-ticket-9\mods-unpacked\cejdan-StoryMode\dev\playtest.ps1" t23_beat_box
```

Output: `C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\playtest_out\<scenario>\` (screenshots, `log.json`, `godot.log`).
