-- machine_interaction: client intent sender for machine selection/rotation/move.
-- No movement logic; server authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local machineIntentEvent = remotes:WaitForChild("machine_intent")

local VALID_INTENTS = {
	select = true,
	rotate = true,
	move = true,
}

local function findMachineFromTarget(target)
	if not target or not target:IsDescendantOf(Workspace) then
		return nil
	end

	local current = target
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local gx = current:GetAttribute("gridx")
			local gz = current:GetAttribute("gridz")
			if typeof(gx) == "number" and typeof(gz) == "number" then
				return current, gx, gz
			end
		end
		current = current.Parent
	end

	return nil
end

local function sendIntent(intent, model, gridx, gridz, rotation)
	if not VALID_INTENTS[intent] then
		return
	end

	local payload = {
		intent = intent,
		gridx = gridx,
		gridz = gridz,
		rotation = rotation,
	}

	machineIntentEvent:FireServer(payload)
end

local function onClick()
	local target = mouse.Target
	local model, gridx, gridz = findMachineFromTarget(target)
	if not model then
		return
	end

	sendIntent("select", model, gridx, gridz)
end

mouse.Button1Down:Connect(onClick)

return {}
