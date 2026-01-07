local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera
local debugutil = require(ReplicatedStorage.Shared.debugutil)
local State = require(script.Parent.tileinteractionstate)
local PlacementMode = require(script.Parent.placementmode_state)
local MachineInteractionState = require(script.Parent.machineinteraction_state)
local mouse = player:GetMouse()

local HIGHLIGHT_COLOR_VALID = Color3.fromRGB(80, 180, 80)

local highlight

local currentHovered
local currentGridFolder
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = { player.Character }
local hoverActive = false
local clearedLogged = false
local unexpectedLogged = false
local hasLoggedStateLock = false
local placementBlockedLogged = false
local machineBlockedLogged = false
local machinesFolder = Workspace:WaitForChild("machines")
local characterConn
local function ensureHighlight()
	if highlight and highlight.Parent then
		return highlight
	end
	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = HIGHLIGHT_COLOR_VALID
	highlight.Enabled = false
	highlight.Adornee = nil
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = PlayerGui
	return highlight
end

local function clearHoverForMachine()
	local hl = ensureHighlight()
	if not currentHovered then
		return
	end
	currentHovered = nil
	hl.Enabled = false
	hl.Adornee = nil
	State.ClearHoveredTile()
	State.SetState("Idle", "over_machine")
	clearedLogged = true
end

local function isOverMachine(inst)
	local node = inst
	while node do
		if node:IsA("Model") and node.Parent == machinesFolder then
			return true
		end
		node = node.Parent
	end
	return false
end

local function ForceClearHover()
	local hl = ensureHighlight()
	if currentHovered then
		debugutil.log("interaction", "state", "hover force-cleared", { reason = "external_cancel" })
	end
	currentHovered = nil
	hl.Enabled = false
	hl.Adornee = nil
	State.ClearHoveredTile()
	State.SetState("Idle", "external_cancel")
	hasLoggedStateLock = false
	clearedLogged = true
end

local function destroyStrayHighlights()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Highlight") then
			if inst.Parent == workspace or inst.Adornee == nil then
				debugutil.log("interaction", "state", "removed stray highlight", {
					path = inst:GetFullName(),
				})
				inst:Destroy()
			end
		end
	end
end

destroyStrayHighlights()

local function clearHighlight()
	local hl = ensureHighlight()
	if currentHovered then
		debugutil.log("interaction", "state", "hover leave", { name = currentHovered.Name })
	end
	currentHovered = nil
	hl.Enabled = false
	hl.Adornee = nil
	State.ClearHoveredTile()
	if not clearedLogged then
		debugutil.log("interaction", "state", "hover cleared", { reason = "no valid hit" })
		clearedLogged = true
	end
	State.SetState("Idle", "hover cleared")
	hasLoggedStateLock = false
end

local function updateGridFolder()
	local islandId = player:GetAttribute("islandid")
	if not islandId then
		currentGridFolder = nil
		raycastParams.FilterDescendantsInstances = { player.Character, machinesFolder }
		return
	end
	local islandsFolder = workspace:FindFirstChild("islands")
	if not islandsFolder then
		currentGridFolder = nil
		raycastParams.FilterDescendantsInstances = { player.Character, machinesFolder }
		return
	end
	local islandModel = islandsFolder:FindFirstChild("player_" .. tostring(islandId))
	if not islandModel then
		currentGridFolder = nil
		raycastParams.FilterDescendantsInstances = { player.Character, machinesFolder }
		return
	end
	currentGridFolder = islandModel:FindFirstChild("grid")
	raycastParams.FilterDescendantsInstances = { player.Character, machinesFolder }
end

local function isValidHit(instance)
	if not instance or not instance:IsA("BasePart") then
		return false
	end
	if instance:IsA("Highlight") and instance.Parent == workspace and not unexpectedLogged then
		unexpectedLogged = true
		debugutil.log("interaction", "warn", "unexpected highlight detected", {
			path = instance:GetFullName(),
		})
	end
	if not currentGridFolder or instance.Parent ~= currentGridFolder then
		return false
	end
	if not instance.Name:match("^tile_z%d+_x%d+$") then
		return false
	end
	local unlocked = instance:GetAttribute("unlocked")
	if unlocked == true then
		return false
	end
	return true
end

local function setHover(part)
	if currentHovered == part then
		return
	end
	local hl = ensureHighlight()
	currentHovered = part
	hl.Adornee = part
	hl.Enabled = true
	clearedLogged = false
	debugutil.log("interaction", "state", "hover enter", { name = part.Name })
	State.SetHoveredTile(part)
	State.SetState("Hovering", "tile under cursor")
	hasLoggedStateLock = false
end

local function handleMouseMove()
	local target = mouse.Target
	if target and isOverMachine(target) then
		return
	end
	if isOverMachine(target) then
		clearHoverForMachine()
		return
	end

	if PlacementMode.IsActive() then
		if not placementBlockedLogged then
			debugutil.log("interaction", "state", "hover blocked", { reason = "placement_active" })
			placementBlockedLogged = true
		end
		return
	end
	placementBlockedLogged = false

if MachineInteractionState.IsActive() and not MachineInteractionState.IsRelocating() then
	if not machineBlockedLogged then
		debugutil.log("interaction", "state", "hover skipped", { reason = "machine_active" })
		machineBlockedLogged = true
	end
	ForceClearHover()
	return
elseif MachineInteractionState.IsRelocating() and machineBlockedLogged then
	debugutil.log("interaction", "state", "hover unblocked", { reason = "relocating" })
	machineBlockedLogged = false
end
machineBlockedLogged = false

	local st = State.GetState()
	if st == "Pending" or st == "Confirmed" then
		if not hasLoggedStateLock then
			debugutil.log("interaction", "state", "hover skipped", { reason = "state_lock", state = st })
			hasLoggedStateLock = true
		end
		return
	end

	updateGridFolder()
	if not currentGridFolder then
		clearHighlight()
		return
	end

	local hit = mouse.Hit
	if not hit then
		clearHighlight()
		return
	end

	local origin = hit.Position + Vector3.new(0, 5, 0)
	local direction = Vector3.new(0, -50, 0)

	local result = workspace:Raycast(origin, direction, raycastParams)
	if result and isValidHit(result.Instance) and State.GetState() ~= "Pending" and State.GetState() ~= "Confirmed" then
		setHover(result.Instance)
	else
		if State.GetState() == "Hovering" then
			clearHighlight()
		end
	end
end

local function onCharacterAdded()
	clearHighlight()
	currentGridFolder = nil
	raycastParams.FilterDescendantsInstances = { player.Character, machinesFolder }
	hoverActive = false
	hasLoggedStateLock = false
	clearedLogged = false
	unexpectedLogged = false
	placementBlockedLogged = false
	machineBlockedLogged = false
	updateGridFolder()
end

local function activateHover()
	if hoverActive then
		return
	end
	hoverActive = true
	debugutil.log("client", "init", "hover ready", {
		islandid = player:GetAttribute("islandid"),
	})
	mouse.Move:Connect(function()
		if not hoverActive then
			return
		end
		handleMouseMove()
	end)
end

if not characterConn then
	characterConn = player.CharacterAdded:Connect(function()
		onCharacterAdded()
		if player:GetAttribute("islandid") ~= nil then
			activateHover()
		end
	end)
end

local function onIslandIdChanged()
	local islandId = player:GetAttribute("islandid")
	if islandId ~= nil then
		activateHover()
	end
end

if player:GetAttribute("islandid") ~= nil then
	activateHover()
else
	player:GetAttributeChangedSignal("islandid"):Connect(onIslandIdChanged)
end

_G._tileHoverAPI = {
	ForceClearHover = ForceClearHover,
}
