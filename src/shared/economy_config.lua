local EconomyConfig = {}

local DEFAULT_RATE_PER_TIER = 10 -- cash per second per tier for generator
local DEFAULT_PRICE_PER_TIER = 100 -- base price per tier
local TILE_BASE_PRICE = 50
local TILE_STEP_PRICE = 25

function EconomyConfig.GetRate(machineType, tier)
	if machineType == nil or tier == nil then
		return 0
	end
	if machineType == "generator" then
		return DEFAULT_RATE_PER_TIER * tier
	end
	return 0
end

function EconomyConfig.GetMachinePrice(machineType, tier)
	if machineType == nil or tier == nil then
		return 0
	end
	if machineType == "generator" then
		return DEFAULT_PRICE_PER_TIER * tier
	end
	return 0
end

function EconomyConfig.GetTilePrice(gridx, gridz)
	if not gridx or not gridz then
		return TILE_BASE_PRICE
	end
	-- simple distance-based price: farther tiles cost more
	local dist = math.abs(gridx - 1) + math.abs(gridz - 1)
	return TILE_BASE_PRICE + dist * TILE_STEP_PRICE
end

return EconomyConfig
