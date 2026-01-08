-- merge_prompt client controller: shows merge confirmation UI and routes decisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local mergeOfferEvent = remotes:WaitForChild("merge_offer")
local mergeDecisionFn = remotes:WaitForChild("merge_decision")

local PlacementMode = require(script.Parent.placementmode_state)
local MachineInteractionState = require(script.Parent.machineinteraction_state)
local Notifier = require(script.Parent.notifier)
local debugutil = require(ReplicatedStorage.Shared.debugutil)

local playerGui = player:WaitForChild("PlayerGui")

local function forceClosePurchasePrompt()
	local pg = playerGui
	local purchaseGui = pg and pg:FindFirstChild("purchase_prompt")
	if purchaseGui and purchaseGui:IsA("ScreenGui") then
		purchaseGui.Enabled = false
	end
	local pf = purchaseGui and (purchaseGui:FindFirstChild("purchase_frame") or purchaseGui:FindFirstChildWhichIsA("Frame", true))
	if pf then
		pf.Visible = false
	end
end

local gui
local frame
local cancelBtn
local coinsBtn
local coinsCostLabel
local cancelConn
local coinsConn
local handleDecision
local hidePrompt

local currentOffer

local function resolveGui()
	if gui and gui.Parent == playerGui then
		return true
	end
	gui = playerGui:FindFirstChild("merge_prompt") or playerGui:WaitForChild("merge_prompt", 2)
	if not gui then
		debugutil.log("merge", "warn", "merge_prompt_gui_missing", {})
		return false
	end
	frame = gui:FindFirstChild("merge_frame") or gui:WaitForChild("merge_frame", 2)
	cancelBtn = frame and frame:FindFirstChild("cancel", true)
	coinsBtn = frame and frame:FindFirstChild("coins", true)
	coinsCostLabel = frame and frame:FindFirstChild("coins_cost", true)
	if frame then
		frame.Visible = false
	end
	gui.Enabled = false

	if cancelConn then
		cancelConn:Disconnect()
		cancelConn = nil
	end
	if coinsConn then
		coinsConn:Disconnect()
		coinsConn = nil
	end

	if cancelBtn and cancelBtn:IsA("GuiButton") then
		cancelConn = cancelBtn.Activated:Connect(function()
			handleDecision("cancel")
		end)
	end

	if coinsBtn and coinsBtn:IsA("GuiButton") then
		coinsConn = coinsBtn.Activated:Connect(function()
			handleDecision("coin")
		end)
	end

	return true
end

local function formatCompact(n)
	n = tonumber(n) or 0
	local abs = math.abs(n)
	local suffix = ""
	local value = n
	if abs >= 1_000_000_000 then
		value = n / 1_000_000_000
		suffix = "B"
	elseif abs >= 1_000_000 then
		value = n / 1_000_000
		suffix = "M"
	elseif abs >= 1_000 then
		value = n / 1_000
		suffix = "K"
	end
	if suffix ~= "" then
		value = math.floor(value * 10 + 0.5) / 10
	end
	return tostring(value) .. suffix
end

function hidePrompt()
	if frame then
		frame.Visible = false
	end
	if gui then
		gui.Enabled = false
	end
	currentOffer = nil
end

local function clearSelection(reason)
	local api = _G._machineInteractionAPI
	if api and api.ClearSelection then
		api.ClearSelection(reason)
	end
end

local function showPrompt(offer)
	if not resolveGui() then
		return
	end
	currentOffer = offer
	if coinsCostLabel and coinsCostLabel:IsA("TextLabel") then
		coinsCostLabel.Text = formatCompact(offer.price or 0)
	end
	if frame then
		frame.Visible = true
	end
	if gui then
		gui.Enabled = true
	end
	forceClosePurchasePrompt()
end

function handleDecision(action)
	if not currentOffer then
		return
	end
	forceClosePurchasePrompt()
	local payload = {
		sourceId = currentOffer.sourceId,
		targetId = currentOffer.targetId,
	}
	local ok, result = pcall(function()
		return mergeDecisionFn:InvokeServer(action, payload)
	end)
	if not ok or not result then
		Notifier.Insufficient()
		return
	end
	if result.success then
		Notifier.Show("Merged", 1.5)
		hidePrompt()
		MachineInteractionState.SetRelocating(false, "merge_complete")
		PlacementMode.RequestCancel()
		return
	end

	if result.reason == "insufficient_funds" then
		Notifier.Insufficient()
		clearSelection("merge_insufficient")
	elseif result.reason == "cancelled" then
		PlacementMode.RequestCancel()
		MachineInteractionState.SetRelocating(false, "merge_cancelled")
		clearSelection("merge_cancelled")
	end
	hidePrompt()
end

mergeOfferEvent.OnClientEvent:Connect(function(offer)
	if not offer then
		return
	end
	debugutil.log("merge", "state", "merge_offer_received", offer)
	-- ensure any other UI is hidden to avoid overlap
	hidePrompt()
	PlacementMode.RequestCancel()
	showPrompt(offer)
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "merge_prompt" then
		gui = nil
		resolveGui()
	end
end)

resolveGui()
