-- mergecontroller: central merge offer + decision handling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MergeSystem = require(ServerScriptService.Server.mergesystem)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local debug = require(ServerScriptService.Server.debugutil)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local mergeOfferEvent = remotes:FindFirstChild("merge_offer") or Instance.new("RemoteEvent")
mergeOfferEvent.Name = "merge_offer"
mergeOfferEvent.Parent = remotes
local mergeDecisionFn = remotes:FindFirstChild("merge_decision") or Instance.new("RemoteFunction")
mergeDecisionFn.Name = "merge_decision"
mergeDecisionFn.Parent = remotes

local pendingMergeByPlayer = {} -- player -> { sourceId, targetId, price, timestamp }

local MergeController = {}

local function computeMergePrice(machineType, tier, player)
	local nextTier = (tier or 0) + 1
	local cps = player and player:GetAttribute("CashPerSecond") or 0
	local basePrice = EconomyConfig.GetMachinePrice(machineType, nextTier, cps)
	local discounted = math.max(0, math.floor(basePrice * 0.8))
	return discounted, nextTier
end

function MergeController.SendMergeOffer(player, sourceId, targetId, machineType, tier)
	if not player then
		return
	end
	local price, targetTier = computeMergePrice(machineType, tier, player)
	pendingMergeByPlayer[player] = {
		sourceId = sourceId,
		targetId = targetId,
		price = price,
		timestamp = os.clock(),
	}
	mergeOfferEvent:FireClient(player, {
		sourceId = sourceId,
		targetId = targetId,
		machineType = machineType,
		currentTier = tier,
		resultTier = targetTier,
		price = price,
	})
end

local function clearPending(player)
	pendingMergeByPlayer[player] = nil
end

Players.PlayerRemoving:Connect(clearPending)

local function handleDecision(player, action, payload)
	local pending = pendingMergeByPlayer[player]
	if not pending then
		return { success = false, reason = "no_pending" }
	end

	if typeof(payload) ~= "table" then
		return { success = false, reason = "invalid_payload" }
	end

	local sourceId = payload.sourceId
	local targetId = payload.targetId
	if pending.sourceId ~= sourceId or pending.targetId ~= targetId then
		return { success = false, reason = "mismatch" }
	end

	if action == "cancel" then
		clearPending(player)
		local model = MachineRegistry.get(sourceId)
		if model and model:GetAttribute("state") == "Relocating" then
			model:SetAttribute("state", "Idle")
		end
		return { success = false, reason = "cancelled" }
	end

	if action ~= "coin" then
		return { success = false, reason = "unsupported_payment" }
	end

	local canMerge, reason = MergeSystem.CanMerge(sourceId, targetId)
	if not canMerge then
		clearPending(player)
		return { success = false, reason = reason or "cannot_merge" }
	end

	local targetModel = MachineRegistry.get(targetId)
	if not targetModel then
		clearPending(player)
		return { success = false, reason = "target_missing" }
	end

	local machineType = targetModel:GetAttribute("machineType")
	local tier = targetModel:GetAttribute("tier")
	local price = computeMergePrice(machineType, tier, player)
	if price ~= pending.price then
		pending.price = price
	end

	local spent = Economy.Spend(player, pending.price)
	if not spent then
		return { success = false, reason = "insufficient_funds", price = pending.price }
	end

	local executed, execReason = MergeSystem.ExecuteMerge(sourceId, targetId)
	clearPending(player)

	if not executed then
		return { success = false, reason = execReason or "merge_failed" }
	end

	debug.log("merge", "state", "merge_executed", {
		source = sourceId,
		target = targetId,
		price = price,
	})

	return { success = true, price = price }
end

mergeDecisionFn.OnServerInvoke = function(player, action, payload)
	return handleDecision(player, action, payload)
end

function MergeController.ClearPending(player)
	clearPending(player)
end

return MergeController
