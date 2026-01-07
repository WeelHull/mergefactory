-- inventory: server-authoritative, session-scoped machine inventory.

local Players = game:GetService("Players")

local inventory = {}
local counts = {} -- counts[userId][machineType][tier] = number

local function ensureBucket(userId, machineType)
	counts[userId] = counts[userId] or {}
	counts[userId][machineType] = counts[userId][machineType] or {}
	return counts[userId][machineType]
end

function inventory.GetCount(userId, machineType, tier)
	local byUser = counts[userId]
	if not byUser then
		return 0
	end
	local byType = byUser[machineType]
	if not byType then
		return 0
	end
	return byType[tier] or 0
end

function inventory.Grant(userId, machineType, tier, amount)
	if typeof(userId) ~= "number" or typeof(machineType) ~= "string" or typeof(tier) ~= "number" then
		return
	end
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return
	end

	local byType = ensureBucket(userId, machineType)
	byType[tier] = (byType[tier] or 0) + amount
end

function inventory.Consume(userId, machineType, tier, amount)
	amount = tonumber(amount) or 1
	if amount <= 0 then
		return false
	end

	if inventory.GetCount(userId, machineType, tier) < amount then
		return false
	end

	local byType = ensureBucket(userId, machineType)
	byType[tier] -= amount
	return true
end

function inventory.Reset(userId)
	if userId == nil then
		return
	end
	counts[userId] = nil
end

Players.PlayerRemoving:Connect(function(player)
	inventory.Reset(player.UserId)
end)

return inventory
