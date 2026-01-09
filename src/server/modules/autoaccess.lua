-- autoaccess: central gate for auto-* features (buy/merge/tiles/quests).
-- Currently permissive for testing; swap HasAccess to call MarketplaceService
-- when adding a gamepass/dev product gate. Keep a whitelist helper for devs.

local RunService = game:GetService("RunService")

local AutoAccess = {}

local WHITELIST = {} -- [userId] = true (global dev bypass)

-- Placeholder product/gamepass mapping per feature for future MarketplaceService checks.
-- Example keys: "auto_buy", "auto_tiles", "auto_merge", "auto_orchestrator", "auto_quest"
local PRODUCT_IDS = {
	-- auto_buy = 123456,
}

function AutoAccess.HasAccess(player, feature)
	if not player then
		return false
	end

	-- Allow everything in Studio for rapid testing.
	if RunService:IsStudio() then
		return true
	end

	-- Temporary whitelist hook.
	if WHITELIST[player.UserId] then
		return true
	end

	-- TODO: replace with MarketplaceService gamepass/dev product check keyed by `feature`.
	-- Example:
	-- local productId = PRODUCT_IDS[feature]
	-- if productId then
	--     return MarketplaceService:UserOwnsGamePassAsync(player.UserId, productId)
	-- end

	return true
end

return AutoAccess
