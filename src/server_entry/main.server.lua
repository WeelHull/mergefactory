local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(game.ServerScriptService.Server.debugutil)
local islandcontroller = require(game.ServerScriptService.Server.islandcontroller)
local unlockcontroller = require(game.ServerScriptService.Server.unlockcontroller)
local PlacementPermission = require(game.ServerScriptService.Server.modules.PlacementPermission)

local START_GRIDX = 1
local START_GRIDZ = 1
local HRP_TIMEOUT = 5

local function findIslandSpawn(islandid)
	local islandsFolder = workspace:FindFirstChild("islands")
	if not islandsFolder then
		return nil
	end

	for _, model in ipairs(islandsFolder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("islandid") == islandid then
			return model:FindFirstChild("spawn")
		end
	end

	return nil
end

local function teleportToSpawn(player, islandid, character)
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", HRP_TIMEOUT)
	if not hrp then
		return
	end

	local spawnPart = findIslandSpawn(islandid)
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return
	end

	debugutil.log("lifecycle", "state", "character spawned", {
		userid = player.UserId,
		islandid = islandid,
	})

	hrp.CFrame = spawnPart.CFrame

	debugutil.log("lifecycle", "state", "teleported to spawn", {
		userid = player.UserId,
		islandid = islandid,
	})
end

local function ensureStartUnlocked(player)
	debugutil.log("lifecycle", "state", "player joined", {
		userid = player.UserId,
	})

	-- Wait for island assignment from islandcontroller
	local islandid
	while islandid == nil do
		islandid = islandcontroller.getIslandForPlayer(player)
		if islandid then
			break
		end
		task.wait()
	end

	debugutil.log("lifecycle", "state", "island ready", {
		userid = player.UserId,
		islandid = islandid,
	})

	player:SetAttribute("islandid", islandid)
	debugutil.log("lifecycle", "state", "islandid set", {
		userid = player.UserId,
		islandid = islandid,
	})

	local unlocked = unlockcontroller.unlockTile(player, START_GRIDX, START_GRIDZ)
	if unlocked then
		debugutil.log("lifecycle", "state", "start unlocked", {
			userid = player.UserId,
			islandid = islandid,
			gridx = START_GRIDX,
			gridz = START_GRIDZ,
		})
	else
		debugutil.log("lifecycle", "warn", "start unlock failed", {
			userid = player.UserId,
			islandid = islandid,
			gridx = START_GRIDX,
			gridz = START_GRIDZ,
			reason = "blocked or already unlocked",
		})
	end

	local function onCharacterAdded(character)
		teleportToSpawn(player, islandid, character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(ensureStartUnlocked)

-- client unlock intent handler (server-authoritative)
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local remotes = sharedFolder:WaitForChild("remotes")
local tileunlockEvent = remotes:WaitForChild("tileunlock")
local canPlaceFunction = remotes:WaitForChild("canPlaceOnTile")

local function onTileUnlock(player, gridx, gridz)
	debugutil.log("interaction", "decision", "tile unlock intent", {
		userid = player.UserId,
		gridx = gridx,
		gridz = gridz,
	})

	local gx = tonumber(gridx)
	local gz = tonumber(gridz)
	if not gx or not gz then
		debugutil.log("interaction", "warn", "tile unlock invalid coords", {
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
		})
		return
	end

	local success = unlockcontroller.unlockTile(player, gx, gz)
	if success then
		debugutil.log("interaction", "state", "tile unlock success", {
			userid = player.UserId,
			gridx = gx,
			gridz = gz,
		})
		tileunlockEvent:FireClient(player, {
			success = true,
			gridx = gx,
			gridz = gz,
		})
	else
		debugutil.log("interaction", "warn", "tile unlock blocked", {
			userid = player.UserId,
			gridx = gx,
			gridz = gz,
			reason = "blocked",
		})
		tileunlockEvent:FireClient(player, {
			success = false,
			gridx = gx,
			gridz = gz,
			reason = "blocked",
		})
	end
end

tileunlockEvent.OnServerEvent:Connect(onTileUnlock)

canPlaceFunction.OnServerInvoke = function(player, tile)
	local allowed, reason = PlacementPermission.CanPlaceOnTile(player, tile)
	debugutil.log("placement", "decision", "canPlaceOnTile result", {
		userid = player.UserId,
		tile = tile,
		allowed = allowed,
		reason = reason,
	})
	return allowed, reason
end
