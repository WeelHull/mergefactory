local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PurchasePrompt = {}

local gui
local messageLabel
local coinsCostLabel
local robuxCostLabel
local frame
local coinButton
local robuxButton
local cancelButton
local busy = false
local pendingCallback

local function formatCompact(amount)
	local n = tonumber(amount) or 0
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
	else
		value = math.floor(value)
	end
	return tostring(value) .. suffix
end

local function finish(result)
	if pendingCallback then
		pendingCallback(result)
	end
	pendingCallback = nil
	if gui then
		gui.Enabled = false
	end
	if frame then
		frame.Visible = false
	end
	busy = false
end

local function ensureUI()
	if gui then
		return true
	end

	gui = playerGui:FindFirstChild("purchase_prompt") or playerGui:WaitForChild("purchase_prompt", 5)
	if not gui then
		warn("purchase_prompt gui not found in PlayerGui")
		return false
	end

	frame = gui:FindFirstChild("purchase_frame") or gui:FindFirstChildWhichIsA("Frame", true)
	if not frame then
		warn("purchase_frame not found under purchase_prompt")
		return false
	end

	messageLabel = frame:FindFirstChild("message")
		or frame:FindFirstChild("label")
		or frame:FindFirstChildWhichIsA("TextLabel", true)
	coinsCostLabel = frame:FindFirstChild("coins_cost", true)
	robuxCostLabel = frame:FindFirstChild("robux_cost", true)
	coinButton = frame:FindFirstChild("coins", true)
	robuxButton = frame:FindFirstChild("robux", true)
	cancelButton = frame:FindFirstChild("cancel", true)

	if not (coinButton and robuxButton and cancelButton) then
		warn("purchase_prompt buttons missing (coins/robux/cancel)")
		return false
	end

	if gui:IsA("ScreenGui") then
		gui.Enabled = false
	end
	frame.Visible = false

	coinButton.Activated:Connect(function()
		finish({ accepted = true, method = "coins" })
	end)

	robuxButton.Activated:Connect(function()
		finish({ accepted = true, method = "robux" })
	end)

	cancelButton.Activated:Connect(function()
		finish({ accepted = false, method = "cancel" })
	end)

	return true
end

function PurchasePrompt.Prompt(machineType, tier, price, callback)
	if not ensureUI() then
		return
	end
	if busy then
		finish({ accepted = false, method = "replaced" })
	end
	busy = true
	pendingCallback = callback
	if messageLabel then
		local t = tonumber(tier) or 0
		local p = tonumber(price) or 0
		if p > 0 then
			messageLabel.Text = string.format("You have 0 of Tier %d. Purchase for %s C$ to place?", t, formatCompact(p))
		else
			messageLabel.Text = string.format("You have 0 of Tier %d. Purchase one to place?", t)
		end
	end
	if coinsCostLabel and coinsCostLabel:IsA("TextLabel") then
		if price and price > 0 then
			coinsCostLabel.Text = formatCompact(price) .. " C$"
		else
			coinsCostLabel.Text = "--"
		end
	end
	if robuxCostLabel and robuxCostLabel:IsA("TextLabel") then
		robuxCostLabel.Text = "N/A"
	end
	if gui then
		gui.Enabled = true
	end
	if frame then
		frame.Visible = true
	end
end

return PurchasePrompt
