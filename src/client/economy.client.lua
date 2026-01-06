local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PlayerUI = require(script.Parent.playerui_controller)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

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
		value = math.floor(value * 10 + 0.5) / 10 -- one decimal place rounded
		return tostring(value) .. suffix
	end

	return tostring(math.floor(n))
end

local function updateCash()
	local cash = player:GetAttribute("Cash") or 0
	PlayerUI.SetCash(cash)
end

local function updateCashPerSecond()
	local cps = player:GetAttribute("CashPerSecond") or 0
	PlayerUI.SetCashPerSecond(cps)
end

local function updateMachineLabel(model)
	if not model or not model:IsA("Model") then
		return
	end
	local machineType = model:GetAttribute("machineType")
	local tier = model:GetAttribute("tier")
	local multiplier = model:GetAttribute("cashMultiplier")
	if typeof(multiplier) ~= "number" or multiplier < 1 then
		multiplier = 1
	end
	if not machineType or not tier then
		return
	end
	local rate = EconomyConfig.GetRate(machineType, tier) * multiplier
	local billboard = model:FindFirstChildWhichIsA("BillboardGui", true)
	if not billboard then
		return
	end
	local desc = billboard:FindFirstChild("description") or billboard:FindFirstChildWhichIsA("Frame", true)
	if not desc then
		return
	end
	local label = desc:FindFirstChild("cash_persecond") or desc:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = "+$" .. formatNumber(rate) .. "/s"
	end
	local multiplierLabel = desc:FindFirstChild("cash_multiplier")
	if multiplierLabel and multiplierLabel:IsA("TextLabel") then
		multiplierLabel.Text = "Multiplier: x" .. tostring(multiplier)
	end
end

local function watchMachine(model)
	updateMachineLabel(model)
	model:GetAttributeChangedSignal("tier"):Connect(function()
		updateMachineLabel(model)
	end)
	model:GetAttributeChangedSignal("machineType"):Connect(function()
		updateMachineLabel(model)
	end)
	model:GetAttributeChangedSignal("cashMultiplier"):Connect(function()
		updateMachineLabel(model)
	end)
end

local function processExistingMachines(folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			watchMachine(child)
		end
	end
end

local function initMachinesWatcher()
	local machines = Workspace:WaitForChild("machines")
	processExistingMachines(machines)
	machines.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			watchMachine(child)
		end
	end)
end

player:GetAttributeChangedSignal("Cash"):Connect(updateCash)
player:GetAttributeChangedSignal("CashPerSecond"):Connect(updateCashPerSecond)
updateCash()
updateCashPerSecond()
initMachinesWatcher()
