-- Handles client requests to place machines.
-- Authoritative. Minimal. No refactors.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineSpawn = require(game.ServerScriptService.Server.machinespawn)
local IslandValidator = require(game.ServerScriptService.Server.islandvalidator)
local PlacementPermission = require(game.ServerScriptService.Server.modules.placementpermission)

local remote =
	ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("remotes")
		:WaitForChild("place_machine")

remote.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then return end

	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
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
