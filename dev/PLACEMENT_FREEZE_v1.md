# Placement / Interaction Freeze — v1

## A — Scope
- This freeze covers the current, correct behavior of:
  - Tile hover
  - Tile pending / TileOptions visibility
  - Tile unlock flow (client intent + server authority)
  - Placement mode (enter/exit, permission checks)
  - Ghost placement visuals
  - Placement feedback UI
  - Placement cancel / confirm logic

## B — State Machine
- TileInteractionState valid states: Idle, Hovering, Pending, Confirmed.
- PlacementMode states: Idle (inactive), Placing, Valid, Invalid (active when permission denies).
- Illegal transitions (TileInteractionState): anything not in {Idle→Hovering, Hovering→Pending, Pending→Confirmed, Confirmed→Idle, Any→Idle(cancel/force)} must be blocked and warn-logged; state must NOT mutate.
- Illegal transitions (PlacementMode): any transition not driven by existing enter/confirm/cancel pathways must be blocked (warn) and ignored.

## C — Placement Consequences (critical)
1) Click on UNLOCKED tile
   - Placement confirms
   - Placement exits
   - Returns to Idle
2) Click on LOCKED tile
   - Placement stays active
   - Invalid placement feedback is shown
   - Ghost remains; no deselection
3) Click OUTSIDE / no tile
   - Invalid placement feedback is shown
   - Placement cancels
   - Returns to Idle

## D — Guards & Invariants
- Placement feedback must NOT fire when placement is inactive.
- Placement cancel must always end in Idle.
- No hovered tile may persist after cancel.
- No pending tile may persist after cancel.
- Placement must consume input on confirm/cancel and release it on InputEnded.
- Hover system must be blocked while placement is active.

## E — Logging Contract
- All placement and interaction decisions must emit structured debugutil logs.
- Logs are relied upon for verification/audit; removing or silencing logs is a breaking change.

## F — Regression Rule
- Any future change affecting placement or interaction must:
  - Re-run the Hidden Bug Audit script.
  - Preserve all behaviors documented here.
  - Update this document only when behavior intentionally changes.
