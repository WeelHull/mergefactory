Project State - mergefactory (initial canonical snapshot)
=========================================================

Repository Tree
---------------
dev/
 ├─ REPO_MAP_v1.md
 │  - Type: Documentation - Repo navigation and freeze map.
 ├─ PLACEMENT_FREEZE_v1.md
 │  - Type: Documentation - Frozen placement/interaction behaviors and invariants.
 ├─ MOVE_RELOCATION_FREEZE_v1.md
 │  - Type: Documentation - Frozen move/relocation behaviors and invariants.
 └─ PROJECT_STATE.md
    - Type: Documentation - Canonical project structure and dependencies (this file).

default.project.json
 - Type: Rojo config - Maps src to DataModel (ServerScriptService.Server, ServerScriptService.entry, ReplicatedStorage.Shared, StarterPlayerScripts.Client).

src/
 ├─ shared/
 │  ├─ debugutil.lua
 │  │  - Type: ModuleScript (Shared) - Lightweight structured logger for shared/client scripts.
 │  └─ remotes/
 │     ├─ remotes.meta.json - Metadata declaring remote container folder.
 │     ├─ canplaceontile.rbxmx - RemoteFunction for client placement permission queries.
 │     ├─ place_machine.rbxmx - RemoteEvent for client spawn/relocate requests.
 │     ├─ machine_intent.rbxmx - RemoteEvent for client machine intents (select/rotate/move/delete).
 │     └─ tileunlock.rbxmx - RemoteEvent for client tile unlock requests and responses.
 ├─ server/
 │  ├─ debugutil.lua
 │  │  - Type: ModuleScript (Server) - Centralized server logging (levels, sanitization).
 │  ├─ islandvalidator.lua
 │  │  - Type: ModuleScript (Server) - Validates island ids against workspace.islands.
 │  ├─ islandcontroller.lua
 │  │  - Type: ModuleScript (Server) - Assigns players to free islands; maintains player-to-island maps; hooks PlayerAdded/Removing.
 │  ├─ gridregistry.lua
 │  │  - Type: ModuleScript (Server) - Scans workspace.islands grid tiles, builds unlocked registry, applies locked/unlocked visuals.
 │  ├─ unlockrules.lua
 │  │  - Type: ModuleScript (Server) - Unlock gating (start tile, whitelist keys, adjacency via gridregistry).
 │  ├─ unlockcontroller.lua
 │  │  - Type: ModuleScript (Server) - Authoritative unlock execution; validates via unlockrules, sets gridregistry unlocked state.
 │  ├─ playerlifecycle.lua
 │  │  - Type: ModuleScript (Server) - On PlayerAdded unlocks start tile via unlockcontroller; lifecycle logging.
 │  ├─ machineregistry.lua
 │  │  - Type: ModuleScript (Server) - In-memory machine registry and occupancy tables; ensures workspace.machines; exposes bind/unbind helpers.
 │  ├─ machinespawn.lua
 │  │  - Type: ModuleScript (Server) - Spawns machine models from ServerStorage.assets.machines, sets attributes, registers/binds occupancy.
 │  ├─ machinerelocation.lua
 │  │  - Type: ModuleScript (Server) - Authoritative machine relocation (validates tile/owner/rotation, binds new tile, moves model; merge-aware).
 │  ├─ mergesystem.lua
 │  │  - Type: ModuleScript (Server) - Merge validation/execution (owner/type/tier/island checks, destroys originals, spawns upgraded machine).
 │  ├─ modules/
 │  │  └─ placementpermission.lua
 │  │     - Type: ModuleScript (Server) - Placement permission checks (tile validity, island ownership, unlocked, occupancy/merge allowance).
 │  ├─ machine_bootstrap.server.lua
 │  │  - Type: Script (Server) - Ensures workspace.machines folder via machineregistry at startup.
 │  ├─ machine_intent.server.lua
 │  │  - Type: Script (Server) - Handles machine_intent RemoteEvent (select/rotate/move/delete); validates ownership/binding; calls MachineRegistry/MergeSystem.
 │  └─ place_machine.server.lua
 │     - Type: Script (Server) - Handles place_machine RemoteEvent (spawn or relocate); checks PlacementPermission, ownership, relocation state; calls machinespawn/machinerelocation.
 ├─ server_entry/
 │  └─ main.server.lua
 │     - Type: Script (Server) - Server entrypoint; waits for island assignment, sets player islandid attribute, teleports to spawn, unlocks start tile; wires tileunlock RemoteEvent and canplaceontile RemoteFunction.
 └─ client/
    ├─ placementmode_state.lua
    │  - Type: ModuleScript (Client) - Placement active flag and enter callback registration.
    ├─ placementmode.client.lua
    │  - Type: LocalScript - Placement controller (input, raycast, ghost tint, permission via canplaceontile, send place_machine payloads, confirm/cancel).
    ├─ ghostplacement.lua
    │  - Type: LocalScript - Simple ghost preview tied to canplaceontile results.
    ├─ placement_feedback.lua
    │  - Type: ModuleScript (Client) - Creates placement feedback ScreenGui; exposes feedback helpers.
    ├─ placement_instruction_controller.lua
    │  - Type: ModuleScript (Client) - Mirrors placement debug logs into instruction UI text; enforces terminal placeholders.
    ├─ tileinteractionstate.lua
    │  - Type: ModuleScript (Client) - Tile interaction FSM (Idle/Hovering/Pending/Confirmed) with invariant checks.
    ├─ tilehover.client.lua
    │  - Type: LocalScript - Raycast hover over locked tiles; drives highlight and TileInteractionState; respects placement/machine interaction locks; exposes _tileHoverAPI.ForceClearHover.
    ├─ tileclick_intent.client.lua
    │  - Type: LocalScript - Click to tile intent pipeline (pending/confirm) with highlights; fires tileunlock RemoteEvent; exposes _tileIntentAPI events.
    ├─ tileoptions.client.lua
    │  - Type: LocalScript - Tile options UI (buy tile); reacts to _tileIntentAPI events; fires tileunlock; clears hover on cancel.
    ├─ visuals/
    │  └─ tile_unlock_feedback.lua
    │     - Type: ModuleScript (Client) - Plays unlock visual tween on tile parts (color/size pulse with cooldown).
    ├─ machineinteraction_state.lua
    │  - Type: ModuleScript (Client) - Tracks machine interaction active/relocating flags; logs relocating changes.
    ├─ machine_interaction.client.lua
    │  - Type: LocalScript - Machine hover/selection UI and intent dispatch (machine_intent remote); delete/rotate; move enters placement payload.
    ├─ validators/
    │  ├─ init.client.lua
    │  │  - Type: LocalScript - Boots ux_interaction_validator if present.
    │  └─ ux_interaction_validator.lua
    │     - Type: ModuleScript (Client) - Live log consumer enforcing UX invariants (hover/pending/placement/instruction); logs violations and warnings.
    └─ Notes
       - Client expects pre-existing UI instances (PlayerGui.tileoptions, PlayerGui.editoptions) and models (ReplicatedStorage.ghostplacement, ReplicatedStorage.previews) from the Roblox place; not present in src.

System Groupings
----------------
- Boot / Lifecycle (Server): src/server_entry/main.server.lua initializes players (islandid attribute, teleport to spawn, unlock start tile), binds remotes; src/server/islandcontroller.lua assigns islands; src/server/playerlifecycle.lua also unlocks start tile on join. Authority: Server.
- Grid / Island / Unlock System (Server): gridregistry.lua holds tile state and visuals; unlockrules.lua determines eligibility; unlockcontroller.lua executes unlock; islandvalidator.lua validates ids; islandcontroller.lua maintains player-to-island mappings; main.server.lua handles tileunlock RemoteEvent responses. Authority: Server.
- Placement Permission (Server): modules/placementpermission.lua validates tile placement/ownership/unlocked/occupancy (merge-aware), reused by place_machine.server.lua, machinerelocation.lua, and main.server.lua (canplaceontile). Authority: Server.
- Machine Runtime (Server): machineregistry.lua registry and occupancy; machinespawn.lua spawns/binds machines; machinerelocation.lua relocates (merge-aware); mergesystem.lua validates/executes merges; machine_bootstrap.server.lua ensures workspace container; machine_intent.server.lua handles selection/rotate/delete/move intents; place_machine.server.lua handles spawn/relocate requests. Authority: Server.
- Placement / Ghost (Client): placementmode_state.lua and placementmode.client.lua manage placement session, raycasts, ghost tint, permission checks, and place_machine firing; ghostplacement.lua provides minimal ghost preview tied to canplaceontile. Authority: Client drives UX; server authorizes via remotes.
- Tile Interaction / Unlock UI (Client): tileinteractionstate.lua, tilehover.client.lua, tileclick_intent.client.lua, tileoptions.client.lua, visuals/tile_unlock_feedback.lua orchestrate hover/pending/confirm and tileunlock RemoteEvent usage. Authority: Client UX; server authorizes unlock via unlockcontroller.
- Placement UX Feedback (Client): placement_feedback.lua and placement_instruction_controller.lua render placement state text and invalid feedback; driven by placementmode and tile click scripts. Authority: Client.
- Machine Interaction UX (Client): machine_interaction.client.lua and machineinteraction_state.lua manage machine selection highlighting, editoptions UI, and machine_intent remoting; integrates relocation payload into placement mode. Authority: Client UX; server authorizes via machine_intent handler.
- Validation / Debug (Shared/Client/Server): src/shared.debugutil.lua and src/server.debugutil.lua provide logging; validators/ux_interaction_validator.lua enforces client UX invariants from log stream. Authority: Logger only; validator client-side.
- Remotes and Networking: Defined under src/shared/remotes/; consumed by placement/interaction scripts (see flows below). Authority: Server owns RemoteFunction/RemoteEvents.

Dependencies and Call Flow
--------------------------
- Requires / Module Usage (Server):
  - main.server.lua -> debugutil, islandcontroller, unlockcontroller, modules/placementpermission, machineregistry.
  - unlockcontroller.lua -> gridregistry, unlockrules, islandcontroller.
  - unlockrules.lua -> gridregistry.
  - playerlifecycle.lua -> islandcontroller, unlockcontroller.
  - machinespawn.lua -> Server.Server.debugutil, gridregistry, machineregistry.
  - machineregistry.lua -> islandvalidator, Server.Server.debugutil.
  - machinerelocation.lua -> gridregistry, machineregistry, modules/placementpermission, mergesystem.
  - mergesystem.lua -> Server.Server.debugutil, machineregistry, machinespawn.
  - place_machine.server.lua -> machinespawn, islandvalidator, modules/placementpermission, machineregistry, machinerelocation, debugutil.
  - machine_intent.server.lua -> Server.Server.debugutil, islandvalidator, machineregistry, mergesystem.
  - modules/placementpermission.lua -> debugutil, islandcontroller, gridregistry, mergesystem, machineregistry.
- Requires / Module Usage (Client):
  - Most client modules depend on ReplicatedStorage.Shared.debugutil.
  - Placement flow: placementmode.client.lua -> placementmode_state, placement_feedback, MachineInteractionState, remotes canplaceontile/place_machine; ghostplacement.lua -> placementmode_state, canplaceontile; placement_instruction_controller.lua wraps debugutil.
  - Tile interaction: tilehover.client.lua -> tileinteractionstate, placementmode_state, machineinteraction_state; tileclick_intent.client.lua -> tileinteractionstate, placementmode_state, placement_feedback, visuals/tile_unlock_feedback; tileoptions.client.lua -> placementmode_state, tileinteractionstate.
  - Machine interaction: machine_interaction.client.lua -> machineinteraction_state, placementmode_state, machine_intent remote.
  - Validators: validators/init.client.lua -> ux_interaction_validator.lua, which consumes log output via debugutil.
- Remotes:
  - Shared.remotes.canplaceontile (RemoteFunction): OnServerInvoke in main.server.lua delegates to PlacementPermission.CanPlaceOnTile and MachineRegistry occupancy check. Called by placementmode.client.lua, ghostplacement.lua; relocation path can pass ignoreMachineId.
  - Shared.remotes.place_machine (RemoteEvent): OnServerEvent in place_machine.server.lua for spawn/relocate. Fired by placementmode.client.lua with payload kind=machine or kind=relocate.
  - Shared.remotes.machine_intent (RemoteEvent): OnServerEvent in machine_intent.server.lua for select/rotate/delete/move/merge routing. Fired by machine_interaction.client.lua.
  - Shared.remotes.tileunlock (RemoteEvent): OnServerEvent in main.server.lua to unlock tiles and respond to client. Fired by tileoptions.client.lua and optionally tileclick_intent.client.lua.
- Initialization / Entry Points:
  - Server: ServerScriptService.entry.main.server.lua boots lifecycle and remotes; other .server.lua Scripts auto-run (machine_bootstrap, place_machine, machine_intent). ModuleScripts initialize on require (gridregistry builds registry immediately).
  - Client: LocalScripts (placementmode.client.lua, tilehover.client.lua, tileclick_intent.client.lua, tileoptions.client.lua, ghostplacement.lua, machine_interaction.client.lua, validators/init.client.lua) auto-run from StarterPlayerScripts.Client.
- External Assets / Expectations:
  - Workspace must contain islands models with grid tiles and attributes (gridx, gridz, unlocked, islandid, optional spawn part).
  - ServerStorage requires assets/machines/<type>/tiers/tier_<n> models with PrimaryPart.
  - ReplicatedStorage requires ghostplacement model and previews folder with machine preview models; PlayerGui requires tileoptions and editoptions UI.
  - ⚠ Unknown - requires runtime inspection to confirm asset presence/structure (not in repository sources).

System Status
-------------
- Grid / Island / Unlock System — Frozen.
- Placement Permission and Interaction — Frozen (per dev/PLACEMENT_FREEZE_v1.md).
- Machine Runtime (registry/spawn/relocate/merge) — Frozen.
- Machine Interaction UX — Frozen.
- Placement UX (ghost/feedback/instruction) — Frozen.
- Tile Interaction / Unlock UI — Frozen.
- Validation / Logging Utilities — Frozen.
- External Assets (ServerStorage/ReplicatedStorage UI/models) — Frozen (assumed stable; not sourced here).

Workflow / Governance Constraints
---------------------------------
- ADDED: Brain Governance Obligations — The Brain does not retain project memory; reconstructs understanding only from dev/PROJECT_STATE.md, current inspection output, and human observation; must halt and request inspection if state is uncertain; build prompts require verified state or explicit “state unchanged”; must interrogate before execution and never act on assumed behavior.
- ADDED: Ask-First / Inspect-First Workflow — Codex is queried for structure, responsibilities, and exact code snippets; human supplies runtime observations and debug logs; decisions occur only after correlating evidence.
- ADDED: Phase Boundary Enforcement — Chats operate in explicit phases: BRAINSTORM, STATE_VERIFICATION, INTENT_CONFIRMATION, EXECUTION; Codex build prompts are valid only during EXECUTION.
- ADDED: Inspection Requirement — Before any modification, either an inspection happens in the current chat or an explicit inspection skip is declared; silent inspection bypass is forbidden.
- ADDED: Canonical File Control — Governance files are updated only when explicitly instructed; Codex must never update governance files implicitly; governance documentation is process guidance, not runtime logic.
