local ReplicatedStorage = game:GetService("ReplicatedStorage")
local debugutil = require(ReplicatedStorage.Shared.debugutil)

local PlacementMode = {}

local active = false

function PlacementMode.IsActive()
	return active
end

function PlacementMode.SetActive(value, reason)
	if active == value then
		return
	end
	active = value
	debugutil.log("placement", "state", value and "enter" or "exit", {
		state = value and "active" or "inactive",
		reason = reason or "unspecified",
	})
end

return PlacementMode
