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
local Inventory = require(script.Parent.inventory)
local PurchasePrompt = require(script.Parent.purchase_prompt)
local PlayerUI = require(script.Parent.playerui_controller)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local canPlaceFn = remotes:WaitForChild("canplaceontile")
local placeMachineEvent = remotes:WaitForChild("place_machine")

local ghostTemplate = ReplicatedStorage:WaitForChild("ghostplacement")
local previewsFolder = ReplicatedStorage:WaitForChild("previews")

-- shared click barrier
_G._placementInputConsumed = _G._placementInputConsumed or { consumed = false, button = nil }

local state = "Idle"
local placementPayload = nil
local ghost
local lastTile
local lastPermission
local lastReason
local currentEvaluatedTile
local lastHoverGridX
local lastHoverGridZ
local lastHoverIslandId
local gridFolder
local stateModule = require(script.Parent.placementmode_state)
local MachineInteractionState = require(script.Parent.machineinteraction_state)
local wasPlacementActive = false
local needPermissionRefresh = true
local hoverDirty = false
local wheelBound = false
local savedMinZoom
local savedMaxZoom
local currentRotation = 0
local relocationSourceModel
local relocationRemovedConn

local ensureGhost
local snapGhostToTile
local replaceGhostPreview
local cancel
local exitPlacement
local watchRelocationSource
local clearRelocationWatcher

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

local function clearHoverCache()
	lastTile = nil
	lastPermission = nil
	lastReason = nil
	currentEvaluatedTile = nil
	lastHoverGridX = nil
	lastHoverGridZ = nil
	lastHoverIslandId = nil
	needPermissionRefresh = true
	hoverDirty = true
end

clearRelocationWatcher = function()
	if relocationRemovedConn then
		relocationRemovedConn:Disconnect()
		relocationRemovedConn = nil
	end
	relocationSourceModel = nil
end

local function findRelocationSourceModel(machineId)
	if typeof(machineId) ~= "string" or machineId == "" then
		return nil
	end
	local machinesFolder = workspace:FindFirstChild("machines")
	if not machinesFolder then
		return nil
	end
	for _, child in ipairs(machinesFolder:GetChildren()) do
		if child:IsA("Model") then
			local id = child:GetAttribute("machineId") or child:GetAttribute("machineid")
			if id == machineId then
				return child
			end
		end
	end
	return nil
end

local function onRelocationSourceRemoved(machineId)
	-- Merges triggered via machine interaction can destroy the relocating machine without going through confirm().
	debugutil.log("merge", "state", "relocate_source_removed", {
		machineId = machineId or (placementPayload and placementPayload.machineId),
	})
	clearRelocationWatcher()
	if placementPayload and placementPayload.kind == "relocate" and stateModule.IsActive() then
		MachineInteractionState.SetRelocating(false, "merge_complete")
		exitPlacement("relocate_source_removed")
	end
end

watchRelocationSource = function(machineId)
	clearRelocationWatcher()
	local model = findRelocationSourceModel(machineId)
	if not model then
		return
	end
	relocationSourceModel = model
	relocationRemovedConn = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			onRelocationSourceRemoved(machineId)
		end
	end)
end

local function destroyGhost(reason, logExit)
	if ghost then
		debugutil.log("placement", "state", "ghost_destroy", {
			reason = reason,
			name = ghost.Name,
		})
		ghost:Destroy()
		ghost = nil
	end
	PlayerUI.SetRotationAdornee(nil)
	if logExit ~= false then
		log("state", "exit", { reason = reason or "destroy" })
	end
end

ensureGhost = function()
	if ghost then
		return ghost
	end
	local previewName
	if placementPayload and (placementPayload.kind == "machine" or placementPayload.kind == "relocate") then
		previewName = placementPayload.machineType .. "_t" .. tostring(placementPayload.tier)
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
			previewName = previewName or "unknown",
			found = false,
			source = "template",
		})
	end
	debugutil.log("placement", "state", "ghost_ensure_called", {
		payload_type = placementPayload and placementPayload.machineType,
		payload_tier = placementPayload and placementPayload.tier,
	})
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

replaceGhostPreview = function(machineType, tier)
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

snapGhostToTile = function(tile)
	if not ghost or not tile then
		return
	end
	local gp = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart")
	local tp = tile:IsA("Model") and tile.PrimaryPart or tile
	if not gp or not tp then
		return
	end
	PlayerUI.SetRotationAdornee(tp)
	local y = tp.Position.Y + tp.Size.Y * 0.5 + gp.Size.Y * 0.5
	local rotation = placementPayload and placementPayload.rotation or currentRotation or 0
	local targetPrimary = CFrame.new(tp.Position.X, y, tp.Position.Z) * CFrame.Angles(0, math.rad(rotation), 0)
	local pivotToPrimary = ghost:GetPivot():ToObjectSpace(gp.CFrame)
	local targetPivot = targetPrimary * pivotToPrimary:Inverse()
	ghost:PivotTo(targetPivot)
end

local function setGhostVisible(visible, allowed)
	if not ghost then
		return
	end
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and (allowed and 0.4 or 0.6) or 1
			part.Color = allowed and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(220, 80, 80)
		end
	end
end

local function raycastToTile()
	local islandId = player and player:GetAttribute("islandid")
	if not islandId then
		return nil
	end
	local islands = workspace:FindFirstChild("islands")
	local islandModel = islands and islands:FindFirstChild("player_" .. tostring(islandId))
	gridFolder = islandModel and islandModel:FindFirstChild("grid") or gridFolder
	if not gridFolder then
		return nil
	end
	if not camera then
		camera = workspace.CurrentCamera
		if not camera then
			return nil
		end
	end
	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gridFolder }
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

local function onWheelAction(actionName, inputState, inputObject)
	if inputObject.UserInputType ~= Enum.UserInputType.MouseWheel then
		return Enum.ContextActionResult.Pass
	end
	if inputObject.Position.Z > 0 then
		Selection.Next()
	elseif inputObject.Position.Z < 0 then
		Selection.Prev()
	end
	local current = Selection.GetCurrent()
	if placementPayload and placementPayload.kind == "machine" and current then
		placementPayload.tier = current.tier
	end
	hoverDirty = true
	if placementPayload and placementPayload.kind == "machine" then
		if not ghost then
			ensureGhost()
		end
		if ghost and current then
			replaceGhostPreview(placementPayload.machineType, placementPayload.tier)
			if lastTile then
				snapGhostToTile(lastTile)
			end
		end
	end
	debugutil.log("placement", "state", "wheel_action", {
		delta = inputObject.Position.Z,
		index = Selection.GetIndex(),
		tier = current and current.tier,
		payload_tier = placementPayload and placementPayload.tier,
		lastTile = lastTile and lastTile:GetFullName() or "nil",
	})
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

exitPlacement = function(reason)
	debugutil.log("placement", "state", "exit_begin", {
		reason = reason,
	})
	clearRelocationWatcher()
	if wheelBound then
		unbindWheel()
	end
	PlayerUI.HideRotationOption()
	if player and savedMinZoom and savedMaxZoom then
		player.CameraMinZoomDistance = savedMinZoom
		player.CameraMaxZoomDistance = savedMaxZoom
		savedMinZoom = nil
		savedMaxZoom = nil
		debugutil.log("placement", "state", "camera zoom restored", {})
	end
	destroyGhost("exit")
	clearHoverCache()
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
	hoverDirty = true
	if not ghost then
		ensureGhost()
	end
	if ghost then
		replaceGhostPreview(placementPayload.machineType, placementPayload.tier)
		if lastTile then
			snapGhostToTile(lastTile)
		end
		debugutil.log("placement", "state", "ghost_rebuilt", {
			reason = "selection_changed",
			tier = current.tier,
		})
	end
end

local function rotatePlacement(delta)
	if not stateModule.IsActive() then
		return false
	end
	if not placementPayload or (placementPayload.kind ~= "machine" and placementPayload.kind ~= "relocate") then
		return false
	end
	local step = delta or 90
	currentRotation = ((currentRotation + step) % 360 + 360) % 360
	placementPayload.rotation = currentRotation
	if not ghost then
		ensureGhost()
	end
	if ghost and lastTile then
		snapGhostToTile(lastTile)
	end
	debugutil.log("placement", "state", "rotate", {
		rotation = currentRotation,
		step = step,
		tile = lastTile and lastTile:GetFullName() or "nil",
	})
	return true
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
		clearHoverCache()
		PlayerUI.HideRotationOption()
		setState("Idle", "placement_inactive")
		return
	end

	if not placementActive then
		return
	end

	if entering then
		hoverDirty = true
	end

	local tile = raycastToTile()

	if not tile then
		debugutil.log("placement", "state", "hover_gate", {
			reason = "no_tile",
		})
		-- Keep lastTile/permission so the ghost can remain and reuse cached state when a tile is regained.
		return
	end

	local gridx = tile:GetAttribute("gridx")
	local gridz = tile:GetAttribute("gridz")
	local islandid = player:GetAttribute("islandid")

	local tileChanged = gridx ~= lastHoverGridX or gridz ~= lastHoverGridZ or islandid ~= lastHoverIslandId

	if not tileChanged and not hoverDirty then
		return
	end

	debugutil.log("placement", "state", "hover_gate", {
		reason = tileChanged and "rebuild" or "hover_dirty",
		gridx = gridx,
		gridz = gridz,
		islandid = islandid,
		lastGridX = lastHoverGridX,
		lastGridZ = lastHoverGridZ,
		lastIsland = lastHoverIslandId,
	})

	if tileChanged then
		lastTile = tile
		lastHoverGridX = gridx
		lastHoverGridZ = gridz
		lastHoverIslandId = islandid
		currentEvaluatedTile = nil
		lastPermission = nil
		lastReason = nil
		needPermissionRefresh = true
		log("state", "tile_hover_change", { tile = tile:GetFullName() })
	end
	hoverDirty = true

	local previousCanPlace = lastPermission
	local allowed
	if tileChanged or needPermissionRefresh then
		allowed = updatePermission(tile)
		needPermissionRefresh = false
	else
		allowed = lastPermission
	end

	if allowed == nil then
		return
	end

	if hoverDirty or not ghost then
		ensureGhost()
		if lastTile then
			snapGhostToTile(lastTile)
		end
		setGhostVisible(true, allowed)
		debugutil.log("placement", "state", "hover_debug", {
			tile = tile:GetFullName(),
			tileChanged = true,
			calledEnsure = true,
		})
		hoverDirty = false
	end

	if allowed ~= previousCanPlace then
		if allowed then
			setState("Valid", "permission_changed")
		else
			setState("Invalid", lastReason or "denied")
		end
	end
end

local function confirm(input)
	if state ~= "Valid" then
		if stateModule.IsActive() then
			if Feedback and Feedback.ShowInvalidPlacement then
				Feedback.ShowInvalidPlacement(lastReason)
			end
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
		local hasInventory = Inventory.Consume(placementPayload.machineType, placementPayload.tier, 1)
		if not hasInventory then
			debugutil.log("placement", "warn", "no_inventory", {
				machineType = placementPayload.machineType,
				tier = placementPayload.tier,
			})
			return
		end
		PlayerUI.SetTierAmount(placementPayload.tier, Inventory.GetCount(placementPayload.machineType, placementPayload.tier))
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
			rotation = placementPayload and placementPayload.rotation or currentRotation or 0,
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
			rotation = placementPayload.rotation or currentRotation or 0,
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

stateModule.SetCancelCallback(cancel)

local function enterPlacement(payload)
	if state ~= "Idle" then
		cancel()
	end
	placementPayload = payload or { kind = "tile" }
	if placementPayload.kind == "relocate" and placementPayload.machineId then
		watchRelocationSource(placementPayload.machineId)
	else
		clearRelocationWatcher()
	end
	currentRotation = placementPayload.rotation or 0
	placementPayload.rotation = currentRotation
	if placementPayload.kind == "machine" or placementPayload.kind == "relocate" then
		PlayerUI.ShowRotationOption()
	else
		PlayerUI.HideRotationOption()
	end
	clearHoverCache()
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
		hoverDirty = true
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
stateModule.SetRotateCallback(rotatePlacement)

player.CharacterAdded:Connect(function()
	_G._placementInputConsumed.consumed = false
	_G._placementInputConsumed.button = nil
	if state ~= "Idle" then
		exitPlacement("character_respawn")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		if stateModule.IsActive() then
			rotatePlacement(90)
		end
	end
	if input.KeyCode == Enum.KeyCode.E then
		if PlayerUI.IsBuildMenuVisible() or stateModule.IsActive() then
			PlayerUI.ShowMenuButtons()
			cancel(input)
			return
		end
		local cur = Selection.GetCurrent()
		if cur then
			PlayerUI.ShowBuildMenu()
			Inventory.EnsureStarter()
			if not Inventory.Has(cur.machineType, cur.tier) then
				local price = require(ReplicatedStorage.Shared.economy_config).GetMachinePrice(cur.machineType, cur.tier, player:GetAttribute("CashPerSecond"))
				PurchasePrompt.Prompt(cur.machineType, cur.tier, price, function(result)
					if result and result.accepted then
						Inventory.Add(cur.machineType, cur.tier, 1)
						PlayerUI.SetTierAmount(cur.tier, Inventory.GetCount(cur.machineType, cur.tier))
						enterPlacement({
							kind = "machine",
							machineType = cur.machineType,
							tier = cur.tier,
						})
					else
						debugutil.log("ui", "warn", "purchase_declined", { trigger = "key_E", tier = cur.tier })
					end
				end)
				return
			end
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
	if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
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
