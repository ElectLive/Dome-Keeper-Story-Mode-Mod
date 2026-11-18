# Handoff: #229 Multiplayer: every player sees the story

Branch `ticket/229-mp-story`, worktree `wt-ticket-9`. Built on `ticket/227-mp-lava`, then `origin/ticket/230-mp-boss-finale` merged in (the #230 boss stack). PR into `ticket/230-mp-boss-finale`; not merged. Done; final commit `#229: Multiplayer: every player sees the story`.

## Design

- **Close rule: "all".** A beat or log closes for the team once every player has closed their own box (the issue's Done-when). One const switches it: `CLOSE_RULE` in `beats/story_beats.gd` (`"all"` or `"any"`). A player who is done sees "Waiting for the other players..." at the foot of the screen (`story.beat.waiting` in `text/strings.gd`) while the game stays paused.
- **Paging is per player.** Each player pages and closes their own box at their own pace; pages are not synced.
- **Team pause (interim; the user's call on #229: pause everyone, or keep playing).** The host alone queues beats and decides when one opens. While one is open it keeps `"<serial>:<id>"` in `team1.story.beatopen` (`OPEN`). Every instance follows that key in `_follow_team()` each frame: a client opens its own box when the key is set and force-closes it when the key clears or changes; each instance pauses itself while it is set (`GameWorld.pause(true)` + the stage's `Tween.stop_all()` + `monster` group `pause`, what vanilla's `groupPause` does), enforced every frame because vanilla's `checkForGroupPause` may unpause when someone's pause menu closes. On clear: unpause, and the host calls `stage.checkForGroupPause()`.
- `showingChoicePopup` is true only while this player's own box is open. A client's box never opens over its pause menu or another choice popup (`_client_can_show`).
- The host waits up to `SYNC_WAIT` (20 s) for clients still loading before opening a queued beat (measured: client in sync 1.5-1.6 s after the run starts on localhost).
- The host's depth watch checks every keeper online, so a client's keeper entering B2 fires the depth beat.
- Offline (single player, splitscreen) takes the old code paths: every new branch is behind `_online()`.
- Online, the host connects `GameWorld.upgradeAdded` to `_on_upgrade_bought`: vanilla's `remoteBuyUpgrade` never emits `upgradeBought` on the host, so a client's Retire Rich or Suit Blaster purchase did nothing before.

## How endings reach clients (after the #230 merge)

One way: the host's game mode node (`gamemode/Storymode.gd`) runs every story ending and sends each step. `_stop_play()` sends `_net_ending_start(lost)`; `StoryEndings._cards()` sends `_net_cards(cards, mood)`; `_end_won(title, subtitle)` / `_end_fallen()` run on every instance (the host's call, sent on). Retire Rich (doom), the saved ending (`horror_defeated`) and the boss's lost ending (`keeper_lost`, now host-only) all go through it.

The #230 finale slice had a second way: a client's boss director called `Storymode.horror_defeated_here()` on `won` and `keeper_lost()` on `lost`, playing the ending locally. With both, a client would have run the ending twice. Removed: `horror_defeated_here()` is gone; the client's boss director only stops the music (and on `lost` hides the keepers). The host-driven path was kept because it covers every ending (a client's Retire Rich purchase included), not just the boss's.

The dome falling stays vanilla's way: every instance sees `team1.dome.health` reach 0 and runs `_lose()` itself (no cards); only the host calls `boss.dome_lost()` (it writes Data).

Every end screen goes through `_show_end(popup)`, which shows at most one per run (a second is refused with a warning) and closes a client's leftover cards. Counters for tests: `Storymode.end_screens`, `StoryEndings.cards_shown`.

## RPCs and where they live

| Node (child of the Story Mode mode node unless said) | RPC | Direction | What |
|---|---|---|---|
| `StoryBeats` (`beats/story_beats.gd`) | `_ack(serial)` | client -> host | "I closed my box of beat number serial" |
| mode node (`gamemode/Storymode.gd`) | `_net_ending_start(lost)` | host -> clients | an ending starts: take controls, set `_ending`/`_lost`, settle 4 frames |
| mode node | `_end_won(title, subtitle)` | host -> clients | won end screen |
| mode node | `_end_fallen()` | host -> clients | the boss lost ending's end screen |
| `StoryEndings` (`endings/ending_director.gd`) | `_net_cards(cards, mood)` | host -> clients | narration cards, each instance at its own pace |
| `StoryPleas` (`pleas/plea_director.gd`) | `_net_say(kind, at, line, life)` | host -> clients | the host picks every plea line |
| `StorySalePops` (`hud/sale_pops.gd`) | `_net_pop(amount, color)` | host -> clients | every sale pop |
| `StoryHeatTalk` (`hud/heat_talk.gd`) | `_net_line(player_id, text, color, kind)` | client -> host -> other clients; host -> clients | a keeper's heat line over that keeper on the other screens |

Host -> clients sends go through `Network.rpc_if_state(..., LEVEL_STAGE_SYNC)`.

## Verified (2026-11-16, after the merge)

Online pairs (`dev/mp_playtest.ps1`), all exit 0, 0 script errors:

- `t229_mp_story_host/client`: host 32/32, client 35/35. Welcome log on both, paused, host closes first and waits (waiting line), client closes, both resume; depth beat fired by the client's keeper in B2, client closes first; 3 sale pops on the client, $15 on both; the host's plea and heat line on the client and the client's heat line on the host; Retire Rich bought by the client: `doom_thanks`, last words, cards, "The Planet Is Lost" on both; exactly 1 card set and 1 end screen on each.
- `t229_mp_lose_host/client` (first run ever): host 7/7, client 5/5. "THE DOME IS LOST" on both, 1 end screen, 0 card sets each.
- `t229_mp_fallen_host/client` (new): host 11/11, client 7/7. The team's hearts run out in Velle's fight (`_keeper_died` on the host): fallen cards and "The Planet Is Lost / You woke it..." on both, 1 card set and 1 end screen each.
- `t230_mp_boss_finale_host/client`: host 16/16, client 21/21; the saved ending's cards and "The Planet Is Saved" on both, 1 card set and 1 end screen each (checks added).
- `t230_mp_boss_fight_host/client`: host 17/17, client 28/28.

Screenshots looked at: client waiting line, client doom end screen, both dome-lost screens, client saved cards and end screen, client fallen cards and end screen.

Single-player regressions through the lock: 18 scenarios, all exit 0 with 0 failed checks: t23_beat_box 24/24, t23_beat_reload 14/14, t123_keeper_log 6/6, t123_reload 2/2, t96_doom 8/8, t96_doom_stage3 7/7, t96_queued_beat 7/7, t97_saved 5/5, t97_dev_command 3/3, t162_fallen 6/6, t162_finale 44/44, t54_retire_rich 6/6, t54_no_relics 3/3, t91_pleas 26/26, t121_sale_pops 8/8, t146_heat_lines 9/9, t06_story_run 3/3, t06_vanilla 3/3. No regressions.

## Not verified

- Miner's log from bones online (same queue as the welcome log; not run).
- Real heat producing a heat line on the other screen (only `_say` called directly).
- Pleas from a real wave online (only a direct `say()` on the host).
- The "any" close rule.
- A client joining while a beat is open, a client disconnecting while the team waits on it, a save made with a beat open and loaded online (saves and drop-in are #232).
- Opening the pause menu while waiting for the others.
- The dome falling in the boss finale online (`_lose` with `fallen`).
- A client reading the cards slower than the host: its cards are closed when the host's end screen comes (by design, not tested at a slow pace).

## Surprises

- Vanilla never emits `upgradeBought` on the host for a client's purchase.
- `Level.stage.pause()` is a no-op online; only `GameWorld.pause(true)` pauses.
- `h.read_beat` is not usable on the host with the "all" rule; the t229 scenarios use `close_mine(h)`.
- Git Bash heredocs with GDScript broke here once; patch scripts were written to files and run with Python.
