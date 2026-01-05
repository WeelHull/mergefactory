local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PlayerUI = require(script.Parent.playerui_controller)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

local function formatNumber(n)
	n = tonumber(n) or 0
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
	if not machineType or not tier then
		return
	end
	local rate = EconomyConfig.GetRate(machineType, tier)
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
end

local function watchMachine(model)
	updateMachineLabel(model)
	model:GetAttributeChangedSignal("tier"):Connect(function()
		updateMachineLabel(model)
	end)
	model:GetAttributeChangedSignal("machineType"):Connect(function()
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
