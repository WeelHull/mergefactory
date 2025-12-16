-- islandvalidator: authoritative check for valid island ids.

local Workspace = game:GetService("Workspace")

local IslandValidator = {}

function IslandValidator.isValidIslandId(islandid)
	if typeof(islandid) ~= "number" then
		return false
	end

	local islands = Workspace:FindFirstChild("islands")
	if not islands then
		return false
	end

	for _, island in ipairs(islands:GetChildren()) do
		if island:GetAttribute("islandid") == islandid then
			return true
		end
	end

	return false
end

return IslandValidator
