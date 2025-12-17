# REPO_MAP_v1 — mergefactory

This file is a **navigation + freeze map** for the repo. It is meant to be used as a quick index:
- Find the **right file** for a responsibility
- Jump to the **raw link** to re-audit the *current* contents after Codex edits
- Preserve consistent **system boundaries** across future changes

---

## Folder anchors (tree links)

- `dev/`  
  https://github.com/WeelHull/mergefactory/tree/master/dev

- `src/`  
  https://github.com/WeelHull/mergefactory/tree/master/src

- `src/client/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/client

- `src/client/validators/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/client/validators

- `src/client/visuals/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/client/visuals

- `src/server/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/server

- `src/server/modules/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/server/modules

- `src/server_entry/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/server_entry

- `src/shared/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/shared

- `src/shared/remotes/`  
  https://github.com/WeelHull/mergefactory/tree/master/src/shared/remotes

---

## Rojo wiring (source of truth)

- `default.project.json`  
  Role: Rojo mapping that determines where scripts land in Roblox services (ServerScriptService / ReplicatedStorage / StarterPlayerScripts, etc).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/default.project.json

---

## DEV freezes

- `dev/PLACEMENT_FREEZE_v1.md`  
  Role: Placement behavior freeze (expected states, allowed/blocked transitions, invariants).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/dev/PLACEMENT_FREEZE_v1.md

- `dev/MOVE_RELOCATION_FREEZE_v1.md`  
  Role: Move/relocation behavior freeze (expected flow + rules).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/dev/MOVE_RELOCATION_FREEZE_v1.md

---

## SHARED (ReplicatedStorage.Shared)

- `src/shared/debugutil.lua`  
  Role: Shared/client logging utility used by client systems.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/debugutil.lua

- `src/shared/remotes.meta.json`  
  Role: Metadata for the `Shared/remotes` asset folder.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/remotes.meta.json

### Shared remotes (assets)

Role: Defines the RemoteFunction/RemoteEvent instances (by name/type) inside `ReplicatedStorage.Shared.remotes`.

- `src/shared/remotes/canplaceontile.rbxmx`  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/remotes/canplaceontile.rbxmx

- `src/shared/remotes/machine_intent.rbxmx`  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/remotes/machine_intent.rbxmx

- `src/shared/remotes/place_machine.rbxmx`  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/remotes/place_machine.rbxmx

- `src/shared/remotes/tileunlock.rbxmx`  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/shared/remotes/tileunlock.rbxmx

---

## SERVER (ServerScriptService.Server)

### Logging

- `src/server/debugutil.lua`  
  Role: Central structured logging for server systems (enable flag, levels, formatting).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/debugutil.lua

### Island + grid + unlock family

- `src/server/islandcontroller.lua`  
  Role: Assigns `islandid` per player session; maintains player↔island mapping.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/islandcontroller.lua

- `src/server/islandvalidator.lua`  
  Role: Validates island ids by scanning `workspace.islands` for matching `islandid` attribute.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/islandvalidator.lua

- `src/server/gridregistry.lua`  
  Role: Scans islands/grids/tiles; owns authoritative tile lookup + unlocked state + visuals apply.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/gridregistry.lua

- `src/server/unlockrules.lua`  
  Role: Unlock permission rules (start tile, whitelist, adjacency checks).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/unlockrules.lua

- `src/server/unlockcontroller.lua`  
  Role: Authoritative unlock execution (checks rules → calls gridregistry to set unlocked).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/unlockcontroller.lua

- `src/server/playerlifecycle.lua`  
  Role: Player join lifecycle; seeds initial unlock/progression state.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/playerlifecycle.lua

### Placement permission gate

- `src/server/modules/placementpermission.lua`  
  Role: Server-authoritative “can place” checks (tile validity, island ownership, unlocked status).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/modules/placementpermission.lua

### Machines family (registry / bootstrap / intent / spawn / relocate / place)

- `src/server/machineregistry.lua`  
  Role: In-memory machine registry + tile occupancy binding; ensures `workspace.machines`.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/machineregistry.lua

- `src/server/machine_bootstrap.server.lua`  
  Role: Bootstraps machine folder/runtime (calls `machineregistry.ensureMachinesFolder`).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/machine_bootstrap.server.lua

- `src/server/machine_intent.server.lua`  
  Role: Server handler for machine intents (select/rotate/move/delete) via `machine_intent` remote; validates ownership; uses MachineRegistry.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/machine_intent.server.lua

- `src/server/machinespawn.lua`  
  Role: Machine spawn service (creates machine model, binds occupancy, sets attrs/initial state).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/machinespawn.lua

- `src/server/machinerelocation.lua`  
  Role: Machine relocation service (eligibility checks + move/apply rotation + occupancy updates).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/machinerelocation.lua

- `src/server/place_machine.server.lua`  
  Role: Server handler for placing machines and relocation finalization via `place_machine` remote.  
  Connects to: `placementpermission`, `machinespawn`, `machinerelocation`, `machineregistry`.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server/place_machine.server.lua

---

## SERVER ENTRY (ServerScriptService.entry)

- `src/server_entry/main.server.lua`  
  Role: Server entrypoint; requires/boots server systems in the intended order.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/server_entry/main.server.lua

---

## CLIENT (StarterPlayerScripts.Client)

### Placement family (mode / ghost / UI feedback)

- `src/client/placementmode_state.lua`  
  Role: Client placement mode state + events (active/inactive).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/placementmode_state.lua

- `src/client/placementmode.client.lua`  
  Role: Client placement controller (input + state transitions + confirm/cancel pathways).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/placementmode.client.lua

- `src/client/ghostplacement.lua`  
  Role: Ghost preview; raycasts hovered tile; calls `canplaceontile` RemoteFunction; tints/positions ghost.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/ghostplacement.lua

- `src/client/placement_feedback.lua`  
  Role: Placement feedback UI surface.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/placement_feedback.lua

- `src/client/placement_instruction_controller.lua`  
  Role: Binds state/log output to instructional UI copy.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/placement_instruction_controller.lua

### Tile interaction family (hover / click intent / state / options UI)

- `src/client/tileinteractionstate.lua`  
  Role: Tile interaction FSM (idle/hover/pending/confirmed) and transition logging.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/tileinteractionstate.lua

- `src/client/tilehover.client.lua`  
  Role: Hover detection + highlight; exposes hover API used by other client scripts.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/tilehover.client.lua

- `src/client/tileclick_intent.client.lua`  
  Role: Click→intent plumbing; exposes intent API used by tile options UI.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/tileclick_intent.client.lua

- `src/client/tileoptions.client.lua`  
  Role: Tile options UI; fires `tileunlock` RemoteEvent and reacts to unlock results.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/tileoptions.client.lua

### Client machine interaction family

- `src/client/machineinteraction_state.lua`  
  Role: Client machine interaction state (selection/current machine/relocating flags, etc).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/machineinteraction_state.lua

- `src/client/machine_interaction.client.lua`  
  Role: Machine selection UX + intent sending (machine_intent; ties into relocation flow).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/machine_interaction.client.lua

### Client validators

- `src/client/validators/init.client.lua`  
  Role: Validator init/loader for client UX constraints.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/validators/init.client.lua

- `src/client/validators/ux_interaction_validator.lua`  
  Role: UX interaction constraint checks (gates hover/click/placement transitions).  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/validators/ux_interaction_validator.lua

### Client visuals

- `src/client/visuals/tile_unlock_feedback.lua`  
  Role: Client-only unlock feedback visuals.  
  Raw: https://raw.githubusercontent.com/WeelHull/mergefactory/master/src/client/visuals/tile_unlock_feedback.lua

---
