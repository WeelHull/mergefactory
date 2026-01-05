local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local PlayerUI = {}

local refs = {
	playerUI = nil,
	menuButtons = nil,
	buildFrame = nil,
	buildButton = nil,
	closeButton = nil,
	rotationOption = nil,
	rotationButton = nil,
	tierButtons = nil,
	tierAmounts = nil,
	cashFrame = nil,
	cashAmountLabel = nil,
	cashPerSecondLabel = nil,
}

local warnedMissing = false

local function ensureRefs()
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if not playerGui then
		if not warnedMissing then
			warnedMissing = true
			debugutil.log("ui", "warn", "playergui_missing", {})
		end
		return false
	end

	if not refs.playerUI or not refs.playerUI.Parent then
		local playerUI = playerGui:FindFirstChild("PlayerUI") or playerGui:WaitForChild("PlayerUI", 5)
		if not playerUI then
			if not warnedMissing then
				warnedMissing = true
				debugutil.log("ui", "warn", "playerui_missing", {})
			end
			return false
		end
		refs.playerUI = playerUI
	end

	if refs.playerUI then
		refs.menuButtons = refs.menuButtons or refs.playerUI:FindFirstChild("menu_buttons")
		refs.buildFrame = refs.buildFrame or refs.playerUI:FindFirstChild("build_frame")
		refs.buildButton = refs.buildButton or (refs.menuButtons and refs.menuButtons:FindFirstChild("build_button") or nil)
		refs.cashFrame = refs.cashFrame or refs.playerUI:FindFirstChild("cash_frame")
		if refs.cashFrame then
			refs.cashAmountLabel = refs.cashAmountLabel or refs.cashFrame:FindFirstChild("cash_amount") or refs.cashFrame:FindFirstChildWhichIsA("TextLabel")
			refs.cashPerSecondLabel = refs.cashPerSecondLabel or refs.cashFrame:FindFirstChild("cash_persecond")
		end
		local machineMenu = refs.buildFrame and refs.buildFrame:FindFirstChild("machine_menu") or nil
		refs.closeButton = refs.closeButton or (machineMenu and machineMenu:FindFirstChild("close") or nil)
		if not refs.tierButtons then
			local viewport = machineMenu and machineMenu:FindFirstChild("ViewportFrame")
			local scroll = viewport and viewport:FindFirstChild("ScrollingFrame")
			if scroll then
				local foundButtons = {}
				local foundLabels = {}
				for tier = 1, 10 do
					local name = "tier_" .. tostring(tier)
					local btn = scroll:FindFirstChild(name)
					if btn and (btn:IsA("ImageButton") or btn:IsA("TextButton")) then
						foundButtons[tier] = btn
						local amt = btn:FindFirstChild("x_amount") or btn:FindFirstChildWhichIsA("TextLabel")
						if amt then
							foundLabels[tier] = amt
						end
					end
				end
				if next(foundButtons) then
					refs.tierButtons = foundButtons
					refs.tierAmounts = foundLabels
				end
			end
		end
		if not refs.rotationOption then
			refs.rotationOption = refs.playerUI:FindFirstChild("rotation_option", true) or refs.playerUI:FindFirstChild("rotate_button", true)
		end
		if not refs.rotationOption then
			refs.rotationOption = playerGui:FindFirstChild("rotation_option", true) or playerGui:FindFirstChild("rotate_button", true)
		end
		if refs.rotationOption and not refs.rotationButton then
			if refs.rotationOption:IsA("ImageButton") or refs.rotationOption:IsA("TextButton") then
				refs.rotationButton = refs.rotationOption
			else
				refs.rotationButton = refs.rotationOption:FindFirstChildWhichIsA("ImageButton", true) or refs.rotationOption:FindFirstChildWhichIsA("TextButton", true)
			end
		end
	end

	return true
end

function PlayerUI.IsReady()
	return ensureRefs()
end

function PlayerUI.GetBuildButton()
	ensureRefs()
	return refs.buildButton
end

function PlayerUI.GetCloseButton()
	ensureRefs()
	return refs.closeButton
end

function PlayerUI.IsBuildMenuVisible()
	ensureRefs()
	return refs.buildFrame and refs.buildFrame.Visible or false
end

function PlayerUI.ShowRotationOption()
	if not ensureRefs() then
		return
	end
	if refs.rotationOption then
		if refs.rotationOption:IsA("BillboardGui") or refs.rotationOption:IsA("ScreenGui") then
			refs.rotationOption.Enabled = true
		elseif typeof(refs.rotationOption.Visible) == "boolean" then
			refs.rotationOption.Visible = true
		end
	end
	if refs.rotationButton and typeof(refs.rotationButton.Visible) == "boolean" then
		refs.rotationButton.Visible = true
	end
end

function PlayerUI.HideRotationOption()
	if not ensureRefs() then
		return
	end
	if refs.rotationOption then
		if refs.rotationOption:IsA("BillboardGui") or refs.rotationOption:IsA("ScreenGui") then
			refs.rotationOption.Enabled = false
		elseif typeof(refs.rotationOption.Visible) == "boolean" then
			refs.rotationOption.Visible = false
		end
	end
	if refs.rotationButton and typeof(refs.rotationButton.Visible) == "boolean" then
		refs.rotationButton.Visible = false
	end
end

function PlayerUI.SetRotationAdornee(part)
	if not ensureRefs() then
		return
	end
	if refs.rotationOption and refs.rotationOption:IsA("BillboardGui") then
		refs.rotationOption.Adornee = part
		if part and part:IsA("BasePart") then
			refs.rotationOption.StudsOffset = Vector3.new()
			refs.rotationOption.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y * 0.5 + 3, 0)
		end
	end
end

function PlayerUI.GetRotationButton()
	ensureRefs()
	return refs.rotationButton
end

function PlayerUI.GetTierButtons()
	ensureRefs()
	return refs.tierButtons
end

local function styleTierButton(btn, selected)
	if not btn then
		return
	end
	local stroke = btn:FindFirstChildWhichIsA("UIStroke", true)
	if stroke then
		stroke.Thickness = selected and 3 or 1
		stroke.Transparency = selected and 0 or 0.6
	end
	if typeof(btn.BorderSizePixel) == "number" then
		btn.BorderSizePixel = selected and 2 or 0
		btn.BorderColor3 = Color3.fromRGB(255, 255, 255)
	end
end

function PlayerUI.HighlightTier(tier)
	if not ensureRefs() or not refs.tierButtons then
		return
	end
	for t, btn in pairs(refs.tierButtons) do
		styleTierButton(btn, t == tier)
	end
end

function PlayerUI.SetTierAmount(tier, amount)
	if not ensureRefs() or not refs.tierAmounts then
		return
	end
	local label = refs.tierAmounts[tier]
	if label and label:IsA("TextLabel") then
		label.Text = "x" .. tostring(amount or 0)
	end
end

function PlayerUI.SetCash(amount)
	if not ensureRefs() then
		return
	end
	if refs.cashAmountLabel and refs.cashAmountLabel:IsA("TextLabel") then
		refs.cashAmountLabel.Text = tostring(math.floor(amount or 0)) .. " C$"
	end
end

function PlayerUI.SetCashPerSecond(amount)
	if not ensureRefs() then
		return
	end
	if refs.cashPerSecondLabel and refs.cashPerSecondLabel:IsA("TextLabel") then
		refs.cashPerSecondLabel.Text = tostring(math.floor(amount or 0)) .. " C$/S"
	end
end

function PlayerUI.ShowBuildMenu()
	if not ensureRefs() then
		return
	end
	if refs.menuButtons then
		refs.menuButtons.Visible = false
	end
	if refs.buildFrame then
		refs.buildFrame.Visible = true
	end
end

function PlayerUI.ShowMenuButtons()
	if not ensureRefs() then
		return
	end
	if refs.menuButtons then
		refs.menuButtons.Visible = true
	end
	if refs.buildFrame then
		refs.buildFrame.Visible = false
	end
end

return PlayerUI
