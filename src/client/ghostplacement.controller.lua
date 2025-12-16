local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local debugutil = require(ReplicatedStorage.Shared.debugutil)

debugutil.log("placement", "init", "ghost placement controller ready")

local ghostTemplate = ReplicatedStorage:WaitForChild("ghostplacement")
local ghost = ghostTemplate:Clone()
ghost.Parent = workspace

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

local function setGhostVisible(visible)
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and 0.2 or 1
		end
	end
end

local function setGhostTint(color)
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function hideGhost()
	setGhostVisible(false)
end

hideGhost()

local remotes = ReplicatedStorage.Shared.remotes
local canPlaceFn = remotes:WaitForChild("canPlaceOnTile")

local lastTile
local lastCanPlace

local function updatePermission(tile)
	if tile == lastTile and lastCanPlace ~= nil then
		return lastCanPlace
	end
	local allowed, reason = canPlaceFn:InvokeServer(tile)
	lastTile = tile
	lastCanPlace = allowed
	debugutil.log("placement", "decision", "permission_result", {
		tile = tile:GetFullName(),
		allowed = allowed,
		reason = reason,
	})
	return allowed
end

local function onCharacterAdded()
	lastTile = nil
	lastCanPlace = nil
	hideGhost()
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

RunService.RenderStepped:Connect(function()
	local tile = getTileHit()
	if not tile then
		lastTile = nil
		lastCanPlace = nil
		hideGhost()
		return
	end

	if tile ~= lastTile then
		debugutil.log("placement", "state", "tile_hover_change", { tile = tile:GetFullName() })
	end

	local allowed = updatePermission(tile)

	positionGhost(tile)
	setGhostVisible(true)
	if allowed then
		setGhostTint(Color3.fromRGB(80, 180, 80))
	else
		setGhostTint(Color3.fromRGB(220, 80, 80))
	end
end)
