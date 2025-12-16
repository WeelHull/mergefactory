-- islandcontroller: assigns islands to players at runtime (session-only).

local Players = game:GetService("Players")

local debug = require(script.Parent.debugutil)
debug.log("boot", "island", "loaded", { module = "islandcontroller" })

local islandcontroller = {}

local playerToIsland = {}
local islandToPlayer = {}

debug.log("island", "init", "controller ready")
debug.log("boot", "island", "init start", { module = "islandcontroller" })

local function warn(message, data)
	debug.log("island", "warn", message, data)
end

local function state(message, data)
	debug.log("island", "state", message, data)
end

local function collectIslands()
	local islandsFolder = workspace:FindFirstChild("islands")
	if not islandsFolder then
		warn("workspace.islands missing")
		return {}
	end

	local islands = {}
	for _, model in ipairs(islandsFolder:GetChildren()) do
		if model:IsA("Model") then
			local islandid = model:GetAttribute("islandid")
			if typeof(islandid) == "number" then
				table.insert(islands, islandid)
			else
				warn("island missing islandid", { island = model })
			end
		end
	end

	table.sort(islands)
	return islands
end

local islandsList = collectIslands()
debug.log("boot", "island", "init end", { module = "islandcontroller" })

local function findFreeIsland()
	for _, islandid in ipairs(islandsList) do
		if islandToPlayer[islandid] == nil then
			return islandid
		end
	end
	return nil
end

function islandcontroller.getIslandForPlayer(player)
	return playerToIsland[player.UserId]
end

function islandcontroller.getPlayerForIsland(islandid)
	return islandToPlayer[islandid]
end

local function assignIsland(player)
	if playerToIsland[player.UserId] ~= nil then
		return
	end

	local islandid = findFreeIsland()
	if not islandid then
		warn("no free islands", { userid = player.UserId })
		return
	end

	playerToIsland[player.UserId] = islandid
	islandToPlayer[islandid] = player.UserId

	state("assigned", { userid = player.UserId, islandid = islandid })
end

local function releaseIsland(player)
	local islandid = playerToIsland[player.UserId]
	if not islandid then
		return
	end

	playerToIsland[player.UserId] = nil
	islandToPlayer[islandid] = nil

	state("released", { userid = player.UserId, islandid = islandid })
end

Players.PlayerAdded:Connect(assignIsland)
Players.PlayerRemoving:Connect(releaseIsland)
debug.log("boot", "island", "hook players", { module = "islandcontroller" })

for _, player in ipairs(Players:GetPlayers()) do
	if not islandcontroller.getIslandForPlayer(player) then
		assignIsland(player)
		if islandcontroller.getIslandForPlayer(player) then
			state("assigned", {
				userid = player.UserId,
				islandid = islandcontroller.getIslandForPlayer(player),
				reason = "init_existing",
			})
			debug.log("boot", "island", "action", {
				module = "islandcontroller",
				detail = "init_existing",
				userid = player.UserId,
			})
		end
	end
end

return islandcontroller
