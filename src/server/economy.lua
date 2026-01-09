local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local debug = require(ServerScriptService.Server.debugutil)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

local Economy = {}

local playerState = {} -- player -> { cash = number, perSecond = number, running = bool }
local ppsCache = {} -- userId -> cached per-second rate

local function updateAttributes(player, state)
	player:SetAttribute("Cash", math.floor(state.cash))
	player:SetAttribute("CashPerSecond", state.perSecond)
end

local function computePerSecond(player)
	local userId = player and player.UserId
	if not userId then
		return 0
	end
	local cached = ppsCache[userId]
	if typeof(cached) ~= "number" then
		return 0
	end
	local prodMult = player:GetAttribute("RebirthProdMult") or 1
	local incomeMult = player:GetAttribute("RebirthIncomeMult") or 1
	return cached * prodMult * incomeMult
end

-- Recompute from registry (safety net)
function Economy.RecomputePlayer(player)
	if not player or not player.UserId then
		return
	end
	local total = 0
	for _, model in ipairs(MachineRegistry.getMachinesForOwner(player.UserId)) do
		local machineType = model:GetAttribute("machineType")
		local tier = model:GetAttribute("tier")
		if machineType and tier then
			local machineMult = model:GetAttribute("cashMultiplier")
			if typeof(machineMult) ~= "number" or machineMult < 1 then
				machineMult = 1
			end
			total += EconomyConfig.GetRate(machineType, tier) * machineMult
		end
	end
	ppsCache[player.UserId] = total
	local state = playerState[player]
	if state then
		state.perSecond = computePerSecond(player)
		updateAttributes(player, state)
	end
end

function Economy.AddRate(userId, machineType, tier, mult)
	if typeof(userId) ~= "number" then
		return
	end
	local machineMult = typeof(mult) == "number" and mult or 1
	if machineMult < 1 then
		machineMult = 1
	end
	ppsCache[userId] = (ppsCache[userId] or 0) + EconomyConfig.GetRate(machineType, tier) * machineMult
end

function Economy.RemoveRate(userId, machineType, tier, mult)
	if typeof(userId) ~= "number" then
		return
	end
	local machineMult = typeof(mult) == "number" and mult or 1
	if machineMult < 1 then
		machineMult = 1
	end
	ppsCache[userId] = (ppsCache[userId] or 0) - EconomyConfig.GetRate(machineType, tier) * machineMult
	if ppsCache[userId] < 0 then
		ppsCache[userId] = 0
	end
end

local function tickPlayer(player)
	local state = playerState[player]
	if not state then
		return
	end
	local now = os.clock()
	local dt = now - (state.last or now)
	state.last = now
	state.perSecond = computePerSecond(player)
	state.cash += state.perSecond * dt
	updateAttributes(player, state)
end

local function runLoop(player)
	local state = playerState[player]
	if not state then
		return
	end
	state.last = os.clock()
while state.running and player.Parent do
		tickPlayer(player)
		task.wait(1) -- balanced cadence for responsiveness vs load
	end
end

function Economy.Start(player)
	if playerState[player] then
		return
	end
	Economy.RecomputePlayer(player)
	playerState[player] = {
		cash = player:GetAttribute("Cash") or 0,
		perSecond = 0,
		running = true,
		last = os.clock(),
	}
	updateAttributes(player, playerState[player])
	task.spawn(runLoop, player)
	debug.log("economy", "init", "economy started", { userid = player.UserId })
end

function Economy.Stop(player)
	local state = playerState[player]
	if not state then
		return
	end
	state.running = false
	playerState[player] = nil
end

function Economy.GetCash(player)
	local state = playerState[player]
	return state and state.cash or 0
end

function Economy.Spend(player, amount)
	local state = playerState[player]
	if not state or not amount or amount <= 0 then
		return false
	end
	if state.cash < amount then
		return false
	end
	state.cash -= amount
	updateAttributes(player, state)
	return true
end

function Economy.Grant(player, amount)
	local state = playerState[player]
	if not state or not amount or amount <= 0 then
		return false
	end
	state.cash += amount
	updateAttributes(player, state)
	return true
end

function Economy.Reset(player)
	if not player then
		return
	end
	local state = playerState[player]
	if not state then
		Economy.Start(player)
		state = playerState[player]
	end
	if not state then
		return
	end
	state.cash = 0
	state.perSecond = 0
	state.last = os.clock()
	updateAttributes(player, state)
end

-- periodic resync to guard against drift
task.spawn(function()
	while true do
		for plr in pairs(playerState) do
			if plr and plr.Parent then
				Economy.RecomputePlayer(plr)
			end
		end
		task.wait(180) -- every 3 minutes
	end
end)

Players.PlayerRemoving:Connect(function(player)
	Economy.Stop(player)
	if player and player.UserId then
		ppsCache[player.UserId] = nil
	end
end)

return Economy
