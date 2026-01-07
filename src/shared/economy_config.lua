local EconomyConfig = {}

local DEFAULT_RATE_PER_TIER = 7 -- base cash per second per tier (before luck multiplier)
local DEFAULT_PRICE_PER_TIER = 120 -- base price per tier
local TILE_BASE_PRICE = 50
local TILE_STEP_PRICE = 25

local function demandMultiplier(cashPerSecond, weight)
	local cps = math.max(0, tonumber(cashPerSecond) or 0)
	local w = weight or 1
	if w < 0 then
		w = 0
	end
	-- Softer growth: modest scaling to avoid sharp spikes in progression.
	-- Tiles use w=0.35 (power ~1.1), machines w=0.75 (power ~1.8).
	local base = 1 + cps / 60
	local power = 1.2 + 0.8 * w
	return math.max(1, base ^ power)
end

function EconomyConfig.GetRate(machineType, tier)
	if machineType == nil or tier == nil then
		return 0
	end
	if machineType == "generator" then
		return DEFAULT_RATE_PER_TIER * tier
	end
	return 0
end

function EconomyConfig.GetMachinePrice(machineType, tier, cashPerSecond)
	if machineType == nil or tier == nil then
		return 0
	end
	local multiplier = demandMultiplier(cashPerSecond, 0.75)
	if machineType == "generator" then
		local t = math.max(1, tier)
		local tierFactor = t ^ 2.6 -- steeper growth per tier to slow progression
		local base = DEFAULT_PRICE_PER_TIER * t * tierFactor
		return math.floor(base * multiplier)
	end
	return 0
end

function EconomyConfig.GetStoragePrice(machineType, tier, cashPerSecond, cash, machineCount)
	if machineType == nil or tier == nil then
		return 0
	end
	local wealth = math.max(0, tonumber(cash) or 0)
	local count = math.max(1, tonumber(machineCount) or 1)
	local pct
	if count == 1 then
		pct = 1
	elseif count == 2 then
		pct = 0.9
	elseif count == 3 then
		pct = 0.8
	elseif count == 4 then
		pct = 0.7
	elseif count == 5 then
		pct = 0.6
	elseif count == 6 then
		pct = 0.5
	else
		pct = 0.4
	end
	local feeFromCash = wealth * pct
	return math.floor(feeFromCash)
end

function EconomyConfig.GetTilePrice(gridx, gridz, cashPerSecond)
	if not gridx or not gridz then
		return TILE_BASE_PRICE
	end
	-- Softer distance growth for a 19x19 grid (361 tiles).
	local dist = math.abs(gridx - 1) + math.abs(gridz - 1)
	local distanceFactor = (1 + dist) ^ 1.15
	local base = TILE_BASE_PRICE + dist * TILE_STEP_PRICE
	-- Tiles scale weakly with income to avoid runaway prices.
	local multiplier = demandMultiplier(cashPerSecond, 0.35)
	return math.floor(base * distanceFactor * multiplier)
end

return EconomyConfig
