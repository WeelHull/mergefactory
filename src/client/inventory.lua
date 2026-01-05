local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local Inventory = {}

local counts = {}
local changedEvent = Instance.new("BindableEvent")
local seeded = false

local function fire(machineType, tier)
	local count = Inventory.GetCount(machineType, tier)
	changedEvent:Fire(machineType, tier, count)
	debugutil.log("inventory", "state", "updated", {
		machineType = machineType,
		tier = tier,
		count = count,
	})
end

function Inventory.GetCount(machineType, tier)
	local byType = counts[machineType]
	if not byType then
		return 0
	end
	return byType[tier] or 0
end

function Inventory.Has(machineType, tier, amount)
	amount = amount or 1
	return Inventory.GetCount(machineType, tier) >= amount
end

function Inventory.Add(machineType, tier, amount)
	amount = amount or 1
	if amount <= 0 then
		return
	end
	counts[machineType] = counts[machineType] or {}
	local byType = counts[machineType]
	byType[tier] = (byType[tier] or 0) + amount
	fire(machineType, tier)
end

function Inventory.Consume(machineType, tier, amount)
	amount = amount or 1
	if not Inventory.Has(machineType, tier, amount) then
		return false
	end
	local byType = counts[machineType]
	byType[tier] -= amount
	fire(machineType, tier)
	return true
end

function Inventory.ConnectChanged(fn)
	return changedEvent.Event:Connect(fn)
end

function Inventory.EnsureStarter()
	if seeded then
		return
	end
	seeded = true
	if Inventory.GetCount("generator", 1) == 0 then
		Inventory.Add("generator", 1, 1)
	end
end

return Inventory
