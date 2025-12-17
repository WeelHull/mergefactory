local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLACEMENT_DEBUG = true

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local debugutil = require(ReplicatedStorage.Shared.debugutil)
local Feedback = require(script.Parent.placement_feedback)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local canPlaceFn = remotes:WaitForChild("canplaceontile")
local placeMachineEvent = remotes:WaitForChild("place_machine")

local ghostTemplate = ReplicatedStorage:WaitForChild("ghostplacement")
local previewsFolder = ReplicatedStorage:WaitForChild("previews")

-- shared click barrier
_G._placementInputConsumed = _G._placementInputConsumed or { consumed = false, button = nil }

local state = "Idle"
local ghost
local lastTile
local lastPermission
local lastReason
local currentEvaluatedTile
local placementPayload = nil
local stateModule = require(script.Parent.placementmode_state)
local MachineInteractionState = require(script.Parent.machineinteraction_state)

local function log(level, message, data)
	if not PLACEMENT_DEBUG then
		return
	end
	debugutil.log("placement", level, message, data)
end

local function setState(newState, reason)
	if state == newState then
		return
	end
	state = newState
	log("state", "state change", { state = state, reason = reason })
end

local function destroyGhost(reason)
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	lastTile = nil
	lastPermission = nil
	placementPayload = nil
	log("state", "exit", { reason = reason or "destroy" })
	setState("Idle")
end

local function ensureGhost()
	if ghost then
		return ghost
	end
	if placementPayload and placementPayload.kind == "machine" then
		local previewName = placementPayload.machineType .. "_t" .. tostring(placementPayload.tier)
		local preview = previewsFolder:FindFirstChild(previewName)
		if preview and preview:IsA("Model") then
			ghost = preview:Clone()
		end
	elseif placementPayload and placementPayload.kind == "relocate" then
		local previewName = placementPayload.machineType .. "_t" .. tostring(placementPayload.tier)
		local preview = previewsFolder:FindFirstChild(previewName)
		if preview and preview:IsA("Model") then
			ghost = preview:Clone()
		end
	end
	if not ghost then
		ghost = ghostTemplate:Clone()
		end
	ghost.Parent = workspace
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Anchored = true
		end
	end
	return ghost
end

local function setGhostVisible(visible, allowed)
	if not ghost then
		return
	end
	if placementPayload and placementPayload.kind == "machine" then
		return
	end
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and (allowed and 0.4 or 0.6) or 1
			part.Color = allowed and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(220, 80, 80)
		end
	end
end

local function snapGhostToTile(tile)
	if not ghost or not tile then
		return
	end
	local gp = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart")
	local tp = tile:IsA("Model") and tile.PrimaryPart or tile
	if not gp or not tp then
		return
	end
	local y = tp.Position.Y + tp.Size.Y * 0.5 + gp.Size.Y * 0.5
	local target = CFrame.new(tp.Position.X, y, tp.Position.Z)
	local delta = target.Position - gp.Position
	ghost:PivotTo(ghost:GetPivot() + delta)
end

local function raycastToTile()
	if not camera then
		camera = workspace.CurrentCamera
		if not camera then
			return nil
		end
	end
	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ghost }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
	if not result then
		return nil
	end
	local hit = result.Instance
	if not hit or not hit:IsA("BasePart") then
		return nil
	end
	if not hit.Name:match("^tile_z%d+_x%d+$") then
		return nil
	end
	local islandId = player:GetAttribute("islandid")
	if not islandId then
		return nil
	end
	local gridFolder = workspace:FindFirstChild("islands")
	gridFolder = gridFolder and gridFolder:FindFirstChild("player_" .. tostring(islandId))
	gridFolder = gridFolder and gridFolder:FindFirstChild("grid")
	if hit.Parent ~= gridFolder then
		return nil
	end
	return hit
end

local function updatePermission(tile)
	if tile == currentEvaluatedTile then
		return lastPermission
	end

	currentEvaluatedTile = tile
	lastPermission = nil
	lastReason = nil

	local ignoreMachineId = placementPayload and placementPayload.kind == "relocate" and placementPayload.machineId or nil
	local allowed, reason = canPlaceFn:InvokeServer(tile, ignoreMachineId)

	if allowed == lastPermission and reason == lastReason then
		return lastPermission
	end

	lastPermission = allowed
	lastReason = reason
	log("decision", "canPlace", {
		tile = tile:GetFullName(),
		allowed = allowed,
		reason = reason,
	})
	if allowed then
		setState("Valid", "permission_changed")
	else
		setState("Invalid", reason or "denied")
	end
	return allowed
end

local function onRender()
	if state == "Idle" or state == "Cancelled" then
		return
	end

	local tile = raycastToTile()
	if not tile then
		setGhostVisible(false)
		lastTile = nil
		lastPermission = nil
		lastReason = nil
		currentEvaluatedTile = nil
		setState("Placing", "no_tile")
		return
	end

	if tile ~= lastTile then
		log("state", "tile_hover_change", { tile = tile:GetFullName() })
		lastTile = tile
		currentEvaluatedTile = nil
		lastPermission = nil
		lastReason = nil
	end

	snapGhostToTile(tile)
	local allowed = updatePermission(tile)
	setGhostVisible(true, allowed)
end

local cancel

local function confirm(input)
	if state ~= "Valid" then
		-- invalid click while in placement: provide user feedback without changing flow
		if stateModule.IsActive() then
			if Feedback and Feedback.ShowInvalidPlacement then
				Feedback.ShowInvalidPlacement(lastReason)
			end
			-- if lastReason indicates a locked tile, stay in placement
			if lastReason == "tile_locked" then
				log("decision", "locked tile pressed — staying in placement", {
					gridx = lastTile and lastTile:GetAttribute("gridx"),
					gridz = lastTile and lastTile:GetAttribute("gridz"),
				})
				return
			end
			if type(cancel) == "function" then
				cancel(input)
			else
				stateModule.SetActive(false, "cancel")
				destroyGhost("cancel")
			end
		end
		return
	end
	log("decision", "confirm")
	if placementPayload and placementPayload.kind == "machine" and lastTile then
		local gx = lastTile:GetAttribute("gridx")
		local gz = lastTile:GetAttribute("gridz")
		debugutil.log("placement", "state", "confirm_machine", {
			gridx = gx,
			gridz = gz,
			machineType = placementPayload.machineType,
			tier = placementPayload.tier,
		})
		placeMachineEvent:FireServer({
			machineType = placementPayload.machineType,
			tier = placementPayload.tier,
			gridx = gx,
			gridz = gz,
			rotation = 0,
		})
	elseif placementPayload and placementPayload.kind == "relocate" and lastTile then
		local gx = lastTile:GetAttribute("gridx")
		local gz = lastTile:GetAttribute("gridz")
		debugutil.log("placement", "state", "confirm_relocate", {
			gridx = gx,
			gridz = gz,
			machineId = placementPayload.machineId,
		})
		placeMachineEvent:FireServer({
			kind = "relocate",
			machineId = placementPayload.machineId,
			machineType = placementPayload.machineType,
			tier = placementPayload.tier,
			gridx = gx,
			gridz = gz,
			rotation = placementPayload.rotation or 0,
		})
		MachineInteractionState.SetRelocating(false)
	end
	_G._placementInputConsumed.consumed = true
	_G._placementInputConsumed.button = input and input.UserInputType or Enum.UserInputType.MouseButton1
	stateModule.SetActive(false, "confirm")
	destroyGhost("confirm")
end

cancel = function(input)
	if state == "Idle" then
		return
	end
	log("state", "exit", { reason = "cancel" })
	_G._placementInputConsumed.consumed = true
	_G._placementInputConsumed.button = input and input.UserInputType or Enum.UserInputType.MouseButton1
	stateModule.SetActive(false, "cancel")
	if placementPayload then
		if placementPayload.kind == "machine" then
			debugutil.log("placement", "state", "cancel_machine", {})
		elseif placementPayload.kind == "relocate" then
			debugutil.log("placement", "state", "cancel_relocate", {
				machineId = placementPayload.machineId,
			})
			MachineInteractionState.SetRelocating(false)
			if placementPayload.machineId then
				local machinesFolder = workspace:FindFirstChild("machines")
				if machinesFolder then
					for _, m in ipairs(machinesFolder:GetChildren()) do
						if m:GetAttribute("machineId") == placementPayload.machineId or m:GetAttribute("machineid") == placementPayload.machineId then
							local adornee = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
							if adornee then
								local playerGui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
								local editOptions = playerGui and playerGui:FindFirstChild("editoptions")
								if editOptions then
									editOptions.Adornee = adornee
									editOptions.Enabled = true
									debugutil.log("machine", "state", "editoptions_open", {
										adornee = adornee:GetFullName(),
										machine = m:GetFullName(),
									})
								end
							end
							break
						end
					end
				end
			end
		end
	end
	destroyGhost("cancel")
end

local function enterPlacement(payload)
	if state ~= "Idle" then
		cancel()
	end
	placementPayload = payload or { kind = "tile" }
	ensureGhost()
	stateModule.SetActive(true, "enter")
	setState("Placing", "enter")
	if placementPayload.kind == "machine" then
		debugutil.log("placement", "state", "enter_machine", {
			machineType = placementPayload.machineType,
			tier = placementPayload.tier,
		})
	elseif placementPayload.kind == "relocate" then
		debugutil.log("placement", "state", "enter_relocate", {
			machineId = placementPayload.machineId,
			machineType = placementPayload.machineType,
			tier = placementPayload.tier,
		})
		MachineInteractionState.SetRelocating(true)
	else
		log("state", "enter", { state = "Placing" })
	end
end
stateModule.SetEnterCallback(enterPlacement)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		enterPlacement({
			kind = "machine",
			machineType = "generator",
			tier = 1,
		})
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		confirm(input)
	end
	if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
		cancel(input)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if _G._placementInputConsumed and _G._placementInputConsumed.consumed and _G._placementInputConsumed.button == input.UserInputType then
		_G._placementInputConsumed.consumed = false
		_G._placementInputConsumed.button = nil
		debugutil.log("interaction", "state", "input consumption reset", {})
	end
end)

RunService.RenderStepped:Connect(onRender)
