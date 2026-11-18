# #268 handoff: gadget Data order (big delta, full sync in flight)

Branch `ticket/268-gadget-data-order` off `ticket/272-old-scenarios`, worktree wt-mp-242. PR base `ticket/272-old-scenarios`.

## Done (code)
- `net/ordered_chunker.gd`: `_send_split` now also runs for a delta >= 900 B with nothing queued; keys no queued message holds go now in batches under BATCH (700 B), the rest (and any single value > BATCH) waits/chunks. With a full sync queued, keys sent ahead go in a new RPC `_ahead(fulls, tick, bytes)`; the client pins them per full-sync request id and `receive` re-applies them once that request lands. The old "whole delta also waits behind the full sync" copy is gone (pinning replaces it). `reset()` clears caches.
- Suit Blaster stand-in extensions (SuitBlaster.gd, SuitBlasterHud.gd) removed, with installer EXTENSIONS/SCENES entries.
- t253 host: `--give=drill` (team gadget), `--onedelta` (2.4 KB random key in the same tick), `--fullsync` (client.full_data_sync() right before giving). Client: per-frame watch that no gadget key goes missing after add; notes OrderedChunker.restored.

## To verify
- t253 `--give=drill --onedelta`, `--give=drill --fullsync`, both, `--give=probe --bigdelta`, default shop; t234 pair; t252_class_names; t223 pair.

## Results
(fill in)
