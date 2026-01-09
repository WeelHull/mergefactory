local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local refs = {
	popup = nil,
	template = nil,
}

local rand = Random.new()
local lastCash = player:GetAttribute("Cash") or 0
local baseSize
local MAX_COINS = 5
local MIN_CHUNK = 25 -- split large gains into a handful of coins
local FADE_IN_TIME = 0.25
local FLOAT_TIME = 0.7
local FADE_OUT_TIME = 0.3

local function formatNumber(n)
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
		return tostring(value) .. suffix
	end

	return tostring(math.floor(n))
end

local function applyTransparency(ui, value)
	if ui:IsA("ImageLabel") or ui:IsA("ImageButton") then
		ui.ImageTransparency = value
	end
	if ui:IsA("Frame") or ui:IsA("TextLabel") or ui:IsA("TextButton") then
		if ui.BackgroundTransparency ~= nil then
			ui.BackgroundTransparency = value
		end
	end
	local amountLabel = ui:FindFirstChild("amount", true)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.TextTransparency = value
	end
end

local function tweenTransparency(ui, target, duration, style)
	if not ui then
		return
	end
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if ui:IsA("ImageLabel") or ui:IsA("ImageButton") then
		TweenService:Create(ui, info, { ImageTransparency = target }):Play()
	elseif ui:IsA("Frame") or ui:IsA("TextLabel") or ui:IsA("TextButton") then
		if ui.BackgroundTransparency ~= nil then
			TweenService:Create(ui, info, { BackgroundTransparency = target }):Play()
		end
	end
	local amountLabel = ui:FindFirstChild("amount", true)
	if amountLabel and amountLabel:IsA("TextLabel") then
		TweenService:Create(amountLabel, info, { TextTransparency = target }):Play()
	end
end

local function tryResolve()
	if refs.popup and refs.popup.Parent and refs.template and refs.template.Parent then
		return true
	end
	local ui = playerGui:FindFirstChild("PlayerUI")
	if not ui then
		return false
	end
	refs.popup = ui:FindFirstChild("coin_popup", true)
	if not refs.popup then
		return false
	end
	refs.template = refs.popup:FindFirstChild("coins_image", true)
	if not refs.template then
		return false
	end
	refs.template.Visible = false
	baseSize = refs.template.Size
	return true
end

local function setVisible(state)
	if refs.popup then
		refs.popup.Visible = state
	end
	if refs.template then
		refs.template.Visible = false
	end
end

local function spawnCoin(text)
	if not tryResolve() then
		return
	end
	local containerSize = refs.popup.AbsoluteSize
	local templateSize = baseSize or refs.template.Size
	if containerSize.X <= 0 or containerSize.Y <= 0 then
		return
	end

	local coin = refs.template:Clone()
	coin.Visible = true
	coin.Parent = refs.popup
	coin.Rotation = rand:NextNumber(-8, 8)
	coin.Size = templateSize

	local amountLabel = coin:FindFirstChild("amount", true)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = text
	end

	-- Start slightly shrunken and fully transparent.
	local startScale = 0.6
	coin.Size = UDim2.new(
		templateSize.X.Scale * startScale,
		templateSize.X.Offset * startScale,
		templateSize.Y.Scale * startScale,
		templateSize.Y.Offset * startScale
	)
	applyTransparency(coin, 1)

	-- Random position inside container.
	local maxX = math.max(0, containerSize.X - templateSize.X.Offset)
	local maxY = math.max(0, containerSize.Y - templateSize.Y.Offset)
	local x = rand:NextNumber(0, maxX)
	local y = rand:NextNumber(0, maxY)
	coin.Position = UDim2.new(0, x, 0, y)

	-- Float up and fade out.
	local floatOffset = rand:NextNumber(30, 60)
	local targetPos = UDim2.new(0, x, 0, y - floatOffset)

	local fadeIn = TweenService:Create(
		coin,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = templateSize,
		}
	)
	local floatTween = TweenService:Create(
		coin,
		TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			Position = targetPos,
			Rotation = 0,
		}
	)
	local fadeOut = TweenService:Create(
		coin,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{}
	)

	fadeOut.Completed:Connect(function()
		coin:Destroy()
	end)

	fadeIn.Completed:Connect(function()
		floatTween:Play()
	end)
	floatTween.Completed:Connect(function()
		tweenTransparency(coin, 1, FADE_OUT_TIME, Enum.EasingStyle.Quad)
		fadeOut:Play()
	end)

	-- Kick off fade-in and show.
	tweenTransparency(coin, 0, FADE_IN_TIME, Enum.EasingStyle.Quad)
	fadeIn:Play()
end

local function onCashChanged()
	if not tryResolve() then
		return
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	if cps <= 0 then
		return
	end

	local current = player:GetAttribute("Cash") or 0
	local delta = current - lastCash
	lastCash = current
	if delta <= 0 then
		return
	end

	local pieces = math.clamp(math.ceil(delta / math.max(MIN_CHUNK, 1)), 1, MAX_COINS)
	local baseChunk = math.max(1, math.floor(delta / pieces))
	local remainder = delta - baseChunk * pieces
	for i = 1, pieces do
		local chunk = baseChunk + (i <= remainder and 1 or 0)
		spawnCoin("+" .. formatNumber(chunk) .. " C$")
	end
end

local function updateActive()
	local cps = player:GetAttribute("CashPerSecond") or 0
	if cps > 0 and tryResolve() then
		setVisible(true)
	else
		setVisible(false)
	end
end

player:GetAttributeChangedSignal("Cash"):Connect(onCashChanged)
player:GetAttributeChangedSignal("CashPerSecond"):Connect(updateActive)

tryResolve()
updateActive()
