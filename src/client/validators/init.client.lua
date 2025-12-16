local validatorModule = script:FindFirstChild("ux_interaction_validator") or script.Parent:FindFirstChild("ux_interaction_validator")

if validatorModule then
	require(validatorModule)
else
	warn("ux_interaction_validator missing; validator not started")
end
