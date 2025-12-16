-- unlockrules: centralized unlock gating logic.

local debug = require(script.Parent.debugutil)
local gridregistry = require(script.Parent.gridregistry)

local unlockrules = {}

local WHITELIST = {
	["1:1_1"] = true,
	["2:1_1"] = true,
}

local function decision(message, data)
	debug.log("unlockrules", "decision", message, data)
end

local function warn(message, data)
	debug.log("unlockrules", "warn", message, data)
end

function unlockrules.canUnlock(gridx, gridz, islandid)
	decision("canUnlock called", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
	})

	if gridx == 1 and gridz == 1 then
		decision("start tile allowed", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			cost = 0,
		})
		return true, "start", 0
	end

	local key = string.format("%s:%s_%s", tostring(islandid), tostring(gridx), tostring(gridz))

	decision("whitelist key computed", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		key = key,
	})

	local allowed = WHITELIST[key] == true

	if allowed then
		return true, "ok", 0
	end

	local neighbors = {
		{ x = gridx + 1, z = gridz },
		{ x = gridx - 1, z = gridz },
		{ x = gridx, z = gridz + 1 },
		{ x = gridx, z = gridz - 1 },
	}

	for _, n in ipairs(neighbors) do
		local entry = gridregistry.getTile(islandid, n.x, n.z)
		if entry and entry.unlocked == true then
			decision("adjacency allowed", {
				islandid = islandid,
				gridx = gridx,
				gridz = gridz,
				cost = 0,
			})
			return true, "ok", 0
		end
	end

	warn("unlock blocked", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		reason = "not whitelisted or adjacent",
		key = key,
	})

	return false, "not adjacent", 0
end

return unlockrules
