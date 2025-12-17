local MachineInteractionState = {}

local active = false

function MachineInteractionState.IsActive()
	return active
end

function MachineInteractionState.SetActive(value)
	active = value and true or false
end

return MachineInteractionState
