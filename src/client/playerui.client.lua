local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)
local Inventory = require(script.Parent.inventory)
local PurchasePrompt = require(script.Parent.purchase_prompt)
local Notifier = require(script.Parent.notifier)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local PlacementMode = require(script.Parent.placementmode_state)
local Selection = require(script.Parent.placement_selection)
local PlayerUI = require(script.Parent.playerui_controller)

local selectionConn

local function highlightCurrent()
	local cur = Selection.GetCurrent()
	if cur then
		PlayerUI.HighlightTier(cur.tier)
		PlayerUI.SetTierAmount(cur.tier, Inventory.GetCount(cur.machineType, cur.tier))
	end
end

local function enterPlacementForSelection(trigger, cur)
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

local function startBuild(trigger)
	PlayerUI.ShowBuildMenu()
	Inventory.EnsureStarter()

	local cur = Selection.GetCurrent()
	if not cur then
		debugutil.log("ui", "warn", "build_no_selection", { trigger = trigger })
		return
	end
	local player = game:GetService("Players").LocalPlayer
	local cashPerSecond = player and player:GetAttribute("CashPerSecond") or 0
	if not Inventory.Has(cur.machineType, cur.tier) then
		local price = EconomyConfig.GetMachinePrice(cur.machineType, cur.tier, cashPerSecond)
		PurchasePrompt.Prompt(cur.machineType, cur.tier, price, function(result)
			if result and result.accepted then
				local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
				local spendCashFn = remotes:FindFirstChild("spend_cash")
				if spendCashFn then
					local ok = spendCashFn:InvokeServer(price)
					if not ok then
						Notifier.Insufficient()
						return
					end
				end
				Inventory.Add(cur.machineType, cur.tier, 1)
				PlayerUI.SetTierAmount(cur.tier, Inventory.GetCount(cur.machineType, cur.tier))
				enterPlacementForSelection(trigger, cur)
			else
				debugutil.log("ui", "warn", "purchase_declined", { trigger = trigger, tier = cur.tier })
			end
		end)
		return
	end

	enterPlacementForSelection(trigger, cur)
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

local tierButtons = PlayerUI.GetTierButtons()
local function refreshAllTierAmounts()
	for tier = 1, 10 do
		PlayerUI.SetTierAmount(tier, Inventory.GetCount("generator", tier))
	end
end

if tierButtons then
	for tier, button in pairs(tierButtons) do
		button.Activated:Connect(function()
			Selection.SetTier(tier)
			if not PlacementMode.IsActive() then
				startBuild("tier_button")
			end
		end)
	end
else
	debugutil.log("ui", "warn", "tier_buttons_missing", {})
end
refreshAllTierAmounts()

selectionConn = Selection.ConnectChanged(function()
	highlightCurrent()
end)
highlightCurrent()

Inventory.ConnectChanged(function(machineType, tier, count)
	if machineType == "generator" then
		PlayerUI.SetTierAmount(tier, count)
	end
end)

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
