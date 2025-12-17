-- machine_intent server handler: routes machine intents to authoritative services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local IslandValidator = require(ServerScriptService.Server.islandvalidator)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)

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
			machineId = payload.machineId,
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
			machineId = payload.machineId,
			reason = reason,
			step = "reject",
		})
	end
end

local function handleSelect(player, payload)
	debug.log("machine", "state", "selected", {
		userid = player and player.UserId,
		gridx = payload.gridx,
		gridz = payload.gridz,
	})
end

local function resolveMachineForPlayer(machineId, islandid, player)
	if typeof(machineId) ~= "string" or machineId == "" then
		return nil, "invalid_machineId"
	end

	local model = MachineRegistry.get(machineId)
	if not model then
		return nil, "machine_not_found"
	end

	local ownerUserId = model:GetAttribute("ownerUserId")
	if typeof(ownerUserId) ~= "number" or ownerUserId ~= (player and player.UserId) then
		return nil, "not_owner"
	end

	local gridx = model:GetAttribute("gridx")
	local gridz = model:GetAttribute("gridz")
	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" then
		return nil, "machine_missing_attrs"
	end

	local occupied, occupantId = MachineRegistry.isTileOccupied(islandid, gridx, gridz)
	if not occupied or occupantId ~= machineId then
		return nil, "machine_not_bound"
	end

	local rotation = model:GetAttribute("rotation")
	if typeof(rotation) ~= "number" then
		rotation = 0
	end

	return {
		model = model,
		gridx = gridx,
		gridz = gridz,
		rotation = rotation,
		ownerUserId = ownerUserId,
	}
end

local function handleDeleteIntent(player, payload, islandid)
	local ctx, reason = resolveMachineForPlayer(payload.machineId, islandid, player)
	if not ctx then
		reject(player, payload, reason)
		return
	end

	MachineRegistry.UnbindTile(payload.machineId)
	MachineRegistry.unregister(payload.machineId)
	ctx.model:Destroy()

	debug.log("machine", "state", "deleted", {
		machineId = payload.machineId,
		gridx = ctx.gridx,
		gridz = ctx.gridz,
	})
end

local function handleRotateIntent(player, payload, islandid)
	local ctx, reason = resolveMachineForPlayer(payload.machineId, islandid, player)
	if not ctx then
		reject(player, payload, reason)
		return
	end

	local delta = payload.delta
	if typeof(delta) ~= "number" then
		reject(player, payload, "invalid_delta")
		return
	end
	if delta % 90 ~= 0 then
		reject(player, payload, "invalid_delta")
		return
	end

	local newRotation = ((ctx.rotation + delta) % 360 + 360) % 360
	if not VALID_ROTATION[newRotation] then
		reject(player, payload, "invalid_rotation")
		return
	end

	local pivot = ctx.model:GetPivot()
	if ctx.model.PrimaryPart then
		ctx.model.PrimaryPart.Anchored = true
	end
	ctx.model:PivotTo(pivot * CFrame.Angles(0, math.rad(delta), 0))
	ctx.model:SetAttribute("rotation", newRotation)

	debug.log("machine", "state", "rotated", {
		machineId = payload.machineId,
		rot = newRotation,
	})
end

local function handleMoveIntent(player, payload, islandid)
	local ctx, reason = resolveMachineForPlayer(payload.machineId, islandid, player)
	if not ctx then
		reject(player, payload, reason)
		return
	end

	ctx.model:SetAttribute("state", "Relocating")
	debug.log("machine", "state", "relocating", {
		machineId = payload.machineId,
		gridx = ctx.gridx,
		gridz = ctx.gridz,
	})
end

local function onMachineIntent(player, payload)
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
	if type(intent) ~= "string" then
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
	if not islandValid then
		reject(player, payload, "island_not_resolved")
		return
	end

	local intentLower = string.lower(intent)

	if intentLower == "select" then
		if type(payload.gridx) ~= "number" or type(payload.gridz) ~= "number" then
			reject(player, payload, "invalid_payload")
			return
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
		if not occupied then
			reject(player, payload, "machine_not_found")
			return
		end
		handleSelect(player, payload)
	elseif intentLower == "delete" then
		handleDeleteIntent(player, payload, islandid)
	elseif intentLower == "rotate" then
		handleRotateIntent(player, payload, islandid)
	elseif intentLower == "move" then
		handleMoveIntent(player, payload, islandid)
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
