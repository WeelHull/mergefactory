local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local Selection = {}

local items = {}
local index = 1

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

local function logSelection()
	local current = Selection.GetCurrent()
	debugutil.log("placement", "state", "selection changed", {
		index = index,
		tier = current and current.tier,
	})
end

function Selection.Next()
	if #items == 0 then
		return Selection.GetCurrent()
	end
	index += 1
	if index > #items then
		index = 1
	end
	logSelection()
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
	logSelection()
	return Selection.GetCurrent()
end

return Selection
