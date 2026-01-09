local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local refs = {
	frame = nil,
	button = nil,
}

local dragging = false
local DEFAULT_SPEED = 16
local MAX_SPEED = 128

local function findControls()
	local playerUI = playerGui:FindFirstChild("PlayerUI")
	if not playerUI then
		return false
	end
	local settings = playerUI:FindFirstChild("settings_frame")
	if not settings then
		return false
	end
	local speedFrame = settings:FindFirstChild("speed_frame", true)
	if not speedFrame then
		return false
	end
	local button = speedFrame:FindFirstChild("scroll_button", true)
	if not button then
		return false
	end
	refs.frame = speedFrame
	refs.button = button
	return true
end

local function applySpeed(ratio)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local speed = DEFAULT_SPEED + (MAX_SPEED - DEFAULT_SPEED) * ratio
	hum.WalkSpeed = speed
end

local function setRatio(ratio)
	if not refs.frame or not refs.button then
		return
	end
	local r = math.clamp(ratio, 0, 1)
	refs.button.Position = UDim2.new(r, 0, 0.5, 0)
	applySpeed(r)
end

local function updateFromInput(input)
	if not refs.frame or not refs.button then
		return
	end
	local framePos = refs.frame.AbsolutePosition
	local frameSize = refs.frame.AbsoluteSize
	if frameSize.X <= 0 then
		return
	end
	local rel = (input.Position.X - framePos.X) / frameSize.X
	setRatio(rel)
end

local function startDrag(input)
	dragging = true
	updateFromInput(input)
end

local function stopDrag()
	dragging = false
end

local function bind()
	if not findControls() then
		return
	end

	refs.button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
		end
	end)

	refs.button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			stopDrag()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input)
		end
	end)

	-- Default to normal speed (left).
	setRatio(0)
end

player.CharacterAdded:Connect(function(char)
	setRatio(0)
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

bind()
