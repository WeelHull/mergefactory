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
	-- Softer growth: clamp demand so luck spikes don't explode prices.
	local base = 1 + cps / 80
	local power = 1 + 0.5 * w
	local mult = math.max(1, base ^ power)
	-- Hard cap to keep early-game prices sane.
	return math.min(mult, 5)
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

function EconomyConfig.GetTilePrice(gridx, gridz, cashPerSecond, tileDiscount)
	if not gridx or not gridz then
		return TILE_BASE_PRICE
	end
	-- Softer distance growth for a 19x19 grid (361 tiles).
	local dist = math.abs(gridx - 1) + math.abs(gridz - 1)
	local distanceFactor = (1 + dist) ^ 1.15
	local base = TILE_BASE_PRICE + dist * TILE_STEP_PRICE
	-- Tiles scale weakly with income to avoid runaway prices.
	local multiplier = demandMultiplier(cashPerSecond, 0.35)
	local discount = math.clamp(tonumber(tileDiscount) or 0, 0, 0.95)
	local price = math.floor(base * distanceFactor * multiplier)
	price = math.floor(price * (1 - discount))
	if price < 0 then
		price = 0
	end
	return price
end

return EconomyConfig
