local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PLACEMENT_DEBUG = true
local WHEEL_ACTION = "PlacementMouseWheel"

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local debugutil = require(ReplicatedStorage.Shared.debugutil)
local Feedback = require(script.Parent.placement_feedback)
local Selection = require(script.Parent.placement_selection)

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
local lastHoverGridX
local lastHoverGridZ
local lastHoverIslandId
local placementPayload = nil
local stateModule = require(script.Parent.placementmode_state)
local MachineInteractionState = require(script.Parent.machineinteraction_state)
local wasPlacementActive = false
local needPermissionRefresh = true
local wheelBound = false
local savedMinZoom
local savedMaxZoom
local replaceGhostPreview = nil
local ensureGhost
local snapGhostToTile
local lastTileInvalidated = false
Selection.Init()

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

local function destroyGhost(reason, logExit)
	if ghost then
		debugutil.log("placement", "state", "ghost_destroy", {
			reason = reason,
			name = ghost.Name,
		})
	end
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	lastTile = nil
	lastPermission = nil
	if logExit ~= false then
		log("state", "exit", { reason = reason or "destroy" })
		-- instruction_clear stays coupled to exit log via placement_instruction_controller observer
	end
end

local function onWheelAction(actionName, inputState, inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.MouseWheel then
		return Enum.ContextActionResult.Pass
	end
	if inputObject.Position.Z > 0 then
		Selection.Next()
	elseif inputObject.Position.Z < 0 then
		Selection.Prev()
	end
	if placementPayload and placementPayload.kind == "machine" then
		local currentSel = Selection.GetCurrent()
		if currentSel then
			placementPayload.tier = currentSel.tier
			debugutil.log("placement", "state", "payload_sync", {
				tier = currentSel.tier,
			})
		end
	end
	if stateModule.IsActive() and placementPayload and placementPayload.kind == "machine" then
		local current = Selection.GetCurrent()
		if current then
			placementPayload.tier = current.tier
			debugutil.log("placement", "state", "wheel_debug", {
				sel_tier = current.tier,
				sel_index = Selection.GetIndex(),
				payload_tier = placementPayload.tier,
				payload_type = placementPayload.machineType,
				ghost = ghost ~= nil,
				state = state,
			})
			lastTileInvalidated = true -- invalidate hover cache so onRender rebuilds on next frame
		end
	end
	if stateModule.IsActive() then
		local current = Selection.GetCurrent()
		debugutil.log("placement", "state", "wheel_action", {
			delta = inputObject.Position.Z,
			index = Selection.GetIndex(),
			tier = current and current.tier,
			payload_tier = placementPayload and placementPayload.tier,
		})
	end
	return Enum.ContextActionResult.Sink
end

local function bindWheel()
	if wheelBound then
		return
	end
	ContextActionService:BindActionAtPriority(WHEEL_ACTION, onWheelAction, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseWheel)
	wheelBound = true
	debugutil.log("placement", "state", "wheel captured", {})
end

local function unbindWheel()
	if not wheelBound then
		return
	end
	ContextActionService:UnbindAction(WHEEL_ACTION)
	wheelBound = false
	debugutil.log("placement", "state", "wheel released", {})
end

local function exitPlacement(reason)
	debugutil.log("placement", "state", "exit_begin", {
		reason = reason,
	})
	if wheelBound then
		unbindWheel()
	end
	if player and savedMinZoom and savedMaxZoom then
		player.CameraMinZoomDistance = savedMinZoom
		player.CameraMaxZoomDistance = savedMaxZoom
		savedMinZoom = nil
		savedMaxZoom = nil
		debugutil.log("placement", "state", "camera zoom restored", {})
	end
	destroyGhost("exit")
	placementPayload = nil
	stateModule.SetActive(false, reason)
	setState("Idle", reason or "exit")
	debugutil.log("placement", "state", "exit_end", {
		reason = reason,
	})
end

Selection.onChanged = function()
	if not stateModule.IsActive() then
		return
	end
	if not placementPayload or placementPayload.kind ~= "machine" then
		return
	end
	local current = Selection.GetCurrent()
	if not current then
		return
	end
	placementPayload.tier = current.tier
	if stateModule.IsActive() and placementPayload.kind == "machine" then
		if not ghost then
			ensureGhost()
		end
		if lastTile and ghost then
			replaceGhostPreview(placementPayload.machineType, placementPayload.tier)
			snapGhostToTile(lastTile)
			debugutil.log("placement", "state", "ghost_rebuilt", {
				reason = "selection_changed",
				tier = current.tier,
			})
		else
			debugutil.log("placement", "state", "ghost_rebuilt", {
				reason = lastTile and "ensure_failed" or "no_tile",
				tier = current.tier,
			})
		end
	end
end

function ensureGhost()
	if ghost then
		return ghost
	end
	if placementPayload and (placementPayload.kind == "machine" or placementPayload.kind == "relocate") then
		local previewName = placementPayload.machineType .. "_t" .. tostring(placementPayload.tier)
		local preview = previewsFolder:FindFirstChild(previewName)
		if preview and preview:IsA("Model") then
				ghost = preview:Clone()
				debugutil.log("placement", "state", "ghost_build", {
					previewName = previewName,
					found = true,
					source = "preview",
				})
		end
	end
	if not ghost then
		ghost = ghostTemplate:Clone()
		debugutil.log("placement", "state", "ghost_build", {
			previewName = placementPayload and (placementPayload.machineType .. "_t" .. tostring(placementPayload.tier)) or "unknown",
			found = false,
			source = "template",
		})
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

local function replaceGhostPreview(machineType, tier)
	if not ghost then
		return nil
	end
	local pivot = ghost:GetPivot()
	for _, child in ipairs(ghost:GetChildren()) do
		child:Destroy()
	end
	local previewName = machineType .. "_t" .. tostring(tier)
	local preview = previewsFolder:FindFirstChild(previewName)
	local source = "template"
	local modelToUse = ghostTemplate
	if preview and preview:IsA("Model") then
		modelToUse = preview
		source = "preview"
	end
	local clone = modelToUse:Clone()
	local newPrimary = clone.PrimaryPart
	for _, child in ipairs(clone:GetChildren()) do
		child.Parent = ghost
	end
	if newPrimary and not newPrimary:IsDescendantOf(ghost) then
		local candidate = ghost:FindFirstChild(newPrimary.Name, true)
		if candidate then
			newPrimary = candidate
		end
	end
	if newPrimary and newPrimary:IsDescendantOf(ghost) then
		ghost.PrimaryPart = newPrimary
	else
		ghost.PrimaryPart = ghost:FindFirstChildWhichIsA("BasePart")
	end
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Anchored = true
		end
	end
	ghost:PivotTo(pivot)
	debugutil.log("placement", "state", "ghost_preview_swapped", {
		tier = tier,
		previewName = previewName,
		source = source,
	})
	clone:Destroy()
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

function snapGhostToTile(tile)
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

	local placementActive = stateModule.IsActive()
	local exiting = (not placementActive) and wasPlacementActive
	local entering = placementActive and (not wasPlacementActive)
	wasPlacementActive = placementActive

	if exiting then
		destroyGhost("placement_inactive")
		setState("Idle", "placement_inactive")
		return
	end

	if not placementActive then
		return
	end

	local tile = raycastToTile()

	if not tile then
		destroyGhost("no_tile", false)
		lastTile = nil
		lastPermission = nil
		lastReason = nil
		currentEvaluatedTile = nil
		lastHoverGridX = nil
		lastHoverGridZ = nil
		lastHoverIslandId = nil
		needPermissionRefresh = true
		lastTileInvalidated = false
		setState("Placing", "no_tile")
		return
	end

	local gridx = tile:GetAttribute("gridx")
	local gridz = tile:GetAttribute("gridz")
	local islandid = player:GetAttribute("islandid")

	if gridx == lastHoverGridX and gridz == lastHoverGridZ and islandid == lastHoverIslandId and not lastTileInvalidated then
		return
	end
	lastTileInvalidated = false
	local tileChanged = true

	if tileChanged then
		log("state", "tile_hover_change", { tile = tile:GetFullName() })
		lastTile = tile
		lastHoverGridX = gridx
		lastHoverGridZ = gridz
		lastHoverIslandId = islandid
		currentEvaluatedTile = nil
		lastPermission = nil
		lastReason = nil
		needPermissionRefresh = true
		debugutil.log("placement", "state", "hover_debug", {
			tile = tile:GetFullName(),
			tileChanged = true,
			calledEnsure = false,
		})
	end

	local previousCanPlace = lastPermission
	local allowed
	local permissionChanged = false
	if needPermissionRefresh or tileChanged then
		allowed = updatePermission(tile)
		permissionChanged = allowed ~= previousCanPlace
		needPermissionRefresh = false
	else
		allowed = lastPermission
	end

	if not allowed then
		if permissionChanged or ghost then
			destroyGhost("hover_invalid", false)
		end
		return
	end

	if tileChanged or permissionChanged or not ghost then
		ensureGhost(tileChanged and "tile_change" or (permissionChanged and "permission_changed" or "first_valid_hover"))
		snapGhostToTile(tile)
		setGhostVisible(true, allowed)
		debugutil.log("placement", "state", "hover_debug", {
			tile = tile:GetFullName(),
			tileChanged = tileChanged,
			calledEnsure = true,
		})
	end
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
				exitPlacement("cancel")
			end
		end
		return
	end
	log("decision", "confirm")
	if placementPayload and placementPayload.kind == "machine" and lastTile then
		local gx = lastTile:GetAttribute("gridx")
		local gz = lastTile:GetAttribute("gridz")
		local current = Selection.GetCurrent()
		if current then
			placementPayload.tier = current.tier
		end
		debugutil.log("placement", "decision", "confirm_sync", {
			payload_tier = placementPayload.tier,
			payload_type = placementPayload.machineType,
			payload_kind = placementPayload.kind,
			sel_tier = current and current.tier,
		})
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
			ignoreMachineId = placementPayload.ignoreMachineId,
		})
		MachineInteractionState.SetRelocating(false)
	end
	_G._placementInputConsumed.consumed = true
	_G._placementInputConsumed.button = input and input.UserInputType or Enum.UserInputType.MouseButton1
	exitPlacement("confirm")
end

cancel = function(input)
	if state == "Idle" then
		return
	end
	log("state", "exit", { reason = "cancel" })
	_G._placementInputConsumed.consumed = true
	_G._placementInputConsumed.button = input and input.UserInputType or Enum.UserInputType.MouseButton1
	if placementPayload then
		if placementPayload.kind == "machine" then
			debugutil.log("placement", "state", "cancel_machine", {})
		elseif placementPayload.kind == "relocate" then
			debugutil.log("placement", "state", "cancel_relocate", {
				machineId = placementPayload.machineId,
			})
			MachineInteractionState.SetRelocating(false)
		end
	end
	exitPlacement("cancel")
end

local function enterPlacement(payload)
	if state ~= "Idle" then
		cancel()
	end
	placementPayload = payload or { kind = "tile" }
	lastTile = nil
	lastPermission = nil
	lastReason = nil
	currentEvaluatedTile = nil
	lastHoverGridX = nil
	lastHoverGridZ = nil
	lastHoverIslandId = nil
	stateModule.SetActive(true, "enter")
	setState("Placing", "enter")
	if player then
		savedMinZoom = player.CameraMinZoomDistance
		savedMaxZoom = player.CameraMaxZoomDistance
		local cam = workspace.CurrentCamera or camera
		if cam then
			local currentDistance = (cam.CFrame.Position - cam.Focus.Position).Magnitude
			player.CameraMinZoomDistance = currentDistance
			player.CameraMaxZoomDistance = currentDistance
			debugutil.log("placement", "state", "camera zoom locked", {
				distance = currentDistance,
			})
		end
	end
	local hovered = raycastToTile()
	if hovered then
		debugutil.log("placement", "state", "enter_forced_ghost", {
			tile = hovered:GetFullName(),
		})
		lastTile = hovered
		lastHoverGridX = hovered:GetAttribute("gridx")
		lastHoverGridZ = hovered:GetAttribute("gridz")
		lastHoverIslandId = player:GetAttribute("islandid")
		currentEvaluatedTile = nil
		lastPermission = nil
		lastReason = nil
		needPermissionRefresh = true
	end
	bindWheel()
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
		local cur = Selection.GetCurrent()
		if cur then
			enterPlacement({
				kind = "machine",
				machineType = cur.machineType,
				tier = cur.tier,
			})
		end
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
