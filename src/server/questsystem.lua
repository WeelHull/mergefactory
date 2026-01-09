-- questsystem: server-authoritative quest chains and rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debugutil = require(ServerScriptService.Server.debugutil)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

local QuestSystem = {}

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local updateEvent = remotes:FindFirstChild("quest_update") or Instance.new("RemoteEvent")
updateEvent.Name = "quest_update"
updateEvent.Parent = remotes
local requestFn = remotes:FindFirstChild("quest_request") or Instance.new("RemoteFunction")
requestFn.Name = "quest_request"
requestFn.Parent = remotes

local MAX_TIER = 10
local PLACEMENT_STEPS_PER_TIER = math.huge -- infinite progression

-- state[userId] = {
--   highestTier = number,
--   placementTotals = { [tier] = count },
--   unlockTier = number,
--   placementSteps = { [tier] = stepIndex },
--   seeded = bool,
-- }
local stateByUserId = {}

local function formatCompact(amount)
	local n = math.floor(tonumber(amount) or 0)
	local abs = math.abs(n)
	if abs >= 1_000_000_000 then
		return string.format("%gB", math.floor((n / 1_000_000_000) * 10 + 0.5) / 10)
	elseif abs >= 1_000_000 then
		return string.format("%gM", math.floor((n / 1_000_000) * 10 + 0.5) / 10)
	elseif abs >= 1_000 then
		return string.format("%gK", math.floor((n / 1_000) * 10 + 0.5) / 10)
	end
	return tostring(n)
end

local function placementTarget(tier, step)
	local s = math.max(1, step or 1)
	if s == 1 then
		return 1
	end
	return 5 * (s - 1)
end

local function getState(userId)
	if typeof(userId) ~= "number" then
		return nil
	end
	stateByUserId[userId] = stateByUserId[userId]
		or {
			highestTier = 0,
			placementTotals = {},
			unlockTier = 1,
			placementSteps = { [1] = 1 },
			seeded = false,
		}
	return stateByUserId[userId]
end

local function seedFromRegistry(userId)
	local state = getState(userId)
	if not state or state.seeded then
		return
	end

	local maxTier = 0
	for _, model in ipairs(MachineRegistry.getMachinesForOwner(userId)) do
		local machineType = model:GetAttribute("machineType")
		local tier = model:GetAttribute("tier")
		if machineType == "generator" and typeof(tier) == "number" then
			state.placementTotals[tier] = (state.placementTotals[tier] or 0) + 1
			if tier > maxTier then
				maxTier = tier
			end
		end
	end

	state.highestTier = math.max(state.highestTier, maxTier)
	state.seeded = true
end

local function getPlacementTotal(userId, tier)
	local state = getState(userId)
	if not state then
		return 0
	end
	return state.placementTotals[tier] or 0
end

local function baseTierPrice(tier)
	local t = math.max(1, tier or 1)
	return EconomyConfig.GetMachinePrice("generator", t, 0)
end

local function computeUnlockReward(player, targetTier)
	local cps = player and player:GetAttribute("CashPerSecond") or 0
	local demandPrice = EconomyConfig.GetMachinePrice("generator", targetTier, cps)
	-- Reward is 110% of the current tier price (the tier you're unlocking), capped at 130% to avoid runaway.
	local reward = demandPrice * 1.1
	local cap = demandPrice * 1.3
	if cap > 0 then
		reward = math.min(reward, cap)
	end
	return math.max(200, math.floor(reward))
end

local function computePlacementReward(player, tier, step)
	local cps = math.max(0, player and player:GetAttribute("CashPerSecond") or 0)
	local t = math.max(1, tier or 1)
	local s = math.max(1, step or 1)

	-- Cumulative cost to reach target count for this step (1,5,10,15,...).
	local target = placementTarget(t, s)
	local cumulativeCost = 0
	for i = 1, target do
		-- use a softened demand multiplier for reward calc to avoid overpaying on luck spikes
		local demandPrice = EconomyConfig.GetMachinePrice("generator", t, cps * 0.35)
		cumulativeCost += demandPrice
	end

	-- Percentage slice based on step (higher steps taper slightly).
	local slice
	if s == 1 then
		slice = 0.5
	elseif s == 2 then
		slice = 0.45
	elseif s == 3 then
		slice = 0.4
	else
		slice = 0.35
	end

	local reward = cumulativeCost * slice

	-- Cap at 70% of cumulative to avoid refunding the whole journey.
	local cap = cumulativeCost * 0.7
	if cap > 0 then
		reward = math.min(reward, cap)
	end

	-- Floor: at least 15% of cumulative plus a tier bump so early steps aren't tiny.
	local floor = cumulativeCost * 0.15 + (t - 1) * 100
	reward = math.max(floor, reward)

	return math.floor(reward)
end

local function buildUnlockQuest(player, state)
	local targetTier = math.min(state.unlockTier or 1, MAX_TIER)
	local highest = state.highestTier or 0
	local reward = computeUnlockReward(player, targetTier)
	return {
		id = "unlock_tier_" .. tostring(targetTier),
		category = "unlock",
		title = "Unlock Tier " .. tostring(targetTier),
		description = "Reach machine Tier " .. tostring(targetTier)
			.. " by placing or merging generators. Unlocks placement quests for this tier.",
		requirement = string.format("Current Tier: %d / %d", math.min(highest, targetTier), targetTier),
		rewardText = string.format("+%s C$", formatCompact(reward)),
		claimable = highest >= targetTier,
		progress = {
			current = highest,
			target = targetTier,
		},
		order = 1,
	}
end

local function buildPlacementQuest(player, state, tier)
	local step = math.max(1, state.placementSteps[tier] or 1)
	local target = placementTarget(tier, step)
	local progress = getPlacementTotal(player and player.UserId, tier)
	local reward = computePlacementReward(player, tier, step)
	return {
		id = string.format("place_tier_%d_step_%d", tier, step),
		category = "placement",
		title = string.format("Place Tier %d Generators", tier),
		description = "Place or create Tier " .. tostring(tier) .. " generators to grow production.",
		requirement = string.format("Progress: %d / %d", math.min(progress, target), target),
		rewardText = string.format("+%s C$", formatCompact(reward)),
		claimable = progress >= target,
		progress = {
			current = progress,
			target = target,
		},
		order = 2,
	}
end

local function noMissionsCard()
	return {
		id = "quests_complete",
		category = "complete",
		title = "No more missions",
		description = "You cleared every available quest for now.",
		requirement = "Check back soon for more challenges.",
		rewardText = "",
		claimable = false,
		terminal = true,
		progress = {
			current = 0,
			target = 0,
		},
		order = 99,
	}
end

local function buildQuestList(player)
	if not player then
		return {}
	end

	local state = getState(player.UserId)
	if not state then
		return {}
	end

	local quests = {}

	if (state.unlockTier or 1) <= MAX_TIER then
		table.insert(quests, buildUnlockQuest(player, state))
	end

	local activePlacementTiers = {}
	for tier, step in pairs(state.placementSteps or {}) do
		if typeof(step) == "number" and step >= 1 then
			table.insert(activePlacementTiers, tier)
		end
	end
	table.sort(activePlacementTiers)
	for _, tier in ipairs(activePlacementTiers) do
		local quest = buildPlacementQuest(player, state, tier)
		-- Slightly bump order to keep unlock first while showing multiple chains.
		quest.order = 2 + tier * 0.01
		table.insert(quests, quest)
	end

	if #quests == 0 then
		table.insert(quests, noMissionsCard())
	end

	table.sort(quests, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)

	return quests
end

local function pushUpdate(player, message)
	if not player or not player.Parent then
		return
	end
	local payload = {
		quests = buildQuestList(player),
		message = message,
	}
	updateEvent:FireClient(player, payload)
end

local function advanceUnlock(state)
	if not state then
		return
	end
	if (state.unlockTier or 1) < MAX_TIER then
		state.unlockTier += 1
	else
		state.unlockTier = MAX_TIER + 1
	end
end

local function advancePlacement(state, tier)
	if not state or typeof(tier) ~= "number" then
		return
	end
	local step = math.max(1, (state.placementSteps[tier] or 1)) + 1
	state.placementSteps[tier] = step
end

local function handleClaim(player, questId)
	if not player or typeof(questId) ~= "string" then
		return { success = false, reason = "invalid_request" }
	end
	local userId = player.UserId
	local state = getState(userId)
	if not state then
		return { success = false, reason = "no_state" }
	end

	if questId:find("^unlock_tier_") then
		local tierStr = questId:match("^unlock_tier_(%d+)$")
		local target = tonumber(tierStr)
		if not target or target ~= state.unlockTier or target > MAX_TIER then
			return { success = false, reason = "not_active" }
		end
		if (state.highestTier or 0) < target then
			return { success = false, reason = "not_complete" }
		end

		state.placementSteps[target] = state.placementSteps[target] or 1
		local reward = computeUnlockReward(player, target)
		if reward > 0 then
			Economy.Grant(player, reward)
		end
		advanceUnlock(state)
		debugutil.log("quest", "state", "unlock_claimed", {
			userid = userId,
			target = target,
			reward = reward,
		})
		return {
			success = true,
			reward = reward,
			message = string.format("Tier %d unlocked quest claimed! +%s C$", target, formatCompact(reward)),
		}
	end

	if questId:find("^place_tier_") then
		local tierStr, stepStr = questId:match("^place_tier_(%d+)_step_(%d+)$")
		local tier = tonumber(tierStr)
		local step = tonumber(stepStr)
		if
			not tier
			or not step
			or state.placementSteps[tier] == nil
			or step ~= state.placementSteps[tier]
		then
			return { success = false, reason = "not_active" }
		end
		local target = placementTarget(tier, step)
		local progress = getPlacementTotal(userId, tier)
		if progress < target then
			return { success = false, reason = "not_complete" }
		end

		local reward = computePlacementReward(player, tier, step)
		if reward > 0 then
			Economy.Grant(player, reward)
		end
		advancePlacement(state, tier)
		debugutil.log("quest", "state", "placement_claimed", {
			userid = userId,
			tier = tier,
			step = step,
			target = target,
			progress = progress,
			reward = reward,
		})
		return {
			success = true,
			reward = reward,
			message = string.format("Placement quest claimed! +%s C$", formatCompact(reward)),
		}
	end

	return { success = false, reason = "unknown_quest" }
end

local function onRequest(player, payload)
	if type(payload) ~= "table" then
		return { success = false, reason = "invalid_payload" }
	end
	local action = payload.action
	if action == "sync" then
		return { success = true, quests = buildQuestList(player) }
	elseif action == "claim" then
		local questId = payload.questId
		local result = handleClaim(player, questId)
		if result and result.success then
			pushUpdate(player, result.message)
		end
		return result
	elseif action == "claim_all" then
		local quests = buildQuestList(player)
		local claimed = 0
		for _, quest in ipairs(quests) do
			if quest.claimable then
				local result = handleClaim(player, quest.id)
				if result and result.success then
					claimed += 1
				end
			end
		end
		if claimed > 0 then
			pushUpdate(player, string.format("Claimed %d quests", claimed))
			return { success = true, claimed = claimed }
		end
		return { success = false, reason = "none_claimable" }
	end

	return { success = false, reason = "unknown_action" }
end

local function trackMachine(userId, machineType, tier, delta)
	if machineType ~= "generator" or typeof(tier) ~= "number" then
		return
	end
	local state = getState(userId)
	if not state then
		return
	end
	local d = tonumber(delta) or 1
	if d > 0 then
		state.highestTier = math.max(state.highestTier or 0, tier)
	end
	local current = state.placementTotals[tier] or 0
	state.placementTotals[tier] = math.max(0, current + d)

	local player = Players:GetPlayerByUserId(userId)
	if player then
		pushUpdate(player)
	end
end

function QuestSystem.RecordMachine(playerOrUserId, machineType, tier)
	local userId = typeof(playerOrUserId) == "number" and playerOrUserId or nil
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		userId = playerOrUserId.UserId
	end
	if not userId then
		return
	end
	trackMachine(userId, machineType, tier, 1)
end

function QuestSystem.RecordMachineRemoval(playerOrUserId, machineType, tier, amount)
	local userId = typeof(playerOrUserId) == "number" and playerOrUserId or nil
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		userId = playerOrUserId.UserId
	end
	if not userId then
		return
	end
	trackMachine(userId, machineType, tier, -(tonumber(amount) or 1))
end

function QuestSystem.Reset(playerOrUserId)
	local userId = typeof(playerOrUserId) == "number" and playerOrUserId or nil
	local player = nil
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		player = playerOrUserId
		userId = player.UserId
	end
	if not userId then
		return
	end
	stateByUserId[userId] = nil
	if player then
		pushUpdate(player)
	end
end

local function onPlayerAdded(player)
	if not player then
		return
	end
	seedFromRegistry(player.UserId)
	pushUpdate(player)
end

local function onPlayerRemoving(player)
	if not player then
		return
	end
	stateByUserId[player.UserId] = nil
end

function QuestSystem.Init()
	if QuestSystem._initialized then
		return
	end
	QuestSystem._initialized = true
	requestFn.OnServerInvoke = onRequest
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(onPlayerAdded, player)
	end
	debugutil.log("quest", "init", "questsystem ready", {})
end

return QuestSystem
