local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local debug = require(ServerScriptService.Server.debugutil)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

local Economy = {}

local playerState = {} -- player -> { cash = number, perSecond = number, running = bool }

local function computePerSecond(player)
	local total = 0
	for _, model in ipairs(MachineRegistry.getMachinesForOwner(player.UserId)) do
		local machineType = model:GetAttribute("machineType")
		local tier = model:GetAttribute("tier")
		if machineType and tier then
			total += EconomyConfig.GetRate(machineType, tier)
		end
	end
	return total
end

local function updateAttributes(player, state)
	player:SetAttribute("Cash", math.floor(state.cash))
	player:SetAttribute("CashPerSecond", state.perSecond)
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
		task.wait(1)
	end
end

function Economy.Start(player)
	if playerState[player] then
		return
	end
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

Players.PlayerRemoving:Connect(function(player)
	Economy.Stop(player)
end)

return Economy
