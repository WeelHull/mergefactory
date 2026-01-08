local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ServerScriptService.Server.debugutil)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local gridregistry = require(ServerScriptService.Server.gridregistry)
local Inventory = require(ServerScriptService.Server.inventory)
local IslandController = require(ServerScriptService.Server.islandcontroller)
local UnlockController = require(ServerScriptService.Server.unlockcontroller)
local Economy = require(ServerScriptService.Server.economy)
local RebirthConfig = require(ReplicatedStorage.Shared.rebirth_config)
local QuestSystem = require(ServerScriptService.Server.questsystem)

local Rebirth = {}

local START_GRIDX = 1
local START_GRIDZ = 1

local state = {} -- state[userId] = { rebirths = number }

local function applyAttributes(player, rebirths)
	local multipliers = RebirthConfig.ComputeMultipliers(rebirths)
	if player then
		player:SetAttribute("Rebirths", rebirths)
		player:SetAttribute("RebirthIncomeMult", multipliers.income)
		player:SetAttribute("RebirthProdMult", multipliers.production)
		player:SetAttribute("RebirthTileDiscount", multipliers.tileDiscount)
	end
	return multipliers
end

local function getState(player)
	if not player then
		return nil
	end
	local userId = player.UserId
	state[userId] = state[userId] or {
		rebirths = player:GetAttribute("Rebirths") or 0,
	}
	return state[userId]
end

local function clearMachines(player)
	for _, machineId in ipairs(MachineRegistry.getIdsForOwner(player.UserId)) do
		local model = MachineRegistry.unregister(machineId)
		if model then
			model:Destroy()
		end
	end
end

local function resetIsland(player)
	local islandid = IslandController.getIslandForPlayer(player)
	if not islandid then
		return
	end
	gridregistry.resetIsland(islandid)
	UnlockController.unlockTile(player, START_GRIDX, START_GRIDZ)
end

local function applyStarter(player)
	Inventory.Reset(player.UserId)
	Inventory.Grant(player.UserId, "generator", 1, 1)
	Economy.Reset(player)
end

local function computeTokens(cash, startIndex)
	local tokens = 0
	local spend = 0
	local r = startIndex
	while true do
		local cost = RebirthConfig.ComputeCost(r)
		if cash >= cost then
			cash -= cost
			spend += cost
			r += 1
			tokens += 1
		else
			break
		end
	end
	local nextCost = RebirthConfig.ComputeCost(r)
	return tokens, spend, cash, nextCost
end

local function updatePreview(player)
	if not player then
		return
	end
	local st = getState(player)
	if not st then
		return
	end
	local cash = Economy.GetCash(player)
	local tokens, spend, remainder, nextCost = computeTokens(cash, st.rebirths or 0)
	local progress = math.clamp(remainder, 0, nextCost)
	player:SetAttribute("RebirthStack", tokens)
	player:SetAttribute("RebirthNextCost", nextCost)
	player:SetAttribute("RebirthProgress", progress)
	player:SetAttribute("RebirthAffordableSpend", spend)
end

function Rebirth.Init(player)
	local st = getState(player)
	local multipliers = applyAttributes(player, st.rebirths)
	updatePreview(player)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		updatePreview(player)
	end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		updatePreview(player)
	end)
	debugutil.log("rebirth", "init", "rebirth initialized", {
		userid = player.UserId,
		rebirths = st.rebirths,
		multipliers = multipliers,
	})
end

function Rebirth.GetRebirths(player)
	local st = getState(player)
	return st and st.rebirths or 0
end

function Rebirth.GetMultipliers(player)
	return RebirthConfig.ComputeMultipliers(Rebirth.GetRebirths(player))
end

function Rebirth.GetCost(player)
	if not player then
		return 0
	end
	local st = getState(player)
	return RebirthConfig.ComputeCost(st and st.rebirths or 0)
end

function Rebirth.Preview(player)
	if not player then
		return { success = false, reason = "no_player" }
	end
	local st = getState(player)
	local rebirths = st.rebirths
	local multipliers = RebirthConfig.ComputeMultipliers(rebirths)
	updatePreview(player)
	local cost = Rebirth.GetCost(player)
	return {
		success = true,
		rebirths = rebirths,
		stack = player:GetAttribute("RebirthStack") or 0,
		cost = cost,
		multipliers = multipliers,
	}
end

function Rebirth.Perform(player)
	if not player then
		return { success = false, reason = "no_player" }
	end

	local st = getState(player)
	local cash = Economy.GetCash(player)
	local currentIndex = st.rebirths or 0
	local tokens, spend, remainder, nextCost = computeTokens(cash, currentIndex)
	if tokens < 1 or spend <= 0 then
		return {
			success = false,
			reason = "insufficient_funds",
			cost = Rebirth.GetCost(player),
			cash = cash,
		}
	end

	local spent = Economy.Spend(player, spend)
	if not spent then
		return {
			success = false,
			reason = "spend_failed",
			cost = Rebirth.GetCost(player),
			cash = Economy.GetCash(player),
		}
	end

	clearMachines(player)
	resetIsland(player)
	applyStarter(player)
	QuestSystem.Reset(player)

	st.rebirths += tokens
	local multipliers = applyAttributes(player, st.rebirths)
	updatePreview(player)

	debugutil.log("rebirth", "state", "rebirthed", {
		userid = player.UserId,
		rebirths = st.rebirths,
		stack = 0,
		tokens_granted = tokens,
		spent = spend,
		multipliers = multipliers,
	})

	return {
		success = true,
		rebirths = st.rebirths,
		stack = 0,
		spent = spend,
		tokensGranted = tokens,
		multipliers = multipliers,
		nextCost = Rebirth.GetCost(player),
	}
end

Players.PlayerAdded:Connect(Rebirth.Init)
Players.PlayerRemoving:Connect(function(player)
	state[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	Rebirth.Init(player)
end

return Rebirth
