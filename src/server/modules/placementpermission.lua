local debugutil = require(script.Parent.Parent.debugutil)
local islandcontroller = require(script.Parent.Parent.islandcontroller)
local gridregistry = require(script.Parent.Parent.gridregistry)

debugutil.log("placement", "init", "placement permission module ready")

local PlacementPermission = {}

local function findIslandIdForTile(tile)
	local ancestor = tile
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:GetAttribute("islandid") ~= nil then
			return ancestor:GetAttribute("islandid")
		end
		ancestor = ancestor.Parent
	end
	return nil
end

function PlacementPermission.CanPlaceOnTile(player, tile)
	if not tile or not tile:IsA("BasePart") then
		debugutil.log("placement", "decision", "deny", { reason = "invalid_tile", userid = player and player.UserId })
		return false, "invalid_tile"
	end

	local gridx = tile:GetAttribute("gridx")
	local gridz = tile:GetAttribute("gridz")
	local unlocked = tile:GetAttribute("unlocked")

	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" or typeof(unlocked) ~= "boolean" then
		debugutil.log("placement", "decision", "deny", {
			reason = "missing_attrs",
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
			unlocked = unlocked,
		})
		return false, "invalid_tile"
	end

	local playerIsland = islandcontroller.getIslandForPlayer(player)
	local tileIsland = findIslandIdForTile(tile)

	if tileIsland ~= playerIsland then
		debugutil.log("placement", "decision", "deny", {
			reason = "wrong_island",
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
			tile_island = tileIsland,
			player_island = playerIsland,
		})
		return false, "wrong_island"
	end

	if unlocked ~= true then
		debugutil.log("placement", "decision", "deny", {
			reason = "tile_locked",
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
		})
		return false, "tile_locked"
	end

	debugutil.log("placement", "state", "allow", {
		userid = player.UserId,
		gridx = gridx,
		gridz = gridz,
	})
	return true, "allowed"
end

-- Coordinate-based helper for grid placement (reuses CanPlaceOnTile logic).
function PlacementPermission.canPlace(params)
	if typeof(params) ~= "table" then
		return false, "invalid_params"
	end

	local player = params.player
	local islandid = params.islandid
	local gridx = params.gridx
	local gridz = params.gridz

	local entry = gridregistry.getTile(islandid, gridx, gridz)
	if not entry or not entry.part then
		debugutil.log("placement", "decision", "deny", {
			reason = "tile_missing",
			userid = player and player.UserId,
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
		})
		return false, "tile_missing"
	end

	return PlacementPermission.CanPlaceOnTile(player, entry.part)
end

return PlacementPermission
