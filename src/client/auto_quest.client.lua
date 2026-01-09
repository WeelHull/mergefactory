local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local requestFn = remotes:WaitForChild("quest_request")

local PlayerUI = require(script.Parent.playerui_controller)
local Notifier = require(script.Parent.notifier)

local ON_COLOR = Color3.fromRGB(93, 255, 107)
local OFF_COLOR = Color3.fromRGB(255, 94, 94)
local POLL_DELAY = 3

local enabled = false
local loopRunning = false

local function setLabel()
	local label = PlayerUI.GetAutoQuestLabel()
	if label and label:IsA("TextLabel") then
		label.Text = enabled and "Auto Quest On" or "Auto Quest"
	end
end

local function tickOnce()
	local ok, result = pcall(function()
		return requestFn:InvokeServer({ action = "claim_all" })
	end)
	if not ok then
		return false
	end
	if not result or result.success ~= true then
		return false
	end
	if result.claimed and result.claimed > 0 then
		Notifier.Show("Claimed " .. tostring(result.claimed) .. " quests")
	end
	return true
end

local function runLoop()
	if loopRunning then
		return
	end
	loopRunning = true
	while enabled do
		tickOnce()
		task.wait(POLL_DELAY)
	end
	loopRunning = false
end

local function updateButtonVisual()
	local button = PlayerUI.GetAutoQuestButton()
	if not button then
		return
	end
	button.BackgroundColor3 = enabled and ON_COLOR or OFF_COLOR
	setLabel()
end

local function onPress()
	enabled = not enabled
	updateButtonVisual()
	if enabled then
		runLoop()
	end
end

local function bind()
	local button = PlayerUI.GetAutoQuestButton()
	if not button or not button.Activated then
		return
	end
	if button:GetAttribute("auto_quest_bound") then
		return
	end
	button:SetAttribute("auto_quest_bound", true)
	enabled = false
	updateButtonVisual()
	button.Activated:Connect(onPress)
end

Players.LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

bind()
