-- auto_tiles: server-authoritative single-step tile unlocking and manual batch remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debugutil = require(ServerScriptService.Server.debugutil)
local gridregistry = require(ServerScriptService.Server.gridregistry)
local unlockrules = require(ServerScriptService.Server.unlockrules)
local unlockcontroller = require(ServerScriptService.Server.unlockcontroller)
local IslandValidator = require(ServerScriptService.Server.islandvalidator)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

local AutoTiles = {}

local function keyFor(x, z)
	return tostring(x) .. ":" .. tostring(z)
end

local function collectUnlocked(islandid)
	local unlockedSet = {}
	local unlockedList = {}
	for _, entry in ipairs(gridregistry.getUnlockedTiles(islandid)) do
		local gx = tonumber(entry.gridx) or (entry.part and tonumber(entry.part:GetAttribute("gridx")))
		local gz = tonumber(entry.gridz) or (entry.part and tonumber(entry.part:GetAttribute("gridz")))
		if gx and gz then
			local key = keyFor(gx, gz)
			if not unlockedSet[key] then
				unlockedSet[key] = true
				table.insert(unlockedList, { gridx = gx, gridz = gz })
			end
		end
	end
	return unlockedSet, unlockedList
end

local function addNeighbors(base, candidates, candidateSet, unlockedSet, cps, discount, islandid)
	local offsets = {
		{ 1, 0 },
		{ -1, 0 },
		{ 0, 1 },
		{ 0, -1 },
	}
	for _, off in ipairs(offsets) do
		local gx = base.gridx + off[1]
		local gz = base.gridz + off[2]
		local key = keyFor(gx, gz)
		if not unlockedSet[key] and not candidateSet[key] then
			local entry = gridregistry.getTile(islandid, gx, gz)
			if entry and entry.unlocked ~= true then
				local price = EconomyConfig.GetTilePrice(gx, gz, cps, discount)
				local dist = math.abs(gx - 1) + math.abs(gz - 1)
				candidateSet[key] = true
				table.insert(candidates, {
					gridx = gx,
					gridz = gz,
					price = price,
					dist = dist,
				})
			end
		end
	end
end

local function cheapestCandidate(islandid, cps, discount)
	local unlockedSet, unlockedList = collectUnlocked(islandid)
	if #unlockedList == 0 then
		return nil
	end
	local candidateSet = {}
	local best
	for _, u in ipairs(unlockedList) do
		local candidates = {}
		addNeighbors(u, candidates, candidateSet, unlockedSet, cps, discount, islandid)
		for _, cand in ipairs(candidates) do
			if not best or cand.price < best.price or (cand.price == best.price and cand.dist < best.dist) then
				best = cand
			end
		end
	end
	return best
end

local function handleRequest(player)
	return AutoTiles.UnlockOne(player)
end

function AutoTiles.Init()
	local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
	local requestFn = remotes:FindFirstChild("auto_tiles_request") or Instance.new("RemoteFunction")
	requestFn.Name = "auto_tiles_request"
	requestFn.Parent = remotes

	requestFn.OnServerInvoke = function(player)
		return handleRequest(player)
	end

	debugutil.log("autotiles", "init", "auto_tiles ready", {})
end

function AutoTiles.NextPrice(player)
	if not player then
		return nil
	end
	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return nil
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	local discount = player:GetAttribute("RebirthTileDiscount") or 0
	local cand = cheapestCandidate(islandid, cps, discount)
	return cand and cand.price or nil
end

function AutoTiles.UnlockOne(player)
	if not player then
		return { success = false, reason = "no_player" }
	end
	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return { success = false, reason = "invalid_island" }
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	local discount = player:GetAttribute("RebirthTileDiscount") or 0
	local cand = cheapestCandidate(islandid, cps, discount)
	if not cand then
		return { success = false, reason = "no_unlockable" }
	end
	if cand.price > 0 and not Economy.Spend(player, cand.price) then
		return { success = false, reason = "insufficient_funds", price = cand.price }
	end
	local success = unlockcontroller.unlockTile(player, cand.gridx, cand.gridz)
	if not success then
		if cand.price > 0 then
			Economy.Grant(player, cand.price)
		end
		return { success = false, reason = "blocked" }
	end
	return { success = true, unlocked = 1, spent = cand.price }
end

return AutoTiles
