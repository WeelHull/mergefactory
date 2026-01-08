local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Notifier = require(script.Parent.notifier)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local shopCoinsFn = remotes:WaitForChild("shop_coins_purchase")

local items = {
	coins_1 = 15,
	coins_2 = 30,
	coins_3 = 60,
	coins_4 = 180,
}

local frames = {}
local connected = false

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

local function resolve()
	local playerUI = playerGui:FindFirstChild("PlayerUI") or playerGui:WaitForChild("PlayerUI", 5)
	if not playerUI then
		return false
	end
	local shopFrame = playerUI:FindFirstChild("shop_frame")
	local scrolling = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
	local coinsBg = scrolling and scrolling:FindFirstChild("coins_background")
	if not coinsBg then
		return false
	end
	for name, minutes in pairs(items) do
		local f = coinsBg:FindFirstChild(name)
		if f then
			local buy = f:FindFirstChild("buy")
			if buy and not buy:IsA("GuiButton") then
				buy = buy:FindFirstChildWhichIsA("GuiButton", true) or buy
			end
			local amt = f:FindFirstChild("amount")
			frames[name] = {
				frame = f,
				minutes = minutes,
				buy = buy,
				amount = amt,
			}
		end
	end
	return next(frames) ~= nil
end

local function update()
	if not resolve() then
		return
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	for _, data in pairs(frames) do
		if data.amount and data.amount:IsA("TextLabel") then
			local amount = math.max(0, math.floor(cps * data.minutes * 60))
			data.amount.Text = formatCompact(amount) .. " C$"
		end
	end
end

local function onBuy(data)
	local ok, result = pcall(function()
		return shopCoinsFn:InvokeServer({ minutes = data.minutes })
	end)
	if not ok or not result or result.success ~= true then
		Notifier.Warn("Purchase failed")
		return
	end
	if result.amount then
		Notifier.Show("Added " .. formatCompact(result.amount) .. " C$", 2)
	else
		Notifier.Show("Coins added!", 2)
	end
end

local function connect()
	if connected then
		return
	end
	if not resolve() then
		return
	end
	for _, data in pairs(frames) do
		if data.buy and not data.buy:GetAttribute("shop_coins_connected") then
			data.buy:SetAttribute("shop_coins_connected", true)
			local handler = function()
				onBuy(data)
			end
			if data.buy.Activated then
				data.buy.Activated:Connect(handler)
			else
				data.buy.MouseButton1Click:Connect(handler)
			end
		end
	end
	player:GetAttributeChangedSignal("CashPerSecond"):Connect(update)
	connected = true
	update()
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(connect)
	end
end)

connect()
