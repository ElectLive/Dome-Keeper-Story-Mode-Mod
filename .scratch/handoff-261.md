# Handoff #261 / #263

Worktree wt-mp-242. #261 on `ticket/261-mp-gadget-data-order` (base `ticket/231-mp-splitscreen`, PR #262); #263 to go on `ticket/263-split-views` stacked on it.

## #261 (done, PR pending)
- `net/ordered_chunker.gd` `_send_split`: a small delta to a peer with queued Data sends at once the keys no queued message to that peer holds; the rest waits behind as a single-chunk request. With a full sync queued, the new keys go at once and the whole delta also waits behind it (a full sync replaces all of a client's Data). Keys per queued message cached by request id.
- `--heldchunker` (editor) restores the #246 hold-whole behaviour.
- t253 scenarios: `--give=<gadget>` (e.g. probe) gives another gadget; client checks every gadget key was in Data when upgradeAdded fired, and that the Suit Blaster stand-ins (static `stand_ins` counters) were not needed.
- Suit Blaster fallback stays as insurance (full-sync window; chunked gadget deltas).
- Evidence: `--bigdelta` (shop), `--bigdelta --give=probe`, `--bigdelta --vanilla`, `--bigdelta --devgear`, `--early --give=probe`, `--early --vanilla` pass; `--bigdelta --give=probe --heldchunker` and `--bigdelta --vanilla --heldchunker` fail (keys late, unknown-key errors / 3 stand-ins). t242 and t246 pass.

## #263
- (not started)
