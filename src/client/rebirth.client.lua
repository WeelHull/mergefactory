local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Notifier = require(script.Parent.notifier)
local PlayerUI = require(script.Parent.playerui_controller)
local RebirthConfig = require(ReplicatedStorage.Shared.rebirth_config)
local Inventory = require(script.Parent.inventory)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local rebirthFn = remotes:WaitForChild("rebirth_request")

local frame
local progressBar
local loadingBar
local requirementLabel
local rebirthButton
local closeButton
local incomeLabel
local incomeCurrentLabel
local tilesLabel
local tilesCurrentLabel
local multiLabel
local multiCurrentLabel
local timerLabel
local stackLabel
local busy = false

local function formatCompact(n)
	n = tonumber(n) or 0
	local abs = math.abs(n)
	local units = {
		{ 1e12, "T" },
		{ 1e9, "B" },
		{ 1e6, "M" },
		{ 1e3, "K" },
	}
	for _, entry in ipairs(units) do
		local threshold, suffix = entry[1], entry[2]
		if abs >= threshold then
			local value = n / threshold
			value = math.floor(value * 10 + 0.5) / 10
			return tostring(value) .. suffix
		end
	end
	return tostring(math.floor(n + 0.5))
end

local function formatPercent(value)
	value = tonumber(value) or 0
	local rounded = math.floor(value * 10 + 0.5) / 10
	return tostring(rounded) .. "%"
end

local function ensureUi()
	local playerUI = playerGui:WaitForChild("PlayerUI", 5)
	if not playerUI then
		return false
	end

	frame = frame or playerUI:WaitForChild("rebirth_frame", 5)
	if not frame then
		return false
	end

	progressBar = progressBar or frame:WaitForChild("progress_bar", 5)
	if not progressBar then
		return false
	end

	loadingBar = loadingBar or progressBar:WaitForChild("loading_bar", 5)

	requirementLabel = requirementLabel
		or progressBar:FindFirstChild("requirement_label")
		or progressBar:FindFirstChild("requiment_label")
	if not requirementLabel then
		requirementLabel = progressBar:FindFirstChildWhichIsA("TextLabel") or progressBar:WaitForChild("requirement_label", 2)
	end

	rebirthButton = rebirthButton or frame:FindFirstChild("rebirth_button")
	if rebirthButton and not rebirthButton:IsA("GuiButton") then
		rebirthButton = rebirthButton:FindFirstChildWhichIsA("GuiButton", true) or rebirthButton
	end

	closeButton = closeButton or frame:FindFirstChild("close_menu")
	if closeButton and not closeButton:IsA("GuiButton") then
		closeButton = closeButton:FindFirstChildWhichIsA("GuiButton", true) or closeButton
	end

	incomeLabel = incomeLabel or frame:FindFirstChild("income_label")
	incomeCurrentLabel = incomeCurrentLabel or frame:FindFirstChild("speed_percent")
	tilesLabel = tilesLabel or frame:FindFirstChild("tiles_label")
	tilesCurrentLabel = tilesCurrentLabel or frame:FindFirstChild("tiles_percent")
	multiLabel = multiLabel or frame:FindFirstChild("multi_label")
	multiCurrentLabel = multiCurrentLabel or frame:FindFirstChild("multi_percent")
	timerLabel = timerLabel or frame:FindFirstChild("timer")
	stackLabel = stackLabel or frame:FindFirstChild("rebirth_stack")

	return frame ~= nil
end

local function simulateTokens(cash, rebirths)
	local tokens = 0
	local r = rebirths or 0
	local spend = 0
	while true do
		local cost = RebirthConfig.ComputeCost(r)
		if cash >= cost then
			cash -= cost
			spend += cost
			tokens += 1
			r += 1
		else
			break
		end
	end
	local nextCost = RebirthConfig.ComputeCost(r)
	local progress = math.clamp(cash, 0, nextCost)
	return tokens, progress, nextCost
end

local function getPreview()
	local tokensAttr = player:GetAttribute("RebirthStack")
	local progressAttr = player:GetAttribute("RebirthProgress")
	local costAttr = player:GetAttribute("RebirthNextCost")
	local cash = player:GetAttribute("Cash") or 0
	local rebirths = player:GetAttribute("Rebirths") or 0

	if typeof(tokensAttr) == "number" and typeof(costAttr) == "number" then
		local progress = typeof(progressAttr) == "number" and progressAttr or 0
		local clampedCost = math.max(1, costAttr)
		return tokensAttr, math.clamp(progress, 0, clampedCost), clampedCost
	end

	return simulateTokens(cash, rebirths)
end

local function updateProgress()
	if not ensureUi() then
		return
	end
	local rebirths = player:GetAttribute("Rebirths") or 0
	local tokens, progress, cost = getPreview()
	if requirementLabel and requirementLabel:IsA("TextLabel") then
		requirementLabel.Text = string.format("%s / %s C$", formatCompact(progress), formatCompact(cost))
	end
	if loadingBar then
		local yScale = loadingBar.Size.Y.Scale
		local yOffset = loadingBar.Size.Y.Offset
		local pct = cost > 0 and math.clamp(progress / cost, 0, 1) or 1
		loadingBar.Size = UDim2.new(pct, 0, yScale, yOffset)
	end
	local current = RebirthConfig.ComputeMultipliers(rebirths)
	local nextMult = RebirthConfig.ComputeMultipliers(rebirths + 1)

	local incomeDelta = (nextMult.income - current.income) * 100
	local tileDelta = (nextMult.tileDiscount - current.tileDiscount) * 100
	local prodDelta = (nextMult.production - current.production) * 100

	if incomeLabel and incomeLabel:IsA("TextLabel") then
		incomeLabel.Text = "Next income-per-second increase: +" .. formatPercent(incomeDelta)
	end
	if incomeCurrentLabel and incomeCurrentLabel:IsA("TextLabel") then
		incomeCurrentLabel.Text = formatPercent((current.income - 1) * 100)
	end
	if tilesLabel and tilesLabel:IsA("TextLabel") then
		tilesLabel.Text = "Next tile discount: +" .. formatPercent(tileDelta)
	end
	if tilesCurrentLabel and tilesCurrentLabel:IsA("TextLabel") then
		tilesCurrentLabel.Text = formatPercent(current.tileDiscount * 100)
	end
	if multiLabel and multiLabel:IsA("TextLabel") then
		multiLabel.Text = "Next multiplier: +" .. formatPercent(prodDelta)
	end
	if multiCurrentLabel and multiCurrentLabel:IsA("TextLabel") then
		multiCurrentLabel.Text = formatPercent((current.production - 1) * 100)
	end
	if stackLabel and stackLabel:IsA("TextLabel") then
		stackLabel.Text = tostring(tokens) .. "x"
	end
	if timerLabel and timerLabel:IsA("TextLabel") then
		local cps = player:GetAttribute("CashPerSecond") or 0
		local remaining = cost - progress
		if remaining <= 0 then
			timerLabel.Text = "Ready"
		elseif cps <= 0 then
			timerLabel.Text = "--"
		else
			local seconds = math.ceil(remaining / cps)
			local hours = math.floor(seconds / 3600)
			local minutes = math.floor((seconds % 3600) / 60)
			local secs = seconds % 60
			if hours > 0 then
				timerLabel.Text = string.format("%dH:%02dM:%02dS", hours, minutes, secs)
			elseif minutes > 0 then
				timerLabel.Text = string.format("%dM:%02dS", minutes, secs)
			else
				timerLabel.Text = string.format("%dS", secs)
			end
		end
	end
end

local function hideFrame()
	if frame then
		frame.Visible = false
	end
	PlayerUI.ShowMenuButtons()
	PlayerUI.HideAllMenus()
end

local function showFrame()
	if ensureUi() and frame then
		frame.Visible = true
	end
end

local function onRebirthPressed()
	if not ensureUi() then
		return
	end
	if busy then
		return
	end
	busy = true
	if rebirthButton then
		rebirthButton.Active = false
		rebirthButton.AutoButtonColor = false
	end
	local ok, result = pcall(function()
		return rebirthFn:InvokeServer({ action = "execute" })
	end)
	if rebirthButton then
		rebirthButton.Active = true
		rebirthButton.AutoButtonColor = true
	end
	busy = false
	if not ok or not result or result.success ~= true then
		if result and result.reason == "insufficient_funds" then
			Notifier.Insufficient()
		else
			Notifier.Warn("Rebirth failed")
		end
		updateProgress()
		return
	end

	Notifier.Show("Rebirth!", 2)
	Inventory.Reset()
	Inventory.EnsureStarter()
	PlayerUI.SetTierAmount(1, Inventory.GetCount("generator", 1))
	hideFrame()
	updateProgress()
end

local function connectButtons()
	if not ensureUi() then
		return
	end
	if rebirthButton and not rebirthButton:GetAttribute("rebirth_connected") then
		rebirthButton:SetAttribute("rebirth_connected", true)
		rebirthButton.MouseButton1Click:Connect(onRebirthPressed)
		rebirthButton.Activated:Connect(onRebirthPressed)
	end
	if closeButton and not closeButton:GetAttribute("rebirth_close_connected") then
		closeButton:SetAttribute("rebirth_close_connected", true)
		local function closeHandler()
			hideFrame()
		end
		closeButton.MouseButton1Click:Connect(closeHandler)
		closeButton.Activated:Connect(closeHandler)
	end
end

local function bootstrap()
	if not ensureUi() then
		return
	end
	connectButtons()
	updateProgress()
end

task.spawn(function()
	while true do
		updateProgress()
		task.wait(0.5)
	end
end)

player:GetAttributeChangedSignal("Cash"):Connect(updateProgress)
player:GetAttributeChangedSignal("CashPerSecond"):Connect(updateProgress)
player:GetAttributeChangedSignal("Rebirths"):Connect(updateProgress)
player:GetAttributeChangedSignal("RebirthIncomeMult"):Connect(updateProgress)
player:GetAttributeChangedSignal("RebirthProdMult"):Connect(updateProgress)
player:GetAttributeChangedSignal("RebirthTileDiscount"):Connect(updateProgress)

	playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" or child.Name == "rebirth_frame" then
		task.defer(bootstrap)
	end
end)

bootstrap()
