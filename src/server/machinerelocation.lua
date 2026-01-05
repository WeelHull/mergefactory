-- machinerelocation: server-authoritative relocation of machines (atomic, no remotes/UX).

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local gridregistry = require(ServerScriptService.Server.gridregistry)
local machineregistry = require(ServerScriptService.Server.machineregistry)
local placementpermission = require(ServerScriptService.Server.modules.placementpermission)
local MergeSystem = require(ServerScriptService.Server.mergesystem)

local machinerelocation = {}

local VALID_ROTATION = {
	[0] = true,
	[90] = true,
	[180] = true,
	[270] = true,
	[360] = true,
}

local function errorLog(reason, data)
	debug.log("machine", "error", "relocate failed", data)
end

local function warnLog(reason, data)
	debug.log("machine", "warn", "relocate rejected", data)
end

local function decisionLog(data)
	debug.log("machine", "decision", "relocate requested", data)
end

local function stateLog(data)
	debug.log("machine", "state", "relocated", data)
end

local function validate(machineId, gridx, gridz, islandid, rotation)
	if typeof(machineId) ~= "string" or machineId == "" then
		return false, "invalid_machineId"
	end

	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" or typeof(islandid) ~= "number" then
		return false, "invalid_coords"
	end

	if not VALID_ROTATION[rotation] then
		return false, "invalid_rotation"
	end

	local model = machineregistry.get(machineId)
	if not model then
		return false, "machine_not_found"
	end

	local sourceGridX = model:GetAttribute("gridx")
	local sourceGridZ = model:GetAttribute("gridz")
	if typeof(sourceGridX) ~= "number" or typeof(sourceGridZ) ~= "number" then
		return false, "machine_missing_attrs"
	end

	local occupied, occupyingId = machineregistry.IsTileOccupied(islandid, sourceGridX, sourceGridZ)
	if not occupied or occupyingId ~= machineId then
		return false, "machine_not_bound"
	end

	local targetTile = gridregistry.getTile(islandid, gridx, gridz)
	if not targetTile then
		return false, "tile_missing"
	end

	if targetTile.unlocked ~= true then
		return false, "tile_locked"
	end

	local targetOccupied, occupantId = machineregistry.IsTileOccupied(islandid, gridx, gridz)

	local ownerUserId = model:GetAttribute("ownerUserId")
	if typeof(ownerUserId) ~= "number" then
		return false, "owner_missing"
	end

	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player then
		return false, "owner_not_present"
	end

	local allowed, reason = placementpermission.CanPlaceOnTile(player, targetTile.part, machineId)
	if not allowed then
		return false, "placement_denied_" .. tostring(reason or "unknown")
	end

	return true, {
		model = model,
		sourceGridX = sourceGridX,
		sourceGridZ = sourceGridZ,
		ownerUserId = ownerUserId,
		targetTile = targetTile,
		targetOccupantId = occupantId,
	}
end

function machinerelocation.CanRelocate(machineId, gridx, gridz, islandid, rotation)
	local ok, result = validate(machineId, gridx, gridz, islandid, rotation)
	return ok, ok and "ok" or result
end

function machinerelocation.Relocate(machineId, gridx, gridz, islandid, rotation)
	decisionLog({
		machineid = machineId,
		gridx = gridx,
		gridz = gridz,
		islandid = islandid,
		rotation = rotation,
	})

	local ok, ctx = validate(machineId, gridx, gridz, islandid, rotation)
	if not ok then
		warnLog(ctx, {
			machineid = machineId,
			gridx = gridx,
			gridz = gridz,
			islandid = islandid,
			rotation = rotation,
			reason = ctx,
		})
		return false, ctx
	end

	if ctx.targetOccupantId and ctx.targetOccupantId ~= machineId then
		local canMerge, mergeReason = MergeSystem.CanMerge(machineId, ctx.targetOccupantId)
		debug.log("merge", "decision", "relocate_merge_check", {
			moving = machineId,
			target = ctx.targetOccupantId,
			allowed = canMerge,
			reason = mergeReason,
		})
		if canMerge then
			local executed, execReason = MergeSystem.ExecuteMerge(machineId, ctx.targetOccupantId)
			debug.log("merge", "state", "relocate_merge_executed", {
				source = machineId,
				target = ctx.targetOccupantId,
			})
			debug.log("machine", "state", "relocate_aborted", {
				reason = "merge_executed",
				machineId = machineId,
			})
			return executed, execReason
		else
			return false, "tile_occupied"
		end
	end

	-- Step 2: unbind from source
	local unbound = machineregistry.UnbindTile(machineId)
	if not unbound then
		errorLog("unbind_failed", {
			machineid = machineId,
			gridx = ctx.sourceGridX,
			gridz = ctx.sourceGridZ,
		})
		return false, "unbind_failed"
	end

	-- Step 4: bind to target
	local bound = machineregistry.BindTile(machineId, islandid, gridx, gridz)
	if not bound then
		-- rollback: rebind to source tile
		machineregistry.BindTile(machineId, islandid, ctx.sourceGridX, ctx.sourceGridZ)
		errorLog("bind_failed", {
			machineid = machineId,
			gridx = gridx,
			gridz = gridz,
		})
		return false, "bind_failed"
	end

	-- Step 6: apply transform
	local model = ctx.model
	local targetPart = ctx.targetTile.part
	local rotationCF = CFrame.Angles(0, math.rad(rotation), 0)
	if model.PrimaryPart then
		model.PrimaryPart.Anchored = true
		model:SetPrimaryPartCFrame(CFrame.new(targetPart.Position) * rotationCF)
	end

	model:SetAttribute("gridx", gridx)
	model:SetAttribute("gridz", gridz)
	model:SetAttribute("rotation", rotation)

	stateLog({
		machineid = machineId,
		gridx = gridx,
		gridz = gridz,
		islandid = islandid,
		rotation = rotation,
	})

	return true, "ok"
end

return machinerelocation
