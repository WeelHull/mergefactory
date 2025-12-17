local MachineInteractionState = {}

local active = false
local relocating = false

function MachineInteractionState.IsActive()
	return active
end

function MachineInteractionState.SetActive(value, reason)
	active = value and true or false
	if not active then
		relocating = false
	end
end

function MachineInteractionState.SetRelocating(value, reason)
	relocating = value and true or false
	local debugutil = require(game:GetService("ReplicatedStorage").Shared.debugutil)
	debugutil.log("machine", "state", "relocating_flag", {
		value = relocating,
		reason = reason or "unspecified",
	})
end

function MachineInteractionState.IsRelocating()
	return relocating
end

return MachineInteractionState
