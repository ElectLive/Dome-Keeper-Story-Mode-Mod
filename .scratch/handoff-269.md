# Handoff: #269 domes, #270 drone cargo, #272 old scenarios

Worktree `wt-mp-242`. Branches stacked: `ticket/269-story-domes` (on `ticket/234-mp-end-to-end`, PR #275), then `ticket/270-drone-cargo`, then `ticket/272-old-scenarios`.

## #269 findings so far
- Vanilla loadout offers dome1-4 (`Data.loadoutDomes`); dome5 (turrets) is unreleased: not in loadoutDomes, no `loadout_dome5.png`, health meter / wave meter list dome1-4 as predecessors, railgun/minelayer slots do nothing (Turrets.gd only builds machine guns).
- Shredders: all use base Shredder.gd; Story minerals get there by Dome.getDropTarget (extension) and StoryDropTrigger. dome3 has its own extension (class_name subclass).
- Boot key `dome` works in a scenario's boot() (Story.user_arg falls back to scenario_boot).
- Laser-only spots: `MultiplayerloadoutStage.gd` STORY_DOME lock; `dev/boss_dev.gd` GEAR.

## Status
- [ ] prices.gd dome2-5
- [ ] loadout offers every dome
- [ ] boss_dev gear per dome
- [ ] t269_dome2..5 + online pair
