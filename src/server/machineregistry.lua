-- machineregistry (ModuleScript): runtime controller for machine models.
-- Ensures workspace container exists and provides in-memory registry helpers.

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local IslandValidator = require(script.Parent.islandvalidator)
local debug = require(ServerScriptService.Server.debugutil)

local function actorPath()
	local a = script:FindFirstAncestorOfClass("Actor")
	return a and a:GetFullName() or "none"
end

local MachineRegistry = {}

local machinesFolder
local machinesById = {} -- machinesById[machineId] = Model
local machinesByOwner = {} -- machinesByOwner[userId][machineId] = true
local machineTileById = {} -- machineTileById[machineId] = { islandid = number, gridx = number, gridz = number }
local tileOccupancy = {} -- tileOccupancy[islandid][gridz][gridx] = machineId

MachineRegistry._occupancy = tileOccupancy

debug.log("machineregistry", "init", "module loaded", {
	script = script:GetFullName(),
	actor = actorPath(),
	registry_table = tostring(MachineRegistry),
})

local function readMachineId(model)
	local attr = model:GetAttribute("machineid")
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end

	attr = model:GetAttribute("machineId")
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end

	return nil
end

local function ensureMachinesFolder()
	if machinesFolder and machinesFolder.Parent == workspace then
		return machinesFolder
	end

	local existing = workspace:FindFirstChild("machines")
	if existing and existing:IsA("Folder") then
		machinesFolder = existing
		return machinesFolder
	end

	machinesFolder = Instance.new("Folder")
	machinesFolder.Name = "machines"
	machinesFolder.Parent = workspace
	return machinesFolder
end

local function generateMachineId()
	local id
	repeat
		id = HttpService:GenerateGUID(false)
	until machinesById[id] == nil
	return id
end

local function readOwnerUserId(model, ownerUserId)
	if ownerUserId ~= nil then
		return ownerUserId
	end

	local attr = model:GetAttribute("ownerUserId")
	if typeof(attr) == "number" then
		return attr
	end

	return nil
end

local function trackOwner(ownerUserId, machineId)
	if ownerUserId == nil then
		return
	end

	machinesByOwner[ownerUserId] = machinesByOwner[ownerUserId] or {}
	machinesByOwner[ownerUserId][machineId] = true
end

local function untrackOwner(machineId)
	for ownerUserId, ids in pairs(machinesByOwner) do
		if ids[machineId] then
			ids[machineId] = nil
			if next(ids) == nil then
				machinesByOwner[ownerUserId] = nil
			end
			return ownerUserId
		end
	end

	return nil
end

function MachineRegistry.register(model, ownerUserId)
	if not model or not model:IsA("Model") then
		return nil
	end

	ensureMachinesFolder()

	local machineId = readMachineId(model)
	if not machineId then
		machineId = generateMachineId()
	end

	machinesById[machineId] = model

	local owner = readOwnerUserId(model, ownerUserId)
	trackOwner(owner, machineId)
	return machineId
end

function MachineRegistry.unregister(machineId)
	if typeof(machineId) ~= "string" or machineId == "" then
		return nil
	end

	local model = machinesById[machineId]
	if not model then
		return nil
	end

	machinesById[machineId] = nil
	local owner = untrackOwner(machineId)

	local bound = machineTileById[machineId]
	if bound then
		MachineRegistry.unbindTile(machineId)
	end
	return model
end

function MachineRegistry.get(machineId)
	return machinesById[machineId]
end

function MachineRegistry.getIdsForOwner(ownerUserId)
	local bucket = machinesByOwner[ownerUserId]
	if not bucket then
		return {}
	end

	local ids = {}
	for id in pairs(bucket) do
		table.insert(ids, id)
	end

	table.sort(ids)
	return ids
end

function MachineRegistry.getMachinesForOwner(ownerUserId)
	local models = {}
	for _, id in ipairs(MachineRegistry.getIdsForOwner(ownerUserId)) do
		local model = machinesById[id]
		if model then
			table.insert(models, model)
		end
	end
	return models
end

function MachineRegistry.isTileOccupied(islandid, gridx, gridz)
	debug.log("machineregistry", "state", "IsTileOccupied", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		registry_table = tostring(MachineRegistry),
	})

	if not IslandValidator.isValidIslandId(islandid) then
		debug.log("machineregistry", "state", "IsTileOccupied result", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			result = false,
		})
		return false, nil
	end

	local islandKey = tostring(islandid)
	local gridzKey = tostring(gridz)
	local gridxKey = tostring(gridx)

	local island = tileOccupancy[islandKey]
	if not island then
		debug.log("machineregistry", "state", "IsTileOccupied result", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			result = false,
		})
		return false, nil
	end

	local row = island[gridzKey]
	if not row then
		debug.log("machineregistry", "state", "IsTileOccupied result", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			result = false,
		})
		return false, nil
	end

	local id = row[gridxKey]
	if typeof(id) ~= "string" or id == "" then
		debug.log("machineregistry", "state", "occupancy clear", {
			func = "isTileOccupied",
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			path = string.format("tileOccupancy[%s][%s][%s]", islandKey, gridzKey, gridxKey),
			table_id = tostring(row),
			previous = id,
		})
		row[gridxKey] = nil
		if next(row) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "isTileOccupied",
				islandid = islandid,
				gridx = gridx,
				gridz = gridz,
				path = string.format("tileOccupancy[%s][%s]", islandKey, gridzKey),
				table_id = tostring(island[gridzKey]),
				previous = "<row emptied>",
			})
			island[gridzKey] = nil
		end
		if next(island) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "isTileOccupied",
				islandid = islandid,
				gridx = gridx,
				gridz = gridz,
				path = string.format("tileOccupancy[%s]", islandKey),
				table_id = tostring(tileOccupancy[islandKey]),
				previous = "<island emptied>",
			})
			tileOccupancy[islandKey] = nil
		end
		debug.log("machineregistry", "state", "IsTileOccupied result", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			result = false,
		})
		return false, nil
	end

	local model = MachineRegistry.get(id)
	if not model then
		debug.log("machineregistry", "state", "occupancy clear", {
			func = "isTileOccupied",
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			path = string.format("tileOccupancy[%s][%s][%s]", islandKey, gridzKey, gridxKey),
			table_id = tostring(row),
			previous = id,
		})
		row[gridxKey] = nil
		if next(row) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "isTileOccupied",
				islandid = islandid,
				gridx = gridx,
				gridz = gridz,
				path = string.format("tileOccupancy[%s][%s]", islandKey, gridzKey),
				table_id = tostring(island[gridzKey]),
				previous = "<row emptied>",
			})
			island[gridzKey] = nil
		end
		if next(island) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "isTileOccupied",
				islandid = islandid,
				gridx = gridx,
				gridz = gridz,
				path = string.format("tileOccupancy[%s]", islandKey),
				table_id = tostring(tileOccupancy[islandKey]),
				previous = "<island emptied>",
			})
			tileOccupancy[islandKey] = nil
		end
		debug.log("machineregistry", "state", "IsTileOccupied result", {
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			result = false,
		})
		return false, nil
	end

	debug.log("machineregistry", "state", "IsTileOccupied result", {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		result = true,
		machineId = id,
	})
	return true, id
end

function MachineRegistry.bindTile(machineId, islandid, gridx, gridz)
	if typeof(machineId) ~= "string" or machineId == "" then
		return false
	end

	if machineTileById[machineId] then
		return false
	end

	local occupied = MachineRegistry.isTileOccupied(islandid, gridx, gridz)
	if occupied then
		return false
	end

	local islandKey = tostring(islandid)
	local gridzKey = tostring(gridz)
	local gridxKey = tostring(gridx)

	if not tileOccupancy[islandKey] then
		debug.log("machineregistry", "state", "occupancy lazy init", {
			func = "bindTile",
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			path = string.format("tileOccupancy[%s]", islandKey),
			table_id = tostring(tileOccupancy),
		})
		tileOccupancy[islandKey] = {}
	end

	if not tileOccupancy[islandKey][gridzKey] then
		debug.log("machineregistry", "state", "occupancy lazy init", {
			func = "bindTile",
			islandid = islandid,
			gridx = gridx,
			gridz = gridz,
			path = string.format("tileOccupancy[%s][%s]", islandKey, gridzKey),
			table_id = tostring(tileOccupancy[islandKey]),
		})
		tileOccupancy[islandKey][gridzKey] = {}
	end

	local previous = tileOccupancy[islandKey][gridzKey][gridxKey]
	tileOccupancy[islandKey][gridzKey][gridxKey] = machineId
	debug.log("machineregistry", "state", "occupancy set", {
		func = "bindTile",
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
		path = string.format("tileOccupancy[%s][%s][%s]", islandKey, gridzKey, gridxKey),
		table_id = tostring(tileOccupancy[islandKey][gridzKey]),
		machineId = machineId,
		previous = previous,
	})

	machineTileById[machineId] = {
		islandid = islandid,
		gridx = gridx,
		gridz = gridz,
	}
	return true
end

function MachineRegistry.unbindTile(machineId)
	local binding = machineTileById[machineId]
	if not binding then
		return false
	end

	local islandKey = tostring(binding.islandid)
	local gridzKey = tostring(binding.gridz)
	local gridxKey = tostring(binding.gridx)

	local island = tileOccupancy[islandKey]
	if island and island[gridzKey] then
		debug.log("machineregistry", "state", "occupancy clear", {
			func = "unbindTile",
			islandid = binding.islandid,
			gridx = binding.gridx,
			gridz = binding.gridz,
			path = string.format("tileOccupancy[%s][%s][%s]", islandKey, gridzKey, gridxKey),
			table_id = tostring(island[gridzKey]),
			previous = island[gridzKey][gridxKey],
		})
		island[gridzKey][gridxKey] = nil
		if next(island[gridzKey]) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "unbindTile",
				islandid = binding.islandid,
				gridx = binding.gridx,
				gridz = binding.gridz,
				path = string.format("tileOccupancy[%s][%s]", islandKey, gridzKey),
				table_id = tostring(island[gridzKey]),
				previous = "<row emptied>",
			})
			island[gridzKey] = nil
		end
		if next(island) == nil then
			debug.log("machineregistry", "state", "occupancy clear", {
				func = "unbindTile",
				islandid = binding.islandid,
				gridx = binding.gridx,
				gridz = binding.gridz,
				path = string.format("tileOccupancy[%s]", islandKey),
				table_id = tostring(tileOccupancy[islandKey]),
				previous = "<island emptied>",
			})
			tileOccupancy[islandKey] = nil
		end
	end

	machineTileById[machineId] = nil
	return true
end

-- Public wrappers (PascalCase) for external callers.
function MachineRegistry.RegisterMachine(model, ownerUserId)
	return MachineRegistry.register(model, ownerUserId)
end

function MachineRegistry.BindTile(machineId, islandid, gridx, gridz)
	return MachineRegistry.bindTile(machineId, islandid, gridx, gridz)
end

function MachineRegistry.IsTileOccupied(islandid, gridx, gridz)
	return MachineRegistry.isTileOccupied(islandid, gridx, gridz)
end

function MachineRegistry.UnbindTile(machineId)
	return MachineRegistry.unbindTile(machineId)
end

function MachineRegistry.__debugDump()
	return {
		registry_table = tostring(MachineRegistry),
		occupancy = MachineRegistry._occupancy,
	}
end

-- Expose folder helper for bootstrap.
MachineRegistry.ensureMachinesFolder = ensureMachinesFolder

return MachineRegistry
