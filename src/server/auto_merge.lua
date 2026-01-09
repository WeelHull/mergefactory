-- auto_merge: server-authoritative single-step merges and batch remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debugutil = require(ServerScriptService.Server.debugutil)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local MergeSystem = require(ServerScriptService.Server.mergesystem)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local AutoAccess = require(ServerScriptService.Server.modules.autoaccess)

local AutoMerge = {}
local lastRequestAt = {}
local REQUEST_COOLDOWN = 0.5 -- seconds between auto merge requests per player

local function computeMergePrice(tier, player)
	local nextTier = math.max(1, (tier or 0) + 1)
	local cps = player and player:GetAttribute("CashPerSecond") or 0
	local base = EconomyConfig.GetMachinePrice("generator", nextTier, cps)
	return math.max(0, math.floor(base * 0.8))
end

local function findPair(player)
	local userId = player.UserId
	local tiers = {}
	local byTier = {}
	for _, id in ipairs(MachineRegistry.getIdsForOwner(userId)) do
		local model = MachineRegistry.get(id)
		if model then
			local machineType = model:GetAttribute("machineType")
			local tier = model:GetAttribute("tier")
			if machineType == "generator" and typeof(tier) == "number" then
				byTier[tier] = byTier[tier] or {}
				table.insert(byTier[tier], id)
			end
		end
	end
	for t in pairs(byTier) do
		table.insert(tiers, t)
	end
	table.sort(tiers)

	local best
	for _, tier in ipairs(tiers) do
		local ids = byTier[tier]
		if ids and #ids >= 2 then
			local a = ids[#ids]
			local b = ids[#ids - 1]
			local allowed = MergeSystem.CanMerge(a, b)
			if allowed then
				local price = computeMergePrice(tier, player)
				if not best or price < best.price then
					best = { a = a, b = b, tier = tier, price = price }
				end
			end
		end
	end
	return best
end

local function handleRequest(player)
	if not player then
		return { success = false, reason = "no_player" }
	end
	if not AutoAccess.HasAccess(player, "auto_merge") then
		return { success = false, reason = "no_access" }
	end
	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < REQUEST_COOLDOWN then
		return { success = false, reason = "cooldown" }
	end
	lastRequestAt[player] = now
	local cash = Economy.GetCash(player)
	local pair = findPair(player)
	if not pair then
		return { success = false, reason = "no_merge" }
	end
	if pair.price > 0 and cash < pair.price then
		return { success = false, reason = "insufficient_funds", price = pair.price }
	end

	if pair.price > 0 and not Economy.Spend(player, pair.price) then
		return { success = false, reason = "insufficient_funds", price = pair.price }
	end

	local ok, newId = MergeSystem.ExecuteMerge(pair.a, pair.b)
	if not ok then
		if pair.price > 0 then
			Economy.Grant(player, pair.price)
		end
		return { success = false, reason = "merge_failed" }
	end

	debugutil.log("automerge", "state", "auto_merge_one", {
		userid = player.UserId,
		merged = 1,
		price = pair.price,
	})

	return { success = true, merged = 1, spent = pair.price }
end

function AutoMerge.Init()
	local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
	local requestFn = remotes:FindFirstChild("auto_merge_request") or Instance.new("RemoteFunction")
	requestFn.Name = "auto_merge_request"
	requestFn.Parent = remotes

	requestFn.OnServerInvoke = function(player)
		return handleRequest(player)
	end

	debugutil.log("automerge", "init", "auto_merge ready", {})
end

function AutoMerge.NextPrice(player)
	if not player then
		return nil
	end
	local pair = findPair(player)
	return pair and pair.price or nil
end

function AutoMerge.MergeOne(player)
	return handleRequest(player)
end

return AutoMerge
