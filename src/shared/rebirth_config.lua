local EconomyConfig = require(script.Parent.economy_config)

local RebirthConfig = {}

local MAX_TIER_FOR_ANCHOR = 10
local BASE_ANCHOR =
	EconomyConfig.GetMachinePrice("generator", MAX_TIER_FOR_ANCHOR, 0)
local BASE_MULTIPLIER = 0.42 -- tuned so first rebirth is ~200k
if BASE_ANCHOR < 1 then
	BASE_ANCHOR = 1
end

local function sanitizeRebirths(rebirths)
	local r = tonumber(rebirths) or 0
	if r < 0 then
		r = 0
	end
	return r
end

function RebirthConfig.ComputeMultipliers(rebirths)
	local r = sanitizeRebirths(rebirths)
	local root = math.sqrt(r)

	local incomeMult = (1 + 0.05) ^ root
	local prodMult = (1 + 0.08) ^ root
	local discount = 0
	if r > 0 then
		discount = 1 - 1 / (1 + 0.03 * (r ^ 0.65))
	end
	discount = math.clamp(discount, 0, 0.95)

	return {
		income = incomeMult,
		production = prodMult,
		tileDiscount = discount,
	}
end

function RebirthConfig.ComputeCost(rebirths)
	local r = sanitizeRebirths(rebirths)

	local base = BASE_ANCHOR * BASE_MULTIPLIER
	local growth = 1.28 ^ r
	local linear = 1 + r / 100
	local cost = base * growth * linear
	return math.ceil(cost)
end

return RebirthConfig
