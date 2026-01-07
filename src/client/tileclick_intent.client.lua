local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local debugutil = require(ReplicatedStorage.Shared.debugutil)
local UnlockFeedback = require(script.Parent.visuals.tile_unlock_feedback)
local playerGui = player:WaitForChild("PlayerGui")
local State = require(script.Parent.tileinteractionstate)
local PlacementMode = require(script.Parent.placementmode_state)
local PlacementFeedback = require(script.Parent.placement_feedback)

local remotesFolder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("remotes")
local tileunlockRemote = remotesFolder and remotesFolder:FindFirstChild("tileunlock")

local hoverAPI

local USE_BUILD_BOARD = true

local pendingSetEvent = Instance.new("BindableEvent")
local pendingClearedEvent = Instance.new("BindableEvent")
local confirmEvent = Instance.new("BindableEvent")
local clearEvent = Instance.new("BindableEvent")

local VALID_COLOR = Color3.fromRGB(80, 180, 80)
local INVALID_COLOR = Color3.fromRGB(220, 80, 80)
local PENDING_COLOR = Color3.fromRGB(240, 200, 80)

local pulseHighlight
local pendingHighlight

local function ensureHighlights()
	if not playerGui or not playerGui.Parent then
		return
	end
	if not pulseHighlight or not pulseHighlight.Parent then
		pulseHighlight = Instance.new("Highlight")
		pulseHighlight.FillTransparency = 1
		pulseHighlight.OutlineTransparency = 0
		pulseHighlight.Enabled = false
		pulseHighlight.Parent = playerGui
	end
	if not pendingHighlight or not pendingHighlight.Parent then
		pendingHighlight = Instance.new("Highlight")
		pendingHighlight.FillTransparency = 1
		pendingHighlight.OutlineTransparency = 0
		pendingHighlight.OutlineColor = PENDING_COLOR
		pendingHighlight.Enabled = false
		pendingHighlight.Parent = playerGui
	end
end

ensureHighlights()

for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("Highlight") then
		debugutil.log("interaction", "error", "illegal workspace highlight", {
			path = inst:GetFullName(),
		})
		inst:Destroy()
	end
end

local pendingTile
local pendingGridX
local pendingGridZ
local inFlight = false
local lastBlockedKey = nil
local lastConfirmStamp = nil

local function forceClearHover()
	if not hoverAPI then
		hoverAPI = _G._tileHoverAPI
	end
	if hoverAPI and hoverAPI.ForceClearHover then
		hoverAPI.ForceClearHover()
		return
	end
	for _, inst in ipairs(playerGui:GetDescendants()) do
		if inst:IsA("Highlight") then
			inst.Enabled = false
			inst.Adornee = nil
		end
	end
end

local function logClient(message, data)
	local parts = {}
	for k, v in pairs(data or {}) do
		table.insert(parts, string.format("%s=%s", k, tostring(v)))
	end
	local suffix = #parts > 0 and (" | " .. table.concat(parts, " ")) or ""
	print(string.format("[interaction][client] %s%s", message, suffix))
end

local function clearPulse()
	ensureHighlights()
	pulseHighlight.Enabled = false
	pulseHighlight.Adornee = nil
end

local function clearPending(reason)
	ensureHighlights()
	if pendingTile then
		debugutil.log("interaction", "state", "pending cleared", { reason = reason })
		clearEvent:Fire()
		pendingClearedEvent:Fire(reason or "cleared")
	end
	pendingTile = nil
	pendingGridX = nil
	pendingGridZ = nil
	pendingHighlight.Enabled = false
	pendingHighlight.Adornee = nil
	State.ClearPendingTile()
end

local function setPending(part)
	if not part or part.Parent == nil then
		debugutil.log("interaction", "warn", "pending set blocked", { reason = "invalid_tile" })
		return
	end
	if PlacementMode.IsActive() then
		debugutil.log("interaction", "warn", "pending set blocked", { reason = "placement_active" })
		return
	end
	pendingTile = part
	pendingHighlight.Adornee = part
	pendingHighlight.Enabled = true
	local gridx = part:GetAttribute("gridx")
	local gridz = part:GetAttribute("gridz")
	debugutil.log("interaction", "state", "pending set", { gridx = gridx, gridz = gridz })
	pendingGridX = gridx
	pendingGridZ = gridz
	State.SetPendingTile(part)
	pendingSetEvent:Fire(part, gridx, gridz)
end

_G._tileIntentAPI = {
	Confirmed = confirmEvent.Event,
	Cleared = clearEvent.Event,
	PendingSet = pendingSetEvent.Event,
	PendingCleared = pendingClearedEvent.Event,
	ClearPending = function(reason)
		clearPending(reason or "external")
	end,
}

local function pulse(part, isValid)
	if not part then
		return
	end
	ensureHighlights()
	pulseHighlight.Adornee = part
	pulseHighlight.OutlineColor = isValid and VALID_COLOR or INVALID_COLOR
	pulseHighlight.Enabled = true

	local tween = TweenService:Create(
		pulseHighlight,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ OutlineTransparency = 0.5 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		pulseHighlight.OutlineTransparency = 0
		clearPulse()
	end)
end

local function getTargetFromMouse()
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
	params.FilterDescendantsInstances = { player.Character or player }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
	return result and result.Instance or nil
end

local function findTileByCoords(gridx, gridz)
	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" then
		return nil
	end
	local islandId = player:GetAttribute("islandid")
	if not islandId then
		return nil
	end
	local gridFolder = workspace:FindFirstChild("islands")
	gridFolder = gridFolder and gridFolder:FindFirstChild("player_" .. tostring(islandId))
	gridFolder = gridFolder and gridFolder:FindFirstChild("grid")
	if not gridFolder then
		return nil
	end
	return gridFolder:FindFirstChild(string.format("tile_z%d_x%d", gridz, gridx))
end

local function onInputBegan(input, gameProcessed)
	if gameProcessed then
		return
	end
	if _G._placementInputConsumed and _G._placementInputConsumed.consumed then
		debugutil.log("interaction", "decision", "input ignored", { reason = "placement_consumed" })
		return
	end
	if PlacementMode.IsActive() then
		debugutil.log("interaction", "state", "blocked", { reason = "placement_active" })
		PlacementFeedback.Show()
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if State.IsBlocked() then
		return
	end
	if inFlight then
		debugutil.log("interaction", "warn", "unlock intent skipped", { reason = "in_flight" })
		return
	end

	local hovered = State.GetHoveredTile()
	local clickHit = getTargetFromMouse()
if not clickHit or not clickHit:IsA("BasePart") then
	if not hovered then
		forceClearHover()
		return
	end
	if State.GetState() == "Pending" then
		clearPending("clicked_outside")
		State.SetState("Idle", "clicked outside")
		State.ClearHoveredTile()
		forceClearHover()
		debugutil.log("interaction", "state", "pending cleared", { reason = "clicked_outside" })
	end
	return
end

	local gridx = hovered and hovered:GetAttribute("gridx")
	local gridz = hovered and hovered:GetAttribute("gridz")
	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" then
		return
	end

	if pendingTile == nil or pendingTile ~= hovered then
		-- first click: arm UI via pending (placement already blocked above)
		if State.GetState() ~= "Hovering" then
			debugutil.log("interaction", "warn", "input blocked", { reason = "invalid_state_for_pending" })
			return
		end
		State.ClearHoveredTile()
		setPending(hovered)
		State.SetState("Pending", "first click")
		return
	end

	if pendingTile and pendingTile.Parent == nil then
		debugutil.log("interaction", "warn", "pending tile invalid", { reason = "destroyed" })
		clearPending("invalid_tile")
		State.SetState("Idle", "pending invalid")
		return
	end

	local now = os.clock()
	if lastConfirmStamp and now - lastConfirmStamp < (1 / 60) then
		debugutil.log("interaction", "warn", "input blocked", { reason = "double_confirm_same_frame" })
		return
	end
	lastConfirmStamp = now

	clearPending("confirmed")
	State.SetState("Confirmed", "second click")
	logClient("pending confirmed", { gridx = gridx, gridz = gridz })
	pulse(hovered, true)
	forceClearHover()
	State.ClearHoveredTile()
	confirmEvent:Fire(hovered)
	if USE_BUILD_BOARD then
		State.SetState("Idle", "confirmed_no_unlock")
		return
	end
	logClient("unlock requested after confirm", { gridx = gridx, gridz = gridz })
	inFlight = true
	if tileunlockRemote then
		tileunlockRemote:FireServer(gridx, gridz)
	end
	State.SetState("Idle", "unlock sent")
end

local function onCharacterAdded()
	clearPulse()
	clearPending()
end

-- clear pending if placement gets activated while armed
local placementWasActive = PlacementMode.IsActive()
RunService.Heartbeat:Connect(function()
	if not camera then
		camera = workspace.CurrentCamera
	end

	local nowActive = PlacementMode.IsActive()
	if nowActive and not placementWasActive and pendingTile then
		debugutil.log("interaction", "decision", "pending cleared", { reason = "placement_enter" })
		clearPending("placement_enter")
		State.SetState("Idle", "placement enter")
		forceClearHover()
		State.ClearHoveredTile()
	end
	placementWasActive = nowActive
end)

player.CharacterAdded:Connect(onCharacterAdded)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if _G._placementInputConsumed and _G._placementInputConsumed.consumed then
		debugutil.log("interaction", "decision", "input ignored", { reason = "placement_consumed" })
		PlacementFeedback.Show("Placement active")
		return
	end
	if PlacementMode.IsActive() then
		debugutil.log("interaction", "state", "blocked", { reason = "placement_active" })
		PlacementFeedback.Show()
		return
	end
	onInputBegan(input, gameProcessed)
end)

UserInputService.InputEnded:Connect(function(input)
	if _G._placementInputConsumed and _G._placementInputConsumed.consumed and _G._placementInputConsumed.button == input.UserInputType then
		_G._placementInputConsumed.consumed = false
		_G._placementInputConsumed.button = nil
		debugutil.log("interaction", "state", "input consumption reset", {})
	end
end)

if tileunlockRemote then
	tileunlockRemote.OnClientEvent:Connect(function(payload)
		inFlight = false
		local success = payload and payload.success
		local key = payload and (payload.gridx .. "_" .. payload.gridz)
		if not success then
			lastBlockedKey = key
			debugutil.log("interaction", "warn", "unlock response blocked", payload or {})
		else
			lastBlockedKey = nil
			debugutil.log("interaction", "state", "unlock response success", payload or {})
			local tile = payload and findTileByCoords(payload.gridx, payload.gridz)
			if tile then
				UnlockFeedback.play(tile)
			end
		end
	end)
end

player.CharacterAdded:Connect(function()
	playerGui = player:WaitForChild("PlayerGui")
	ensureHighlights()
	clearPending("character_respawn")
	clearPulse()
end)
