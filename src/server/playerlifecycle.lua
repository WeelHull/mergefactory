-- playerlifecycle: initializes player progression safely (session-only).

local Players = game:GetService("Players")

local debug = require(script.Parent.debugutil)
debug.log("boot", "lifecycle", "loaded", { module = "playerlifecycle" })
local islandcontroller = require(script.Parent.islandcontroller)
local unlockcontroller = require(script.Parent.unlockcontroller)

debug.log("lifecycle", "init", "module ready")
debug.log("boot", "lifecycle", "init start", { module = "playerlifecycle" })

local function warn(message, data)
	debug.log("lifecycle", "warn", message, data)
end

local function decision(message, data)
	debug.log("lifecycle", "decision", message, data)
end

local function state(message, data)
	debug.log("lifecycle", "state", message, data)
end

local function ensureProgression(player)
	debug.log("boot", "lifecycle", "player added", { module = "playerlifecycle", userid = player.UserId })

	local islandid = islandcontroller.getIslandForPlayer(player)

	decision("check initial state", {
		userid = player.UserId,
		islandid = islandid,
	})

	if not islandid then
		warn("no island assigned", { userid = player.UserId })
		return
	end

	state("player joined", {
		userid = player.UserId,
		islandid = islandid,
	})

	local unlocked = unlockcontroller.unlockTile(player, 1, 1)
	if unlocked then
		state("start unlocked", {
			userid = player.UserId,
			islandid = islandid,
			gridx = 1,
			gridz = 1,
		})
	else
		warn("start unlock failed", {
			userid = player.UserId,
			islandid = islandid,
			reason = "blocked or already unlocked",
		})
	end
end

Players.PlayerAdded:Connect(ensureProgression)
debug.log("boot", "lifecycle", "hook players", { module = "playerlifecycle" })
debug.log("boot", "lifecycle", "init end", { module = "playerlifecycle" })

return {}
