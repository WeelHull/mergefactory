local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local refs = {
	frame = nil,
	button = nil,
}

local dragging = false
local NEAR_MIN = 60
local NEAR_MAX = 200
local FAR_MIN = 120
local FAR_MAX = 700

local function findControls()
	local playerUI = playerGui:FindFirstChild("PlayerUI")
	if not playerUI then
		return false
	end
	local settings = playerUI:FindFirstChild("settings_frame")
	if not settings then
		return false
	end
	local radiusFrame = settings:FindFirstChild("radius_frame", true)
	if not radiusFrame then
		return false
	end
	local button = radiusFrame:FindFirstChild("scroll_button", true)
	if not button then
		return false
	end
	refs.frame = radiusFrame
	refs.button = button
	return true
end

local function applyRadius(ratio)
	local near = NEAR_MAX - (NEAR_MAX - NEAR_MIN) * ratio
	local far = FAR_MAX - (FAR_MAX - FAR_MIN) * ratio
	player:SetAttribute("MachineLODNear", math.floor(near))
	player:SetAttribute("MachineLODFar", math.floor(far))
end

local function setRatio(ratio)
	if not refs.frame or not refs.button then
		return
	end
	local r = math.clamp(ratio, 0, 1)
	refs.button.Position = UDim2.new(r, 0, 0.5, 0)
	applyRadius(r)
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

	-- Default: far left (show more machines).
	setRatio(0)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

bind()
