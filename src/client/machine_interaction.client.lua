-- machine_interaction: client-only hover/select visuals + intent dispatch.
-- Visuals only; server remains authoritative for selection validation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local machineIntentEvent = remotes:WaitForChild("machine_intent")
local debug = require(ReplicatedStorage.Shared.debugutil)
local MachineInteraction = {}
local MachineInteractionState = require(script.Parent.machineinteraction_state)
local PlacementModeState = require(script.Parent.placementmode_state)

local machinesFolder = Workspace:WaitForChild("machines")

local HOVER_COLOR = Color3.fromRGB(150, 180, 220)
local SELECT_COLOR = Color3.fromRGB(255, 210, 90)
local HOVER_FILL_TRANSPARENCY = 0.75
local SELECT_FILL_TRANSPARENCY = 0.35

local currentHover
local currentSelected
local hoverHighlight
local selectedHighlight
local editOptions = playerGui:WaitForChild("editoptions")
local editOptionsConnected = false

local function getMachineId(model)
	if not model then
		return nil
	end
	return model:GetAttribute("machineId") or model:GetAttribute("machineid")
end

local function logState(message, data)
	debug.log("machine", "state", message, data)
end

local function handleDelete()
	if not currentSelected then
		return
	end
	local machineId = getMachineId(currentSelected)
	debug.log("machine", "decision", "delete_pressed", {
		machine = currentSelected:GetFullName(),
		machineId = machineId,
	})
	if not machineId then
		debug.log("machine", "warn", "missing_machine_id", {
			machine = currentSelected:GetFullName(),
		})
		return
	end
	machineIntentEvent:FireServer({
		intent = "delete",
		machineId = machineId,
	})
end

local function handleMove()
	if not currentSelected then
		return
	end
	local machineId = getMachineId(currentSelected)
	local machineType = currentSelected:GetAttribute("machineType")
	local tier = currentSelected:GetAttribute("tier")
	local rotation = currentSelected:GetAttribute("rotation")

	debug.log("machine", "decision", "move_pressed", {
		machine = currentSelected:GetFullName(),
		machineId = machineId,
	})

	if machineId then
		machineIntentEvent:FireServer({
			intent = "move",
			machineId = machineId,
		})
	else
		debug.log("machine", "warn", "missing_machine_id", {
			machine = currentSelected:GetFullName(),
		})
		return
	end

	if editOptions then
		editOptions.Enabled = false
		editOptions.Adornee = nil
	end

	local payload = {
		kind = "relocate",
		machineId = machineId,
		machineType = machineType,
		tier = tier,
		rotation = rotation,
	}

	clearSelected()
	PlacementModeState.RequestEnter(payload)
end

local function handleRotate()
	if not currentSelected then
		return
	end
	local machineId = getMachineId(currentSelected)
	debug.log("machine", "decision", "rotate_pressed", {
		machine = currentSelected:GetFullName(),
		machineId = machineId,
	})
	if not machineId then
		debug.log("machine", "warn", "missing_machine_id", {
			machine = currentSelected:GetFullName(),
		})
		return
	end
	machineIntentEvent:FireServer({
		intent = "rotate",
		machineId = machineId,
		delta = 90,
	})
end

local function connectEditOptions()
	if editOptionsConnected or not editOptions then
		return
	end
	local deleteBtn = editOptions:FindFirstChild("delete_button", true)
	local moveBtn = editOptions:FindFirstChild("move_button", true)
	local rotateBtn = editOptions:FindFirstChild("rotate_button", true)

	if deleteBtn and (deleteBtn:IsA("ImageButton") or deleteBtn:IsA("TextButton")) then
		deleteBtn.Activated:Connect(handleDelete)
	else
		debug.log("machine", "warn", "editoptions_button_missing", {
			name = "delete_button",
			path = editOptions:GetFullName(),
		})
	end

	if moveBtn and (moveBtn:IsA("ImageButton") or moveBtn:IsA("TextButton")) then
		moveBtn.Activated:Connect(handleMove)
	else
		debug.log("machine", "warn", "editoptions_button_missing", {
			name = "move_button",
			path = editOptions:GetFullName(),
		})
	end

	if rotateBtn and (rotateBtn:IsA("ImageButton") or rotateBtn:IsA("TextButton")) then
		rotateBtn.Activated:Connect(handleRotate)
	else
		debug.log("machine", "warn", "editoptions_button_missing", {
			name = "rotate_button",
			path = editOptions:GetFullName(),
		})
	end
	editOptionsConnected = true
end

local function ensureHoverHighlight()
	if hoverHighlight then
		return hoverHighlight
	end
	local h = Instance.new("Highlight")
	h.Name = "MachineHoverHighlight"
	h.FillColor = HOVER_COLOR
	h.FillTransparency = HOVER_FILL_TRANSPARENCY
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	hoverHighlight = h
	return h
end

local function ensureSelectedHighlight()
	if selectedHighlight then
		return selectedHighlight
	end
	local h = Instance.new("Highlight")
	h.Name = "MachineSelectedHighlight"
	h.FillColor = SELECT_COLOR
	h.FillTransparency = SELECT_FILL_TRANSPARENCY
	h.OutlineTransparency = 0.05
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	selectedHighlight = h
	return h
end

local function clearHover()
	if currentHover then
		logState("hover_clear", {
			machine = currentHover:GetFullName(),
		})
	end
	currentHover = nil
	if hoverHighlight then
		hoverHighlight.Adornee = nil
		hoverHighlight.Parent = nil
	end
end

local function clearSelected()
	if currentSelected then
		logState("deselect", {
			machine = currentSelected:GetFullName(),
		})
	end
	currentSelected = nil
	if selectedHighlight then
		selectedHighlight.Adornee = nil
		selectedHighlight.Parent = nil
	end
	MachineInteractionState.SetActive(false)
	if editOptions then
		editOptions.Enabled = false
		editOptions.Adornee = nil
		debug.log("machine", "state", "editoptions_close", {})
	end
end

local function resolveMachine(target)
	if not target or not target:IsDescendantOf(Workspace) then
		return nil
	end

	local node = target
	while node and node ~= Workspace do
		if node:IsA("Model") and node.Parent == machinesFolder then
			return node
		end
		node = node.Parent
	end

	return nil
end

local function resolveGrid(model)
	if not model then
		return nil, nil
	end
	return model:GetAttribute("gridx"), model:GetAttribute("gridz")
end

local function setHover(machine)
	if machine == currentHover or machine == currentSelected then
		return
	end

	if machine then
		currentHover = machine
		local h = ensureHoverHighlight()
		h.Adornee = machine
		h.Parent = machine
		logState("hover", { machine = machine:GetFullName() })
	else
		clearHover()
	end
end

local function setSelected(machine)
	if machine == currentSelected then
		return
	end

	clearSelected()
	currentSelected = machine
	local h = ensureSelectedHighlight()
	h.Adornee = machine
	h.Parent = machine
	MachineInteractionState.SetActive(true)
	logState("select", { machine = machine:GetFullName() })
	if editOptions then
		connectEditOptions()
		local adornPart = nil
		if machine.PrimaryPart and machine.PrimaryPart:IsA("BasePart") then
			adornPart = machine.PrimaryPart
		else
			adornPart = machine:FindFirstChildWhichIsA("BasePart", true)
		end

		if adornPart then
			editOptions.Adornee = adornPart
			editOptions.Enabled = true
			debug.log("machine", "state", "editoptions_open", {
				adornee = adornPart:GetFullName(),
				machine = machine:GetFullName(),
			})
		else
			editOptions.Enabled = false
			editOptions.Adornee = nil
			debug.log("machine", "warn", "editoptions_no_adornee", {
				machine = machine:GetFullName(),
			})
		end
	end
end

function MachineInteraction.IsActive()
	return currentSelected ~= nil
end

local function sendSelect(machine)
	local gridx, gridz = resolveGrid(machine)
	if typeof(gridx) ~= "number" or typeof(gridz) ~= "number" then
		return
	end

	machineIntentEvent:FireServer({
		intent = "select",
		gridx = gridx,
		gridz = gridz,
	})
end

local function onClick()
	local target = mouse.Target
	local machine = resolveMachine(target)
	if not machine then
		clearHover()
		clearSelected()
		MachineInteractionState.SetActive(false)
		return
	end

	setSelected(machine)
	clearHover()
	sendSelect(machine)
end

local function onEsc(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		clearSelected()
		clearHover()
		MachineInteractionState.SetActive(false)
	end
end

local function step()
	if currentSelected and (not currentSelected.Parent or currentSelected.Parent ~= machinesFolder) then
		clearSelected()
	end

	local target = mouse.Target
	local machine = resolveMachine(target)

	if machine and machine ~= currentSelected then
		setHover(machine)
	else
		if currentHover then
			clearHover()
		end
	end
end

mouse.Button1Down:Connect(onClick)
UserInputService.InputBegan:Connect(onEsc)
RunService.RenderStepped:Connect(step)
connectEditOptions()

return MachineInteraction
