-- UnlockController: island-scoped tile unlocks using gridregistry.

local debug = require(script.Parent.debugutil)
debug.log("boot", "unlock", "loaded", { module = "unlockcontroller" })
local gridregistry = require(script.Parent.gridregistry)
local unlockrules = require(script.Parent.unlockrules)
local islandcontroller = require(script.Parent.islandcontroller)

local UnlockController = {}

debug.log("unlock", "init", "module init")
debug.log("boot", "unlock", "init start", { module = "unlockcontroller" })
debug.log("boot", "unlock", "init end", { module = "unlockcontroller" })

local function warn(message, data)
	debug.log("unlock", "warn", message, data)
end

local function decision(message, data)
	debug.log("unlock", "decision", message, data)
end

local function state(message, data)
	debug.log("unlock", "state", message, data)
end

function UnlockController.isUnlocked(islandid, gridx, gridz)
	decision("isUnlocked called", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
	})

	return gridregistry.isUnlocked(islandid, gridx, gridz)
end

function UnlockController.unlockTile(player, gridx, gridz)
	decision("unlockTile called", {
		userid = player and player.UserId or nil,
		gridx = gridx,
		gridz = gridz,
	})

	if not player then
		warn("unlock failed", {
			reason = "missing player",
			gridx = gridx,
			gridz = gridz,
		})
		return false
	end

	local playerIsland = islandcontroller.getIslandForPlayer(player)

	decision("resolve ownership", {
		userid = player.UserId,
		islandid = playerIsland,
	})

	if not playerIsland then
		warn("unlock failed", {
			reason = "no island assigned",
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
		})
		return false
	end

	local islandid = playerIsland

	local allowed, reason = unlockrules.canUnlock(gridx, gridz, islandid)
	if not allowed then
		warn("unlock failed", {
			reason = reason or "blocked",
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			userid = player.UserId,
		})
		return false
	end

	local success = gridregistry.setUnlocked(islandid, gridx, gridz, true)
	if not success then
		local entry = gridregistry.getTile(islandid, gridx, gridz)
		local failReason = "missing"
		if entry and entry.unlocked == true then
			failReason = "already unlocked"
		end

		warn("unlock failed", {
			reason = failReason,
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			userid = player.UserId,
		})
		return false
	end

	state("tile unlocked", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		userid = player.UserId,
	})

	return true
end

return UnlockController
