local EconomyConfig = {}

local DEFAULT_RATE_PER_TIER = 10 -- cash per second per tier for generator
local DEFAULT_PRICE_PER_TIER = 100 -- base price per tier
local TILE_BASE_PRICE = 75
local TILE_STEP_PRICE = 50

local function demandMultiplier(cashPerSecond, weight)
	local cps = math.max(0, tonumber(cashPerSecond) or 0)
	local w = weight or 1
	if w < 0 then
		w = 0
	end
	-- Aggressive growth: as income rises, prices scale superlinearly to slow progression.
	-- Tiles use w=1 (power ~2.0), machines w=0.75 (power ~1.8).
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
		local tierFactor = t ^ 2.1 -- steeper growth per tier to slow progression
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
	local purchasePrice = EconomyConfig.GetMachinePrice(machineType, tier, cashPerSecond)
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
	-- ensure a baseline tied to machine value so fee isn't negligible when cash is low
	local baseline = math.max(10, purchasePrice * 0.25)
	return math.floor(math.max(baseline, feeFromCash))
end

function EconomyConfig.GetTilePrice(gridx, gridz, cashPerSecond)
	if not gridx or not gridz then
		return TILE_BASE_PRICE
	end
	-- Distance spike: farther tiles get exponentially more expensive.
	local dist = math.abs(gridx - 1) + math.abs(gridz - 1)
	local distanceFactor = (1 + dist) ^ 2.2
	local base = TILE_BASE_PRICE + dist * TILE_STEP_PRICE
	local multiplier = demandMultiplier(cashPerSecond, 1)
	return math.floor(base * distanceFactor * multiplier)
end

return EconomyConfig
