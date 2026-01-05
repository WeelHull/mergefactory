local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local Selection = {}

local items = {}
local index = 1
local changedListeners = {}

function Selection.Init()
	table.clear(items)
	for tier = 1, 10 do
		table.insert(items, {
			kind = "machine",
			machineType = "generator",
			tier = tier,
		})
	end
	index = 1
end

function Selection.GetCurrent()
	return items[index]
end

function Selection.GetIndex()
	return index
end

function Selection.GetCount()
	return #items
end

local function fireChanged()
	local current = Selection.GetCurrent()
	debugutil.log("placement", "state", "selection changed", {
		index = index,
		tier = current and current.tier,
	})
	for _, fn in pairs(changedListeners) do
		if typeof(fn) == "function" then
			fn()
		end
	end
	if typeof(Selection.onChanged) == "function" then
		Selection.onChanged()
	end
end

function Selection.Next()
	if #items == 0 then
		return Selection.GetCurrent()
	end
	index += 1
	if index > #items then
		index = 1
	end
	fireChanged()
	return Selection.GetCurrent()
end

function Selection.Prev()
	if #items == 0 then
		return Selection.GetCurrent()
	end
	index -= 1
	if index < 1 then
		index = #items
	end
	fireChanged()
	return Selection.GetCurrent()
end

function Selection.SetTier(tier)
	if #items == 0 then
		return Selection.GetCurrent()
	end
	local clamped = math.clamp(tier, 1, #items)
	if clamped == index then
		return Selection.GetCurrent()
	end
	index = clamped
	fireChanged()
	return Selection.GetCurrent()
end

function Selection.ConnectChanged(fn)
	local id = tostring(tick()) .. "_" .. tostring(math.random())
	changedListeners[id] = fn
	return {
		Disconnect = function()
			changedListeners[id] = nil
		end,
	}
end

return Selection
