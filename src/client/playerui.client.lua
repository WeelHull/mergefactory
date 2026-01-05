local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)
local PlacementMode = require(script.Parent.placementmode_state)
local Selection = require(script.Parent.placement_selection)
local PlayerUI = require(script.Parent.playerui_controller)

local function startBuild(trigger)
	PlayerUI.ShowBuildMenu()

	local cur = Selection.GetCurrent()
	if not cur then
		debugutil.log("ui", "warn", "build_no_selection", { trigger = trigger })
		return
	end

	local ok = PlacementMode.RequestEnter({
		kind = "machine",
		machineType = cur.machineType,
		tier = cur.tier,
	})

	debugutil.log("ui", ok and "state" or "warn", "build_enter_request", {
		trigger = trigger,
		machineType = cur.machineType,
		tier = cur.tier,
		requested = ok,
	})
end

local buildButton = PlayerUI.GetBuildButton()
if buildButton then
	buildButton.Activated:Connect(function()
		startBuild("build_button")
	end)
else
	debugutil.log("ui", "warn", "build_button_missing", {})
end

local function closeBuild(trigger)
	PlayerUI.ShowMenuButtons()
	local cancelled = PlacementMode.RequestCancel()
	debugutil.log("ui", cancelled and "state" or "warn", "build_close_request", {
		trigger = trigger,
		cancelled = cancelled,
	})
end

local closeButton = PlayerUI.GetCloseButton()
if closeButton then
	closeButton.Activated:Connect(function()
		closeBuild("build_close_button")
	end)
else
	debugutil.log("ui", "warn", "build_close_missing", {})
end

local function rotateBuild(trigger)
	local rotated = PlacementMode.RequestRotate(90)
	debugutil.log("ui", rotated and "state" or "warn", "build_rotate_request", {
		trigger = trigger,
		rotated = rotated,
	})
end

local rotationButton = PlayerUI.GetRotationButton()
if rotationButton then
	rotationButton.Activated:Connect(function()
		rotateBuild("rotation_button")
	end)
else
	debugutil.log("ui", "warn", "rotation_button_missing", {})
end
