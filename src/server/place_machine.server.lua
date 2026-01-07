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
local MergeSystem = require(ServerScriptService.Server.mergesystem)
local MergeController = require(ServerScriptService.Server.mergecontroller)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local Inventory = require(ServerScriptService.Server.inventory)

local remote =
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("remotes")
		:WaitForChild("place_machine")

local ALLOWED_MACHINES = {
	generator = { minTier = 1, maxTier = 10 },
}

local VALID_ROTATION = {
	[0] = true,
	[90] = true,
	[180] = true,
	[270] = true,
	[360] = true,
}

local function isAllowedMachine(machineType, tier)
	local rule = ALLOWED_MACHINES[machineType]
	if not rule or typeof(tier) ~= "number" then
		return false
	end
	local t = math.floor(tier)
	return t >= (rule.minTier or 1) and t <= (rule.maxTier or t)
end

local function normalizeRotation(rotation)
	if typeof(rotation) ~= "number" then
		return 0
	end
	local r = ((rotation % 360) + 360) % 360
	if VALID_ROTATION[r] then
		return r
	end
	return 0
end

local function ensurePaid(player, machineType, tier)
	-- First attempt to consume server-side inventory grant (starter item).
	if Inventory.Consume(player.UserId, machineType, tier, 1) then
		return true
	end

	local cps = player:GetAttribute("CashPerSecond") or 0
	local price = EconomyConfig.GetMachinePrice(machineType, tier, cps)
	if price <= 0 then
		return true
	end

	local spent = Economy.Spend(player, price)
	if not spent then
		debugutil.log("machine", "warn", "placement_rejected_insufficient", {
			userid = player.UserId,
			machineType = machineType,
			tier = tier,
			price = price,
			cash = Economy.GetCash(player),
		})
		return false
	end

	return true
end

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
		ignoreMachineId = machineId,
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

	local occupied, occupantId = MachineRegistry.IsTileOccupied(islandid, payload.gridx, payload.gridz)
	if occupied and occupantId ~= machineId then
		local canMerge, mergeReason = MergeSystem.CanMerge(machineId, occupantId)
		debugutil.log("merge", "decision", "relocate_merge_check", {
			moving = machineId,
			target = occupantId,
			allowed = canMerge,
			reason = mergeReason,
		})
		if canMerge then
			local targetModel = MachineRegistry.get(occupantId)
			local machineType = targetModel and targetModel:GetAttribute("machineType")
			local tier = targetModel and targetModel:GetAttribute("tier")
			MergeController.SendMergeOffer(player, machineId, occupantId, machineType, tier)
			return
		end
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
		if moveReason ~= "merge_offer" then
			debugutil.log("machine", "warn", "relocate_rejected", {
				reason = moveReason,
				machineId = machineId,
				gridx = payload.gridx,
				gridz = payload.gridz,
			})
		end
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

	local machineType = payload.machineType
	local tier = math.floor(tonumber(payload.tier) or 0)

	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return
	end

	if not isAllowedMachine(machineType, tier) then
		debugutil.log("machine", "warn", "placement_rejected", {
			reason = "invalid_machine",
			machineType = machineType,
			tier = payload.tier,
			userid = player.UserId,
		})
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

	if not ensurePaid(player, machineType, tier) then
		return
	end

	MachineSpawn.SpawnMachine({
		ownerUserId = player.UserId,
		machineType = machineType,
		tier = tier,
		gridx = gridx,
		gridz = gridz,
		rotation = normalizeRotation(payload.rotation or 0),
	})
end)
