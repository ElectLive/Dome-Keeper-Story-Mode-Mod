# Handoff: #230 boss sequence for a team

All three slices are built, each a stacked PR (nothing merged, #230 open):

| Slice | Branch | PR | Base |
|---|---|---|---|
| 1, Velle's chamber fight | `ticket/230-mp-boss-fight` | #239 | `ticket/227-mp-lava` |
| 2, the chase | `ticket/230-mp-boss-chase` | #240 | `ticket/230-mp-boss-fight` |
| 3, the finale | `ticket/230-mp-boss-finale` | see #230 | `ticket/230-mp-boss-chase` |

## Design

- Host authority everywhere; a client builds the same nodes as `puppet`s that skip the AI and draw the host's stream (`boss/boss_director.gd`, "online (#230)").
- Hearts: one shared team pool (`team1.story.hearts`, interim: the user has not chosen between this and hearts per keeper). A hit on any keeper costs one, decided on the host and played on that keeper's instance.
- Fight: any keeper in the chamber starts it; each instance seals in its own keepers. A client reveals the chamber itself when the fight starts.
- Chase (`boss/chase.gd`): the tentacles hunt one keeper out of the dome at a time, the one nearest their lead tip; they turn when another is 90 px nearer (2 s rest) or the hunted one gets home (trail cut at the lead tip, straight on to the new target). Touching any keeper out of the dome costs a heart. Over when every keeper is home and at least one has been out. Trail sent in parts, reliably; a client asks for all of it when it missed a part.
- Finale (`boss/finale.gd` and the monster scripts): the host's monsters go into vanilla's `MonsterSynchronizer.monsters` under the same UID on every peer, so a client's dome weapon hits reach the host (vanilla `PrimaryWeapon` hit data) and the host's health and deaths come back. Copies are built from `net_record()` in the 15 Hz finale stream (unreliable, the whole roster every time). A copy's `hit()` only flashes. A client at the dome's weapon ends the breath (`_net_battle`). A client plays the saved ending on `won` (`Storymode.horror_defeated_here`) and the lost ending on `lost` from the fight or chase.

## Tests

- Pairs: `t230_mp_boss_fight_*`, `t230_mp_boss_chase_*`, `t230_mp_boss_finale_*` (`dev/mp_playtest.ps1 <host> <client>`).
- Known failures that predate #230 (they fail the same way on `ticket/227-mp-lava`): `t160_boss_play` ("the bot hurt Velle with carried charges") and `t170_dev_chase` ("Laser III (110 dps)": stale since the dev gear gives Laser IV).
- "Lambda capture at index 0 was freed" errors show up in single-player boss runs too (t160_boss_fight, t162_finale, t171_finale_play): not from #230.

## Not verified / gaps

- A client's lost ending (no two-instance run loses the fight or the chase); a dome lost in the finale on a client.
- Saving and loading mid-sequence online; a client joining mid-sequence (the chase resends its trail, the finale roster repeats, but no test).
- Hearts per keeper (design call for the user).
- Known single-player bug: #237 (`velle.gd _update_orbs` index error when the keeper dies mid-fight).
