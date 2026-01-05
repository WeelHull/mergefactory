local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Notifier = {}

local gui
local label
local hideConnection

local function ensureGui()
	if gui then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "notifier"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui

	label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Position = UDim2.new(0, 0, 0, 10)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.Visible = false
	label.Parent = gui
end

function Notifier.Insufficient()
	ensureGui()
	if not label then
		return
	end
	label.Text = "Insufficient Funds!!"
	label.Visible = true
	if hideConnection then
		hideConnection:Disconnect()
	end
	hideConnection = nil
	task.delay(2, function()
		if label then
			label.Visible = false
		end
	end)
end

return Notifier
