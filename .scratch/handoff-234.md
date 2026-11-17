# Handoff #234: online co-op end to end

Branch `ticket/234-mp-end-to-end` in `wt-mp-242`, stacked on `ticket/265-heat-shield-per-keeper` (PR #271).

## Plan
- `t234_mp_e2e_host` / `_client` / `_leaver` (-Client2): leaver buys Teleporter and leaves; host sale; client carries
  iron + B1 bones home; client takes the B2 translator; shop per keeper / team (second weapon chain); gadget shop via
  the client's real shop panel, then host + client at once; client blasts a gate; Metal Bit; wave from both stations;
  Retire Rich by the client.
- Run: `mp_playtest.ps1 t234_mp_e2e_host t234_mp_e2e_client -Client2 t234_mp_e2e_leaver -Timeout 1100`
- Horror-defeated ending: rerun `t230_mp_boss_finale_host/_client` (a run ends once).

## Status
- scenarios written, first run pending
