local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local toggleFn = remotes:WaitForChild("auto_flags")

local PlayerUI = require(script.Parent.playerui_controller)

local ON_COLOR = Color3.fromRGB(93, 255, 107)
local OFF_COLOR = Color3.fromRGB(255, 94, 94)

local enabled = false

local function setLabel()
	local label = PlayerUI.GetAutoTilesLabel()
	if label and label:IsA("TextLabel") then
		label.Text = enabled and "Auto Tiles On" or "Auto Tiles"
	end
end

local function updateVisual()
	local button = PlayerUI.GetAutoTilesButton()
	if button then
		button.BackgroundColor3 = enabled and ON_COLOR or OFF_COLOR
	end
	setLabel()
end

local function syncServer()
	pcall(function()
		toggleFn:InvokeServer({ tiles = enabled })
	end)
end

local function onPress()
	enabled = not enabled
	updateVisual()
	syncServer()
end

local function bind()
	local button = PlayerUI.GetAutoTilesButton()
	if not button or not button.Activated then
		return
	end
	if button:GetAttribute("auto_tiles_bound") then
		return
	end
	button:SetAttribute("auto_tiles_bound", true)
	enabled = false
	updateVisual()
	button.Activated:Connect(onPress)
end

Players.LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

bind()
