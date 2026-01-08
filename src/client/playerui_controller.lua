local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local PlayerUI = {}
local previewsFolder = ReplicatedStorage:FindFirstChild("previews")
local previewConnections = {}

local refs = {
	playerUI = nil,
	menuButtons = nil,
	buildFrame = nil,
	buildButton = nil,
	closeButton = nil,
	rotationOption = nil,
	rotationButton = nil,
	rebirthButton = nil,
	settingsButton = nil,
	shopButton = nil,
	rebirthFrame = nil,
	settingsFrame = nil,
	shopFrame = nil,
	tierButtons = nil,
	tierAmounts = nil,
	cashFrame = nil,
	cashAmountLabel = nil,
	cashPerSecondLabel = nil,
}

local warnedMissing = false
local tierPreviewSeeded = false

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

local function setupTierPreview(btn, machineType, tier)
	if not btn then
		return
	end
	local viewport = btn:FindFirstChild("machine_view")
	if not viewport or not viewport:IsA("ViewportFrame") then
		return
	end

	local world = viewport:FindFirstChildOfClass("WorldModel")
	if not world then
		world = Instance.new("WorldModel")
		world.Name = "PreviewWorld"
		world.Parent = viewport
	end

	for _, child in ipairs(world:GetChildren()) do
		child:Destroy()
	end

	local previewName = tostring(machineType) .. "_t" .. tostring(tier)
	local preview = previewsFolder and previewsFolder:FindFirstChild(previewName)
	if not preview or not preview:IsA("Model") then
		return
	end

	local model = preview:Clone()
	model.Parent = world
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local camera = viewport.CurrentCamera
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end

	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = math.max(4, maxDim * 1.35)
	local lookAt = cf.Position
	camera.CFrame = CFrame.new(lookAt + Vector3.new(dist, dist * 0.25, dist), lookAt)

	-- slow rotate
	local angle = 0
	if previewConnections[viewport] then
		previewConnections[viewport]:Disconnect()
	end
	local conn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * math.rad(20)
		local offset = Vector3.new(math.cos(angle) * dist, dist * 0.25, math.sin(angle) * dist)
		camera.CFrame = CFrame.new(lookAt + offset, lookAt)
	end)
	previewConnections[viewport] = conn
end

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
		refs.rebirthFrame = refs.rebirthFrame or refs.playerUI:FindFirstChild("rebirth_frame")
		refs.settingsFrame = refs.settingsFrame or refs.playerUI:FindFirstChild("settings_frame")
		refs.shopFrame = refs.shopFrame or refs.playerUI:FindFirstChild("shop_frame")
		refs.buildButton = refs.buildButton or (refs.menuButtons and refs.menuButtons:FindFirstChild("build_button") or nil)
		if refs.menuButtons then
			refs.rebirthButton = refs.rebirthButton or refs.menuButtons:FindFirstChild("rebirth_button")
			refs.settingsButton = refs.settingsButton
				or refs.menuButtons:FindFirstChild("setting_button")
				or refs.menuButtons:FindFirstChild("settings_button")
			refs.shopButton = refs.shopButton or refs.menuButtons:FindFirstChild("shop_button")
		end
		refs.cashFrame = refs.cashFrame or refs.playerUI:FindFirstChild("cash_frame")
		if refs.cashFrame then
			refs.cashAmountLabel = refs.cashAmountLabel or refs.cashFrame:FindFirstChild("cash_amount") or refs.cashFrame:FindFirstChildWhichIsA("TextLabel")
			refs.cashPerSecondLabel = refs.cashPerSecondLabel or refs.cashFrame:FindFirstChild("cash_persecond")
		end
		local machineMenu = refs.buildFrame and refs.buildFrame:FindFirstChild("machine_menu") or nil
		refs.closeButton = refs.closeButton or (machineMenu and machineMenu:FindFirstChild("close") or nil)
		if not refs.tierButtons then
			local scroll = machineMenu and machineMenu:FindFirstChild("ScrollingFrame")
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
						setupTierPreview(btn, "generator", tier)
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

function PlayerUI.GetRebirthButton()
	ensureRefs()
	return refs.rebirthButton
end

function PlayerUI.GetSettingsButton()
	ensureRefs()
	return refs.settingsButton
end

function PlayerUI.GetShopButton()
	ensureRefs()
	return refs.shopButton
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
		refs.cashAmountLabel.Text = formatCompact(amount) .. " C$"
	end
end

function PlayerUI.SetCashPerSecond(amount)
	if not ensureRefs() then
		return
	end
	if refs.cashPerSecondLabel and refs.cashPerSecondLabel:IsA("TextLabel") then
		refs.cashPerSecondLabel.Text = formatCompact(amount) .. " C$/S"
	end
end

function PlayerUI.ShowBuildMenu()
	if not ensureRefs() then
		return
	end
	PlayerUI.HideAllMenus(refs.buildFrame)
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

function PlayerUI.HideAllMenus(exceptFrame)
	if not ensureRefs() then
		return
	end
	local targets = {
		refs.rebirthFrame,
		refs.settingsFrame,
		refs.shopFrame,
		refs.buildFrame,
	}
	for _, frame in ipairs(targets) do
		if frame and typeof(frame.Visible) == "boolean" then
			if exceptFrame and frame == exceptFrame then
				-- leave as-is
			else
				frame.Visible = false
			end
		end
	end
end

function PlayerUI.ToggleRebirthMenu()
	if not ensureRefs() then
		return
	end
	local frame = refs.rebirthFrame
	if not frame or typeof(frame.Visible) ~= "boolean" then
		return
	end
	local shouldShow = not frame.Visible
	PlayerUI.HideAllMenus(shouldShow and frame or nil)
	frame.Visible = shouldShow
end

function PlayerUI.ToggleSettingsMenu()
	if not ensureRefs() then
		return
	end
	local frame = refs.settingsFrame
	if not frame or typeof(frame.Visible) ~= "boolean" then
		return
	end
	local shouldShow = not frame.Visible
	PlayerUI.HideAllMenus(shouldShow and frame or nil)
	frame.Visible = shouldShow
end

function PlayerUI.ToggleShopMenu()
	if not ensureRefs() then
		return
	end
	local frame = refs.shopFrame
	if not frame or typeof(frame.Visible) ~= "boolean" then
		return
	end
	local shouldShow = not frame.Visible
	PlayerUI.HideAllMenus(shouldShow and frame or nil)
	frame.Visible = shouldShow
end

return PlayerUI
