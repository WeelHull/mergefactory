local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- binding state
local feedbackGui: ScreenGui? = nil
local label: TextLabel? = nil
local uiReady = false

local function bindUi(gui)
	local lbl = gui:FindFirstChild("TextLabel")
	if not lbl or not lbl:IsA("TextLabel") then
		return
	end
	feedbackGui = gui
	label = lbl
	label.Text = ""
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Position = UDim2.new(0.5, 0, 0.9, 0)
	feedbackGui.Enabled = false
	uiReady = true
	debugutil.log("ux", "init", "instruction_ui_bound", { path = feedbackGui:GetFullName() })
end

-- attempt immediate bind
local existing = playerGui:FindFirstChild("placement_feedback")
if existing and existing:IsA("ScreenGui") then
	bindUi(existing)
else
	playerGui.ChildAdded:Connect(function(child)
		if uiReady then
			return
		end
		if child.Name == "placement_feedback" and child:IsA("ScreenGui") then
			bindUi(child)
		end
	end)
end

local currentText = ""
local lastDeniedReason = nil
local terminalLocked = false
local setPlaceholder -- forward declaration

local function logSet(placeholder, text)
	debugutil.log("ux", "state", "instruction_set", { placeholder = placeholder or "direct", text = text })
end

local function logClear(reason)
	debugutil.log("ux", "state", "instruction_clear", { reason = reason or "unspecified" })
end

local function show(text, placeholder)
	if not uiReady then
		return
	end
	if terminalLocked and placeholder ~= "instruction_clear" then
		return
	end
	if currentText ~= text then
		currentText = text
		logSet(placeholder, text)
	end
	label.Text = text
	feedbackGui.Enabled = true
	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0, TextStrokeTransparency = 0.3 }):Play()
end

local function fadeOut(reason, duration)
	if not uiReady then
		return
	end
	terminalLocked = false
	currentText = ""
	logClear(reason)
	TweenService:Create(label, TweenInfo.new(duration or 0.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(duration or 0.2, function()
		if currentText == "" then
			feedbackGui.Enabled = false
		end
	end)
end

local function morph(text, holdTime, placeholder)
	if not uiReady then
		return
	end
	show(text, placeholder)
	if holdTime and holdTime > 0 then
		task.delay(holdTime, function()
			if currentText == text then
				fadeOut("morph_timeout", 0.25)
			end
		end)
	end
end

-- observe existing placement logs without changing behavior
local originalLog = debugutil.log
debugutil.log = function(system, level, message, data)
	originalLog(system, level, message, data)

	if system ~= "placement" then
		return
	end

	local reason = data and data.reason

	if level == "state" and message == "enter" then
		lastDeniedReason = nil
		if not terminalLocked then
			setPlaceholder("placement_active")
		end
	elseif level == "state" and message == "exit" then
		lastDeniedReason = nil
		-- exit when no terminal is active: clear immediately
		if not terminalLocked then
			fadeOut("placement_exit", 0.1)
		else
			setPlaceholder("cancel")
		end
	elseif level == "decision" and message == "confirm" then
		setPlaceholder("confirm")
	elseif level == "decision" and (message == "deny" or message == "canPlace") and data and data.allowed == false then
		lastDeniedReason = data.reason
	elseif level == "decision" and (message == "deny" or message == "canPlace") and data and data.allowed == true then
		lastDeniedReason = nil
	elseif level == "state" and message == "invalid placement feedback shown" then
		if lastDeniedReason == "tile_locked" then
			setPlaceholder("invalid_locked")
		else
			setPlaceholder("invalid_generic")
		end
	elseif level == "state" and message == "exit" and reason == "cancel" then
		setPlaceholder("cancel")
	end
end

function setPlaceholder(placeholder)
	-- enforce single terminal instruction per placement interaction
	local isTerminal = (placeholder == "confirm" or placeholder == "invalid_generic" or placeholder == "invalid_locked" or placeholder == "cancel")
	if terminalLocked and isTerminal then
		return
	end
	if terminalLocked and placeholder == "placement_active" then
		return
	end

	if placeholder == "placement_active" then
		show("Place your item", placeholder)
	elseif placeholder == "invalid_generic" then
		morph("You can’t place it here", 1.0, placeholder)
		terminalLocked = true
	elseif placeholder == "invalid_locked" then
		morph("Tile locked", 1.2, placeholder)
		terminalLocked = true
	elseif placeholder == "confirm" then
		morph("Placed", 0.8, placeholder)
		terminalLocked = true
	elseif placeholder == "cancel" then
		if not terminalLocked then
			morph("Placement cancelled", 1.0, placeholder)
			terminalLocked = true
		end
	else
		fadeOut("unknown_placeholder", 0.1)
	end
end

return {
	show = show,
	morph = morph,
	fadeOut = fadeOut,
	setPlaceholder = setPlaceholder,
}
