-- machinespawn: server-authoritative machine spawning (atomic, no UX/remotes).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local gridregistry = require(ServerScriptService.Server.gridregistry)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)

local machinespawn = {}

local VALID_ROTATION = {
	[0] = true,
	[90] = true,
	[180] = true,
	[360] = true,
}

local initLogged = false

local function warn(reason, data)
	debug.log("machine", "warn", "spawn rejected", data and table.clone(data) or { reason = reason })
end

local function errorLog(reason, data)
	debug.log("machine", "error", "spawn failed", data and table.clone(data) or { reason = reason })
end

local function decision(data)
	debug.log("machine", "decision", "spawn requested", data)
end

local function state(data)
	debug.log("machine", "state", "spawned", data)
end

local function getIslandId(ownerUserId)
	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player then
		return nil
	end

	local islandid = player:GetAttribute("islandid")
	if typeof(islandid) == "number" then
		return islandid
	end

	return nil
end

local function resolveTile(islandid, gridx, gridz)
	local tileEntry = gridregistry.getTile(islandid, gridx, gridz)
	if not tileEntry then
		return nil, "tile_missing"
	end

	if tileEntry.unlocked ~= true then
		return nil, "tile_locked"
	end

	if not tileEntry.part or not tileEntry.part:IsA("BasePart") then
		return nil, "tile_invalid"
	end

	return tileEntry, nil
end

local function findAsset(machineType, tier)
	local assets = ServerStorage:FindFirstChild("assets")
	if not assets then
		return nil
	end

	local machinesRoot = assets:FindFirstChild("machines")
	if not machinesRoot then
		return nil
	end

	local typeFolder = machinesRoot:FindFirstChild(machineType)
	if not typeFolder then
		return nil
	end

	local tiersFolder = typeFolder:FindFirstChild("tiers")
	if not tiersFolder then
		return nil
	end

	local model = tiersFolder:FindFirstChild("tier_" .. tostring(tier))
	if model and model:IsA("Model") then
		return model
	end

	return nil
end

function machinespawn.SpawnMachine(params)
	if typeof(params) ~= "table" then
		return false, "invalid_params"
	end

	local ownerUserId = params.ownerUserId
	local machineType = params.machineType
	local tier = params.tier
	local gridx = params.gridx
	local gridz = params.gridz
	local rotation = params.rotation

	if not initLogged then
		initLogged = true
		debug.log("machine", "init", "machinespawn ready")
	end

	decision({
		userid = ownerUserId,
		type = machineType,
		tier = tier,
		gridx = gridx,
		gridz = gridz,
		rot = rotation,
	})

	if typeof(ownerUserId) ~= "number" or typeof(machineType) ~= "string" or typeof(tier) ~= "number" or typeof(gridx) ~= "number" or typeof(gridz) ~= "number" or typeof(rotation) ~= "number" then
		warn("invalid_args", {
			reason = "invalid_args",
			userid = ownerUserId,
			gridx = gridx,
			gridz = gridz,
		})
		return false, "invalid_args"
	end

	if not VALID_ROTATION[rotation] then
		warn("invalid_rotation", {
			reason = "invalid_rotation",
			userid = ownerUserId,
			rot = rotation,
		})
		return false, "invalid_rotation"
	end

	local islandid = getIslandId(ownerUserId)
	if islandid == nil then
		warn("island_missing", {
			reason = "island_missing",
			userid = ownerUserId,
		})
		return false, "island_missing"
	end

	local tileEntry, tileErr = resolveTile(islandid, gridx, gridz)
	if not tileEntry then
		warn(tileErr, {
			reason = tileErr,
			userid = ownerUserId,
			gridx = gridx,
			gridz = gridz,
		})
		return false, tileErr
	end

	local occupied, existingId = MachineRegistry.IsTileOccupied(islandid, gridx, gridz)
	if occupied then
		warn("occupied", {
			reason = "occupied",
			userid = ownerUserId,
			gridx = gridx,
			gridz = gridz,
			machineid = existingId,
		})
		return false, "occupied"
	end

	local asset = findAsset(machineType, tier)
	if not asset then
		warn("asset_missing", {
			reason = "asset_missing",
			userid = ownerUserId,
			type = machineType,
			tier = tier,
		})
		return false, "asset_missing"
	end

	if not asset.PrimaryPart then
		warn("asset_primary_missing", {
			reason = "asset_primary_missing",
			type = machineType,
			tier = tier,
		})
		return false, "asset_primary_missing"
	end

	local clone
	local success, cloneResult = pcall(function()
		return asset:Clone()
	end)

	if success then
		clone = cloneResult
	else
		errorLog("clone_failed", {
			reason = "clone_failed",
			type = machineType,
			tier = tier,
		})
		return false, "clone_failed"
	end

	if not clone.PrimaryPart then
		clone:Destroy()
		warn("clone_primary_missing", {
			reason = "clone_primary_missing",
			type = machineType,
			tier = tier,
		})
		return false, "clone_primary_missing"
	end

	clone.PrimaryPart.Anchored = true

	local rotationCF = CFrame.Angles(0, math.rad(rotation), 0)
	clone:SetPrimaryPartCFrame(CFrame.new(tileEntry.part.Position) * rotationCF)

	clone:SetAttribute("machineType", machineType)
	clone:SetAttribute("tier", tier)
	clone:SetAttribute("ownerUserId", ownerUserId)
	clone:SetAttribute("gridx", gridx)
	clone:SetAttribute("gridz", gridz)
	clone:SetAttribute("rotation", rotation)
	clone:SetAttribute("state", "Idle")

	local machinesFolder = workspace:FindFirstChild("machines")
	if not machinesFolder then
		machinesFolder = Instance.new("Folder")
		machinesFolder.Name = "machines"
		machinesFolder.Parent = workspace
	end

	clone.Parent = machinesFolder

	local machineId = MachineRegistry.RegisterMachine(clone, ownerUserId)
	if not machineId then
		clone:Destroy()
		errorLog("register_failed", {
			reason = "register_failed",
			userid = ownerUserId,
		})
		return false, "register_failed"
	end

	clone:SetAttribute("machineId", machineId)

	local bound = MachineRegistry.BindTile(machineId, islandid, gridx, gridz)
	if not bound then
		MachineRegistry.unregister(machineId)
		clone:Destroy()
		errorLog("bind_failed", {
			reason = "bind_failed",
			userid = ownerUserId,
			gridx = gridx,
			gridz = gridz,
		})
		return false, "bind_failed"
	end

	state({
		machineid = machineId,
		userid = ownerUserId,
		gridx = gridx,
		gridz = gridz,
		rot = rotation,
	})

	return true, machineId
end

return machinespawn
