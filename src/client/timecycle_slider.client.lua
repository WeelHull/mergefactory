local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local setEvent = remotes:WaitForChild("timecycle_set")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local refs = {
	frame = nil,
	button = nil,
}

local dragging = false
local lastSend = 0

local function findControls()
	local playerUI = playerGui:FindFirstChild("PlayerUI")
	if not playerUI then
		return false
	end
	local settings = playerUI:FindFirstChild("settings_frame")
	if not settings then
		return false
	end
	local dayNight = settings:FindFirstChild("day_night_frame", true)
	if not dayNight then
		return false
	end
	local button = dayNight:FindFirstChild("scroll_button", true)
	if not button then
		return false
	end
	refs.frame = dayNight
	refs.button = button
	if refs.button.AnchorPoint == Vector2.new() then
		refs.button.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.button.Position = UDim2.new(0, refs.button.AbsoluteSize.X * 0.5, 0.5, 0)
	end
	return true
end

local function sendClock(clockTime)
	local now = os.clock()
	if now - lastSend < 0.1 then
		return
	end
	lastSend = now
	setEvent:FireServer({ clockTime = clockTime })
end

local function setRatio(ratio)
	if not refs.frame or not refs.button then
		return
	end
	local r = math.clamp(ratio, 0, 1)
	refs.button.Position = UDim2.new(r, 0, 0.5, 0)
	-- Map 0 (left) = day (ClockTime ~12), 1 (right) = night (ClockTime ~0).
	local clock = 12 * (1 - r)
	sendClock(clock)
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

	-- Default to day.
	setRatio(0)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

bind()
