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

local ghostTemplate = ReplicatedStorage:WaitForChild("ghostplacement")
task.defer(function()
	for _, part in ipairs(ghostTemplate:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.LocalTransparencyModifier = 1
			part.CastShadow = false
		end
	end
	local anchorPart = ghostTemplate:FindFirstChild("anchor", true)
	if anchorPart and anchorPart:IsA("BasePart") then
		anchorPart.Transparency = 1
		anchorPart.LocalTransparencyModifier = 1
		anchorPart.CastShadow = false
		anchorPart.Anchored = true
	end
end)
local ghost -- lazily created

local function setGhostCollision(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

local function setGhostTint(color)
	if not ghost then
		return
	end
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

local function destroyGhost(reason)
	if ghost then
		ghost:Destroy()
		ghost = nil
		DebugUtil.log("ghost", "state", "destroyed", { reason = reason })
	end
end

local function ensureGhost(reason)
	if ghost then
		return ghost
	end
	ghost = ghostTemplate:Clone()
	setGhostCollision(ghost)
	ghost.Parent = Workspace
	DebugUtil.log("ghost", "state", "created", { reason = reason })
	DebugUtil.log("ghost", "state", "active", { reason = reason })
	return ghost
end

local function setGhostVisible(visible, reason)
	if not ghost then
		return
	end
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = visible and 0 or 1
		end
	end

	DebugUtil.log("ghost", "state", visible and "visible" or "hidden", {
		reason = reason,
	})
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
	destroyGhost("character_added_no_hover")
end

player.CharacterAdded:Connect(onCharacterAdded)

local function positionGhost(tile)
	if not ghost then
		return
	end
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

RunService.RenderStepped:Connect(function()
	local placementActive = PlacementMode.IsActive()
	local placementChanged = placementActive ~= lastPlacementActive
	local tile = getTileHit()

	if placementChanged and not placementActive then
		lastTile = nil
		lastCanPlace = nil
		destroyGhost("placement_exit_force")
	end
	lastPlacementActive = placementActive

	if not placementActive then
		destroyGhost("placement_inactive")
		return
	end

	if not tile then
		lastTile = nil
		lastCanPlace = nil
		destroyGhost("no_hover")
		return
	end

	if tile ~= lastTile then
		DebugUtil.log("placement", "state", "tile_hover_change", { tile = tile:GetFullName() })
	end

	local previousCanPlace = lastCanPlace
	local allowed = updatePermission(tile)
	local permissionChanged = (allowed ~= previousCanPlace)

	if not allowed then
		destroyGhost("hover_invalid")
		return
	end

	ensureGhost("hover_valid")
	positionGhost(tile)
	if allowed then
		setGhostTint(Color3.fromRGB(80, 180, 80))
	else
		setGhostTint(Color3.fromRGB(220, 80, 80))
	end

	if placementChanged or tile ~= lastTile or permissionChanged then
		setGhostVisible(true, placementChanged and "placement_enter" or (permissionChanged and "permission_result" or "hover_change"))
	end
end)
