local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local machinespawn = require(ServerScriptService.Server.machinespawn)

local MergeSystem = {}
local MAX_TIER = 10

-- Placeholder: placement mode is client-driven and not surfaced to the server yet.
-- Guard remains explicit for future wiring; currently returns false (not active).
local function isPlacementActive()
	return false
end

local function findIslandForMachine(machineId)
	local dump = MachineRegistry.__debugDump()
	local occupancy = dump and dump.occupancy
	if type(occupancy) ~= "table" then
		return nil
	end
	for islandKey, zRows in pairs(occupancy) do
		for _, xRow in pairs(zRows) do
			for _, id in pairs(xRow) do
				if id == machineId then
					local numericIsland = tonumber(islandKey)
					return numericIsland
				end
			end
		end
	end
	return nil
end

local function canMergeInternal(machineAId, machineBId)
	if isPlacementActive() then
		debug.log("merge", "decision", "deny", { reason = "placement_active" })
		return false, "placement_active"
	end

	if typeof(machineAId) ~= "string" or machineAId == "" or typeof(machineBId) ~= "string" or machineBId == "" then
		debug.log("merge", "decision", "deny", { reason = "invalid_id" })
		return false, "invalid_id"
	end

	if machineAId == machineBId then
		debug.log("merge", "decision", "deny", { reason = "same_machine", machineA = machineAId, machineB = machineBId })
		return false, "same_machine"
	end

	local modelA = MachineRegistry.get(machineAId)
	local modelB = MachineRegistry.get(machineBId)
	if not modelA or not modelB then
		debug.log("merge", "decision", "deny", { reason = "machine_not_found", machineA = machineAId, machineB = machineBId })
		return false, "machine_not_found"
	end

	local ownerA = modelA:GetAttribute("ownerUserId")
	local ownerB = modelB:GetAttribute("ownerUserId")
	if typeof(ownerA) ~= "number" or typeof(ownerB) ~= "number" or ownerA ~= ownerB then
		debug.log("merge", "decision", "deny", { reason = "owner_mismatch", machineA = machineAId, machineB = machineBId })
		return false, "owner_mismatch"
	end

	local typeA = modelA:GetAttribute("machineType")
	local typeB = modelB:GetAttribute("machineType")
	if typeA ~= typeB then
		debug.log("merge", "decision", "deny", { reason = "type_mismatch", typeA = typeA, typeB = typeB })
		return false, "type_mismatch"
	end

	local islandA = findIslandForMachine(machineAId)
	local islandB = findIslandForMachine(machineBId)
	if islandA == nil or islandB == nil or islandA ~= islandB then
		debug.log("merge", "decision", "deny", { reason = "different_island", islandA = islandA, islandB = islandB })
		return false, "different_island"
	end

	local tierA = modelA:GetAttribute("tier")
	local tierB = modelB:GetAttribute("tier")
	if tierA ~= tierB then
		debug.log("merge", "decision", "deny", { reason = "tier_mismatch", tierA = tierA, tierB = tierB })
		return false, "tier_mismatch"
	end

	if typeof(tierA) == "number" and tierA >= MAX_TIER then
		debug.log("merge", "decision", "deny", {
			reason = "tier_cap",
			tier = tierA,
			max = MAX_TIER,
		})
		return false, "tier_cap"
	end

	debug.log("merge", "decision", "relocate_merge_allowed", {
		machineA = machineAId,
		machineB = machineBId,
		type = typeA,
		tier = tierA,
	})
	return true, "ok"
end

function MergeSystem.CanMerge(machineAId, machineBId)
	return canMergeInternal(machineAId, machineBId)
end

function MergeSystem.RequestMerge(player, machineAId, machineBId)
	local allowed, reason = canMergeInternal(machineAId, machineBId)
	if not allowed then
		return false, reason
	end

	debug.log("merge", "state", "request_received", {
		userid = player and player.UserId,
		machineA = machineAId,
		machineB = machineBId,
	})
	return true, "ok"
end

function MergeSystem.ExecuteMerge(machineAId, machineBId)
	local allowed, reason = canMergeInternal(machineAId, machineBId)
	if not allowed then
		return false, reason
	end

	local modelA = MachineRegistry.get(machineAId)
	local modelB = MachineRegistry.get(machineBId)
	if not modelA or not modelB then
		debug.log("merge", "warn", "execute_failed", { reason = "models_missing" })
		return false, "models_missing"
	end

	local ownerId = modelA:GetAttribute("ownerUserId")
	local machineType = modelA:GetAttribute("machineType")
	local tier = modelA:GetAttribute("tier")
	local newTier = tier and tier + 1 or 1
	if typeof(tier) == "number" and tier >= MAX_TIER then
		debug.log("merge", "warn", "execute_failed", {
			reason = "tier_cap",
			tier = tier,
			max = MAX_TIER,
		})
		return false, "tier_cap"
	end

	local gridx = modelB:GetAttribute("gridx")
	local gridz = modelB:GetAttribute("gridz")
	local rotation = modelB:GetAttribute("rotation") or 0
	local islandid = findIslandForMachine(machineBId)

	-- Unbind and destroy old machines
	MachineRegistry.UnbindTile(machineAId)
	MachineRegistry.UnbindTile(machineBId)
	MachineRegistry.unregister(machineAId)
	MachineRegistry.unregister(machineBId)
	modelA:Destroy()
	modelB:Destroy()

	local spawned, newId = machinespawn.SpawnMachine({
		ownerUserId = ownerId,
		machineType = machineType,
		tier = newTier,
		gridx = gridx,
		gridz = gridz,
		rotation = rotation,
	})

	debug.log("merge", "state", "relocate_merge_execute", {
		source = machineAId,
		target = machineBId,
		tier = newTier,
		result = spawned,
		newMachineId = newId,
	})

	return spawned, newId
end

return MergeSystem
