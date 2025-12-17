local MachineInteractionState = {}

local active = false
local relocating = false

function MachineInteractionState.IsActive()
	return active
end

function MachineInteractionState.SetActive(value)
	active = value and true or false
end

function MachineInteractionState.SetRelocating(value)
	relocating = value and true or false
end

function MachineInteractionState.IsRelocating()
	return relocating
end

return MachineInteractionState
