local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlacementMode = require(script.Parent.placementmode_state)
local Instruction = require(script.Parent.placement_instruction_controller)

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Feedback = {}

local gui = Instance.new("ScreenGui")
gui.Name = "placement_feedback"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local function addStroke(label, color)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local stateLabel = Instance.new("TextLabel")
stateLabel.BackgroundTransparency = 1
stateLabel.TextColor3 = Color3.new(1, 1, 1)
stateLabel.TextStrokeTransparency = 0
stateLabel.Text = "Placement active"
stateLabel.Font = Enum.Font.GothamBold
stateLabel.TextSize = 16
stateLabel.AnchorPoint = Vector2.new(0.5, 0.5)
stateLabel.Position = UDim2.new(0.5, 0, 0.82, 0)
stateLabel.Parent = gui
addStroke(stateLabel)

local invalidLabel = Instance.new("TextLabel")
invalidLabel.BackgroundTransparency = 1
invalidLabel.TextColor3 = Color3.fromRGB(220, 80, 80)
invalidLabel.TextStrokeTransparency = 0
invalidLabel.Text = ""
invalidLabel.Font = Enum.Font.GothamBold
invalidLabel.TextSize = 16
invalidLabel.AnchorPoint = Vector2.new(0.5, 0.5)
invalidLabel.Position = UDim2.new(0.5, 0, 0.88, 0)
invalidLabel.Visible = false
invalidLabel.Parent = gui
addStroke(invalidLabel, Color3.fromRGB(0, 0, 0))

local lastShow = 0
local cooldown = 0.3
local duration = 3

function Feedback.Show(_message)
	local now = os.clock()
	if now - lastShow < cooldown then
		return
	end
	lastShow = now
	Instruction.setPlaceholder("placement_active")
end

function Feedback.ShowInvalidPlacement(reason)
	if not PlacementMode.IsActive() then
		debugutil.log("placement", "warn", "invalid placement feedback blocked", { reason = "placement_inactive" })
		return
	end
	lastShow = os.clock()
	debugutil.log("placement", "state", "invalid placement feedback shown", {})
	if reason == "tile_locked" then
		Instruction.setPlaceholder("invalid_locked")
	else
	Instruction.setPlaceholder(reason == "tile_locked" and "invalid_locked" or "invalid_generic")
end
end

return Feedback
