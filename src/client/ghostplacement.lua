local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DebugUtil = require(ReplicatedStorage.Shared.debugutil)
local PlacementMode = require(script.Parent.placementmode_state)

DebugUtil.log("placement", "init", "ghost placement controller ready")

local PREVIEW_ROOT = ReplicatedStorage:WaitForChild("Previews")

local ghostTemplate = ReplicatedStorage:WaitForChild("ghostplacement")
local ghost = ghostTemplate:Clone()
ghost.Parent = PREVIEW_ROOT
DebugUtil.log("preview", "state", "created", {})

local function setGhostCollision(enabled)
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

setGhostCollision(false)

local function setGhostTint(color)
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local remotes = ReplicatedStorage.Shared.remotes
local canPlaceFn = remotes:WaitForChild("canplaceontile")

local lastTile
local lastCanPlace
local lastPlacementActive = false
local lastHoverValid = false

local function mountGhost(reason)
	if ghost.Parent ~= Workspace then
		ghost.Parent = Workspace
		DebugUtil.log("ghost", "state", "mounted", { reason = reason })
	end
end

local function unmountGhost(reason)
	if ghost.Parent ~= PREVIEW_ROOT then
		ghost.Parent = PREVIEW_ROOT
		DebugUtil.log("ghost", "state", "unmounted", { reason = reason })
	end
end

local function updatePermission(tile)
	if tile == lastTile and lastCanPlace ~= nil then
		return lastCanPlace
	end
	local allowed, reason = canPlaceFn:InvokeServer(tile)
	lastTile = tile
	lastCanPlace = allowed
	DebugUtil.log("placement", "decision", "permission_result", {
		tile = tile:GetFullName(),
		allowed = allowed,
		reason = reason,
	})
	return allowed
end

local function onCharacterAdded()
	lastTile = nil
	lastCanPlace = nil
	unmountGhost("character_added_no_hover")
end

player.CharacterAdded:Connect(onCharacterAdded)

local function positionGhost(tile)
	local primary = tile:IsA("Model") and tile.PrimaryPart or tile
	if not primary then
		return
	end
	local ghostPrimary = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart")
	if not ghostPrimary then
		return
	end

	local tileY = primary.Position.Y + primary.Size.Y * 0.5
	local ghostOffset = ghostPrimary.Size.Y * 0.5
	local targetCFrame = CFrame.new(primary.Position.X, tileY + ghostOffset, primary.Position.Z)

	local delta = targetCFrame.Position - ghostPrimary.Position
	ghost:PivotTo(ghost:GetPivot() + delta)
end

local function getTileHit()
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

	local inst = result.Instance
	if not inst or not inst:IsA("BasePart") then
		return nil
	end

	if not inst.Name:match("^tile_z%d+_x%d+$") then
		return nil
	end

	local islandId = player:GetAttribute("islandid")
	if not islandId then
		return nil
	end

	local parentFolder = inst.Parent
	local expectedFolder = workspace:FindFirstChild("islands") and workspace.islands:FindFirstChild("player_" .. tostring(islandId)) and workspace.islands["player_" .. tostring(islandId)]:FindFirstChild("grid")
	if parentFolder ~= expectedFolder then
		return nil
	end

	return inst
end

local function updateGhostMount(placementActive, tile, hoverValid, reason)
	if not placementActive then
		unmountGhost(reason or "placement_inactive")
		return
	end

	if not tile then
		unmountGhost(reason or "no_hover")
		return
	end

	if not hoverValid then
		unmountGhost(reason or "hover_invalid")
		return
	end

	mountGhost(reason or "hover_valid")
end

RunService.RenderStepped:Connect(function()
	local placementActive = PlacementMode.IsActive()
	local placementChanged = placementActive ~= lastPlacementActive
	local tile = getTileHit()

	if placementChanged and not placementActive then
		lastTile = nil
		lastCanPlace = nil
		updateGhostMount(false, nil, false, "placement_exit_force")
	end
	lastPlacementActive = placementActive

	if not placementActive then
		return
	end

	if not tile then
		lastTile = nil
		lastCanPlace = nil
		updateGhostMount(placementActive, nil, false, "no_hover")
		return
	end

	if tile ~= lastTile then
		DebugUtil.log("placement", "state", "tile_hover_change", { tile = tile:GetFullName() })
	end

	local allowed = updatePermission(tile)
	local permissionChanged = (allowed ~= lastCanPlace)

	positionGhost(tile)
	if allowed then
		setGhostTint(Color3.fromRGB(80, 180, 80))
	else
		setGhostTint(Color3.fromRGB(220, 80, 80))
	end

	if placementChanged or tile ~= lastTile or permissionChanged then
		updateGhostMount(placementActive, tile, allowed, placementChanged and (placementActive and "placement_enter" or "placement_exit") or (permissionChanged and "permission_result" or "hover_change"))
	end
end)
