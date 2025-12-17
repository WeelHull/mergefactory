-- machine_intent server handler: routes machine intents to authoritative services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local IslandValidator = require(ServerScriptService.Server.islandvalidator)
local machinerelocation = require(ServerScriptService.Server.machinerelocation)

local TRACE = true
local BOUND = false

local function actorPath()
	local a = script:FindFirstAncestorOfClass("Actor")
	return a and a:GetFullName() or "none"
end

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local machineIntentEvent = remotes:WaitForChild("machine_intent")

local VALID_ROTATION = {
	[0] = true,
	[90] = true,
	[180] = true,
	[270] = true,
}

debug.log("machine", "init", "context", {
	script = script:GetFullName(),
	actor = actorPath(),
})

local function logIntent(payload, player)
	if TRACE then
		debug.log("machine", "decision", "intent received", {
			step = "entry",
			userid = player and player.UserId,
			intent = payload.intent,
			gridx = payload.gridx,
			gridz = payload.gridz,
			rotation = payload.rotation,
		})
	end
end

local function reject(player, payload, reason)
	if TRACE then
		debug.log("machine", "warn", "intent rejected", {
			userid = player and player.UserId,
			intent = payload.intent,
			gridx = payload.gridx,
			gridz = payload.gridz,
			rotation = payload.rotation,
			reason = reason,
			step = "reject",
		})
	end
end

local function handleRotate(player, payload, machineId, islandid)
	local rotation = payload.rotation
	if not VALID_ROTATION[rotation] then
		reject(player, payload, "invalid_rotation")
		return
	end

	-- Rotation without movement uses relocation to enforce occupancy and state.
	local ok, reason = machinerelocation.CanRelocate(machineId, payload.gridx, payload.gridz, islandid, rotation)
	if not ok then
		reject(player, payload, reason)
		return
	end

	local moved, why = machinerelocation.Relocate(machineId, payload.gridx, payload.gridz, islandid, rotation)
	if not moved then
		reject(player, payload, why)
	end
end

local function handleMove(player, payload)
	-- Move intent needs client to supply target coords in future; currently reject.
	reject(player, payload, "move_not_implemented")
end

local function handleSelect(player, payload)
	debug.log("machine", "state", "selected", {
		userid = player and player.UserId,
		gridx = payload.gridx,
		gridz = payload.gridz,
	})
end

local function onMachineIntent(player, payload)
	local MachineRegistry = require(ServerScriptService.Server.machineregistry)
	debug.log("machine", "init", "intent handler entered", {
		registry_table = tostring(MachineRegistry),
		islandid = nil,
		gridx = payload and payload.gridx,
		gridz = payload and payload.gridz,
	})
	if type(payload) ~= "table" then
		return
	end

	logIntent(payload, player)

	local intent = payload.intent

	if type(payload.gridx) ~= "number" or type(payload.gridz) ~= "number" or type(intent) ~= "string" then
		reject(player, payload, "invalid_payload")
		return
	end

	local islandid = player and player:GetAttribute("islandid")
	if TRACE then
		debug.log("machine", "state", "intent trace", {
			step = "island_attr",
			userid = player and player.UserId,
			islandid = islandid,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
	end

	local islandValid = IslandValidator.isValidIslandId(islandid)
	if TRACE then
		debug.log("machine", "state", "intent trace", {
			step = "island_validated",
			islandid = islandid,
			is_valid = islandValid,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
	end

	if not islandValid then
		reject(player, payload, "island_not_resolved")
		return
	end

	if islandid == nil then
		reject(player, payload, "island_not_resolved")
		return
	end

	if TRACE then
		debug.log("machine", "state", "intent trace", {
			step = "pre_occupied_A",
			islandid = islandid,
			gridx = payload.gridx,
			gridz = payload.gridz,
		})
	end

	debug.log("machine", "decision", "calling IsTileOccupied", {
		registry_table = tostring(MachineRegistry),
	})
	local occupied, machineId = MachineRegistry.isTileOccupied(islandid, payload.gridx, payload.gridz)
	debug.log("machine", "state", "IsTileOccupied result", {
		result = occupied,
		machineId = machineId,
		registry_table = tostring(MachineRegistry),
		dump = MachineRegistry.__debugDump(),
	})
	if TRACE then
		debug.log("machine", "state", "intent trace", {
			step = "post_occupied_A",
			islandid = islandid,
			gridx = payload.gridx,
			gridz = payload.gridz,
			occupied = occupied,
			machineid = machineId,
		})
	end
	if not occupied then
		reject(player, payload, "machine_not_found")
		return
	end

	local intentLower = string.lower(intent)

	if intentLower == "select" then
		handleSelect(player, payload)
	elseif intentLower == "rotate" then
		handleRotate(player, payload, machineId, islandid)
	elseif intentLower == "move" then
		handleMove(player, payload)
	else
		reject(player, payload, "unknown_intent")
	end
end

if BOUND then
	debug.log("machine", "error", "machine_intent already bound", {
		script = script,
	})
	return
end
BOUND = true

machineIntentEvent.OnServerEvent:Connect(onMachineIntent)
