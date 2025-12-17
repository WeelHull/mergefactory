# MOVE_RELOCATION_FREEZE_v1

## States & Flow
- **Select Machine**: editoptions opens; MachineInteractionState active=true.
- **Move Pressed**: logs `move_pressed`, sends `machine_intent` intent=move with machineId/grid; editoptions closed; MachineInteractionState.relocating=true; enter placement payload `{kind="relocate", machineId, machineType, tier, rotation}`.
- **Relocate Placement**:
  - Tile hover allowed (tilehover skips machine_active when relocating).
  - Ghost uses matching preview model for machineType/tier.
  - canplaceontile invoked with ignoreMachineId to allow source tile; logs permission changes.
- **Confirm**: logs `confirm_relocate`; fires `place_machine` with kind=relocate + coords + rotation; MachineInteractionState.relocating=false; placement exits.
- **Cancel**: logs `cancel_relocate`; MachineInteractionState.relocating=false; ghost cleared; editoptions re-opened on the original machine if found.

## Remotes Used
- `Shared.remotes.machine_intent` (RemoteEvent): intents `select`, `move` (prep).
- `Shared.remotes.canplaceontile` (RemoteFunction): now accepts optional ignoreMachineId for relocation permission.
- `Shared.remotes.place_machine` (RemoteEvent): accepts relocate payload to apply move on server.

## Server Responsibilities
- canplaceontile: validates tile + occupancy (ignores occupant matching ignoreMachineId).
- place_machine (relocate kind): validates ownership/Relocating state, uses machinerelocation to unbind/bind and move model, logs `relocated`.

## Client Responsibilities
- machine_interaction: handles button wiring, logs, toggles relocating flag, enters placement, reopens UI on cancel.
- placementmode: ghost/hover, permission checks, confirm/cancel, logs, calls place_machine.
- tilehover: hover allowed while relocating.

## Invariants
- No UI creation/rename; editoptions reused.
- Logs via debugutil only, one-line.
- Server is authoritative for placement/relocation.
- Machines remain in workspace.machines; relocation does not clone/destroy.

## Regression Checklist
- Select machine → Move shows ghost and allows tile hover.
- Move confirm relocates model; registry updates, no errors.
- Move cancel restores editoptions on same machine.
- Delete/Rotate continue working.
- Hover over tiles while relocating works; non-relocate still blocked by selection.
- canplaceontile returns tile_occupied when target has other machine; allows source tile via ignoreMachineId.
