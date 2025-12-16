-- Grid registry: scans workspace islands -> grids -> tiles and builds read-only lookup.

local debug = require(script.Parent.debugutil)
debug.log("boot", "gridregistry", "loaded", { module = "gridregistry" })

local gridregistry = {}
local registry = {} -- registry[islandid][gridz][gridx] = { part = BasePart, unlocked = boolean }
local LOCKED_COLOR = Color3.fromRGB(180, 60, 60)
local UNLOCKED_COLOR = Color3.fromRGB(80, 180, 80)
local VERBOSE = false

local function applyVisual(part, unlocked)
	if not part or not part:IsA("BasePart") then
		return
	end

	if unlocked == true then
		part.Color = UNLOCKED_COLOR
	else
		part.Color = LOCKED_COLOR
	end
end

function gridregistry.applyvisuals(islandid)
	local islandCount = 0
	local unlockedCount = 0
	local lockedCount = 0

	local function applyIsland(key, islandGrid)
		islandCount += 1
		for _, zRow in pairs(islandGrid) do
			for _, entry in pairs(zRow) do
				applyVisual(entry.part, entry.unlocked)
				if entry.unlocked then
					unlockedCount += 1
				else
					lockedCount += 1
				end
			end
		end
	end

	if islandid ~= nil then
		local islandGrid = registry[tostring(islandid)]
		if not islandGrid then
			return
		end
		applyIsland(islandid, islandGrid)
	else
		for key, islandGrid in pairs(registry) do
			applyIsland(key, islandGrid)
		end
	end

	debug.log("gridregistry", "state", "visuals applied", {
		islands = islandCount,
		unlocked = unlockedCount,
		locked = lockedCount,
	})
end

local function warn(message, data)
	debug.log("gridregistry", "warn", message, data)
end

local function readTileAttributes(tile)
	local gridx = tile:GetAttribute("gridx")
	local gridz = tile:GetAttribute("gridz")
	local unlockedAttr = tile:GetAttribute("unlocked")

	local missing = gridx == nil or gridz == nil or unlockedAttr == nil
	local typesValid = typeof(gridx) == "number" and typeof(gridz) == "number" and typeof(unlockedAttr) == "boolean"

	if missing or not typesValid then
		warn("tile attributes missing or invalid", {
			tile = tile,
			gridx = gridx,
			gridz = gridz,
			unlocked = unlockedAttr,
		})
		return nil
	end

	if VERBOSE then
		debug.log("gridregistry", "state", "unlocked state read", {
			tile = tile,
			gridx = gridx,
			gridz = gridz,
			unlocked = unlockedAttr,
		})
	end

	applyVisual(tile, unlockedAttr)

	return {
		part = tile,
		gridx = gridx,
		gridz = gridz,
		unlocked = unlockedAttr,
	}
end

local function buildRegistry()
	local islandsFolder = workspace:FindFirstChild("islands")
	if not islandsFolder then
		warn("workspace.islands missing")
		return
	end

	local islands = islandsFolder:GetChildren()
	table.sort(islands, function(a, b)
		return a.Name < b.Name
	end)

	local islandsProcessed = 0
	local totalTiles = 0
	local tilesPerIsland = 0

	for _, island in ipairs(islands) do
		if not island:IsA("Model") then
			warn("island skipped", { reason = "non-model", island = island })
			continue
		end

		local islandid = island:GetAttribute("islandid")
		if islandid == nil then
			warn("island skipped", { reason = "missing islandid", island = island })
			continue
		end

		local islandKey = tostring(islandid)
		registry[islandKey] = registry[islandKey] or {}

		local gridFolder = island:FindFirstChild("grid")
		if not gridFolder or not gridFolder:IsA("Folder") then
			warn("island skipped", {
				reason = "missing grid",
				islandid = islandid,
				island = island,
			})
			continue
		end

		local tiles = gridFolder:GetChildren()
		table.sort(tiles, function(a, b)
			return a.Name < b.Name
		end)

		local added = 0
		for _, tile in ipairs(tiles) do
			if tile:IsA("BasePart") then
				local entry = readTileAttributes(tile)
				if entry then
					registry[islandKey][entry.gridz] = registry[islandKey][entry.gridz] or {}
					registry[islandKey][entry.gridz][entry.gridx] = {
						part = entry.part,
						unlocked = entry.unlocked,
					}
					added += 1
				end
			else
				warn("non-BasePart tile ignored", { tile = tile, islandid = islandid })
			end
		end

		islandsProcessed += 1
		totalTiles += added
	end

	if islandsProcessed > 0 then
		tilesPerIsland = totalTiles / islandsProcessed
	end

	debug.log("gridregistry", "init", "island grids built", {
		islands = islandsProcessed,
		tiles_per_island = tilesPerIsland,
		total_tiles = totalTiles,
	})

	gridregistry.applyvisuals()
end

function gridregistry.getTile(islandid, gridx, gridz)
	debug.log("gridregistry", "decision", "getTile called", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
	})

	local islandGrid = registry[tostring(islandid)]
	if not islandGrid then
		return nil
	end

	local zx = tonumber(gridx)
	local zz = tonumber(gridz)
	if not zx or not zz then
		return nil
	end

	local zRow = islandGrid[zz]
	if not zRow then
		return nil
	end

	return zRow[zx]
end

function gridregistry.isUnlocked(islandid, gridx, gridz)
	debug.log("gridregistry", "decision", "isUnlocked called", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
	})

	local entry = gridregistry.getTile(islandid, gridx, gridz)
	if not entry then
		return false
	end

	return entry.unlocked == true
end

function gridregistry.setUnlocked(islandid, gridx, gridz, value)
	debug.log("gridregistry", "decision", "setUnlocked called", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		value = value,
	})

	if value ~= true then
		return false
	end

	local entry = gridregistry.getTile(islandid, gridx, gridz)
	if not entry then
		warn("tile not found", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
		})
		return false
	end

	if entry.unlocked == value then
		return false
	end

	entry.unlocked = true
	entry.part:SetAttribute("unlocked", true)
	applyVisual(entry.part, true)

	debug.log("gridregistry", "state", "unlocked set", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		value = true,
	})

	return true
end

buildRegistry()

return gridregistry
