-- Handles client requests to place machines.
-- Authoritative. Minimal. No refactors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MachineSpawn = require(ServerScriptService.Server.machinespawn)
local IslandValidator = require(ServerScriptService.Server.islandvalidator)
local PlacementPermission = require(ServerScriptService.Server.modules.placementpermission)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local machinerelocation = require(ServerScriptService.Server.machinerelocation)
local debugutil = require(ServerScriptService.Server.debugutil)

local remote =
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("remotes")
		:WaitForChild("place_machine")

local function handleRelocate(player, payload, islandid)
	if typeof(payload.gridx) ~= "number" or typeof(payload.gridz) ~= "number" then
		return
	end

	local machineId = payload.machineId
	if typeof(machineId) ~= "string" or machineId == "" then
		return
	end

	local model = MachineRegistry.get(machineId)
	if not model then
		debugutil.log("machine", "warn", "relocate_rejected", { reason = "machine_not_found", machineId = machineId })
		return
	end

	local ownerUserId = model:GetAttribute("ownerUserId")
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= player.UserId then
		debugutil.log("machine", "warn", "relocate_rejected", { reason = "not_owner", machineId = machineId })
		return
	end

	if model:GetAttribute("state") ~= "Relocating" then
		debugutil.log("machine", "warn", "relocate_rejected", { reason = "not_relocating", machineId = machineId })
		return
	end

	local rotation = payload.rotation
	if typeof(rotation) ~= "number" then
		rotation = model:GetAttribute("rotation") or 0
	end
	rotation = ((rotation % 360) + 360) % 360

	local allowed, reason = PlacementPermission.canPlace({
		player = player,
		islandid = islandid,
		gridx = payload.gridx,
		gridz = payload.gridz,
		machineType = payload.machineType,
		tier = payload.tier,
	})
	if not allowed then
		debugutil.log("machine", "warn", "relocate_rejected", {
			reason = reason or "placement_denied",
			machineId = machineId,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
		return
	end

	local ok, why = machinerelocation.CanRelocate(machineId, payload.gridx, payload.gridz, islandid, rotation)
	if not ok then
		debugutil.log("machine", "warn", "relocate_rejected", {
			reason = why,
			machineId = machineId,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
		return
	end

	local moved, moveReason = machinerelocation.Relocate(machineId, payload.gridx, payload.gridz, islandid, rotation)
	if not moved then
		debugutil.log("machine", "warn", "relocate_rejected", {
			reason = moveReason,
			machineId = machineId,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
		return
	end

	model:SetAttribute("state", "Idle")
	debugutil.log("machine", "state", "relocated", {
		machineId = machineId,
		gridx = payload.gridx,
		gridz = payload.gridz,
		rot = rotation,
	})
end

remote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then return end

	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return
	end

	if payload.kind == "relocate" then
		handleRelocate(player, payload, islandid)
		return
	end

	local gridx = payload.gridx
	local gridz = payload.gridz

	-- permission gate (existing system)
	local allowed = PlacementPermission.canPlace({
		player = player,
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		machineType = payload.machineType,
		tier = payload.tier,
	})

	if not allowed then
		return
	end

	MachineSpawn.SpawnMachine({
		ownerUserId = player.UserId,
		machineType = payload.machineType,
		tier = payload.tier,
		gridx = gridx,
		gridz = gridz,
		rotation = payload.rotation or 0,
	})
end)
