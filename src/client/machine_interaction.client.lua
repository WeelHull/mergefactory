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
local Inventory = require(script.Parent.inventory)
local PlayerUI = require(script.Parent.playerui_controller)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)

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
local deleteCostLabel
local characterConn
local lastDeletePriceUpdate = 0

local function resolveGrid(model)
	if not model then
		return nil, nil
	end
	return model:GetAttribute("gridx"), model:GetAttribute("gridz")
end

local function formatCompact(amount)
	local n = tonumber(amount) or 0
	local abs = math.abs(n)
	local suffix = ""
	local value = n
	if abs >= 1_000_000_000 then
		value = n / 1_000_000_000
		suffix = "B"
	elseif abs >= 1_000_000 then
		value = n / 1_000_000
		suffix = "M"
	elseif abs >= 1_000 then
		value = n / 1_000
		suffix = "K"
	end
	if suffix ~= "" then
		value = math.floor(value * 10 + 0.5) / 10
	else
		value = math.floor(value)
	end
	return tostring(value) .. suffix
end

local function countOwnedMachines()
	local count = 0
	for _, m in ipairs(machinesFolder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("ownerUserId") == player.UserId then
			count += 1
		end
	end
	return math.max(1, count)
end

local function computeDeleteCost(model)
	if not model then
		return 0
	end
	local machineType = model:GetAttribute("machineType")
	local tier = model:GetAttribute("tier")
	local cashPerSecond = player:GetAttribute("CashPerSecond") or 0
	local cash = player:GetAttribute("Cash") or 0
	local count = countOwnedMachines()
	return EconomyConfig.GetStoragePrice(machineType, tier, cashPerSecond, cash, count)
end

local function updateDeleteCostLabel(model)
	if not deleteCostLabel or not deleteCostLabel:IsA("TextLabel") then
		return
	end
	local price = computeDeleteCost(model)
	deleteCostLabel.Text = formatCompact(price) .. " C$"
end

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
	local machineType = currentSelected:GetAttribute("machineType")
	local tier = currentSelected:GetAttribute("tier")
	local price = computeDeleteCost(currentSelected)
	local cash = player:GetAttribute("Cash") or 0
	debug.log("machine", "decision", "delete_pressed", {
		machine = currentSelected:GetFullName(),
		machineId = machineId,
		price = price,
		cash = cash,
	})
	if price > 0 and cash < price then
		local Notifier = require(script.Parent.notifier)
		Notifier.Insufficient()
		return
	end
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
	local gridx, gridz = resolveGrid(currentSelected)

	MachineInteractionState.SetRelocating(true, "move_pressed")

	debug.log("machine", "decision", "move_pressed", {
		machine = currentSelected:GetFullName(),
		machineId = machineId,
	})

	if machineId then
		machineIntentEvent:FireServer({
			intent = "move",
			machineId = machineId,
			gridx = gridx,
			gridz = gridz,
		})
		debug.log("machine", "decision", "move_intent_sent", {
			machineId = machineId,
			gridx = gridx,
			gridz = gridz,
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
		fromGridX = gridx,
		fromGridZ = gridz,
		ignoreMachineId = machineId,
	}

	local entered = PlacementModeState.RequestEnter(payload)
	if not entered then
		debug.log("machine", "warn", "move_enter_failed", {
			machineId = machineId,
		})
	end
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
	deleteCostLabel = deleteBtn and deleteBtn:FindFirstChild("coins_cost", true) or deleteCostLabel

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
	MachineInteractionState.SetRelocating(false)
	if editOptions then
		editOptions.Enabled = false
		editOptions.Adornee = nil
		debug.log("machine", "state", "editoptions_close", {})
	end
	if deleteCostLabel and deleteCostLabel:IsA("TextLabel") then
		deleteCostLabel.Text = "--"
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
			updateDeleteCostLabel(currentSelected)
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
			updateDeleteCostLabel(machine)
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

	if MachineInteractionState.IsRelocating() then
		local sourceId = getMachineId(currentSelected)
		local targetId = getMachineId(machine)
		debug.log("merge", "decision", "client_merge_attempt", {
			sourceMachineId = sourceId,
			targetMachineId = targetId,
		})

		local gridx, gridz = resolveGrid(machine)
		if typeof(gridx) == "number" and typeof(gridz) == "number" then
			machineIntentEvent:FireServer({
				intent = "select",
				gridx = gridx,
				gridz = gridz,
			})
		end

		clearHover()
		return
	end

	setSelected(machine)
	clearHover()
	sendSelect(machine)
end

local function onInput(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		clearSelected()
		clearHover()
		MachineInteractionState.SetActive(false)
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		if PlacementModeState.IsActive() then
			return
		end
		if currentSelected then
			handleRotate()
		end
	end
end

	local function maybeRefreshDeleteCost(now)
		if not currentSelected or not deleteCostLabel or not deleteCostLabel:IsA("TextLabel") then
			return
		end
		if now - lastDeletePriceUpdate < 0.25 then
			return
		end
		lastDeletePriceUpdate = now
		updateDeleteCostLabel(currentSelected)
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

		maybeRefreshDeleteCost(os.clock())
	end

mouse.Button1Down:Connect(onClick)
UserInputService.InputBegan:Connect(onInput)
RunService.RenderStepped:Connect(step)
connectEditOptions()

local machineDeleteResultEvent = remotes:FindFirstChild("machine_delete_result") or remotes:WaitForChild("machine_delete_result", 5)
	if machineDeleteResultEvent then
		machineDeleteResultEvent.OnClientEvent:Connect(function(payload)
			if not payload then
				return
			end
			if payload.success then
				if payload.machineType and payload.tier then
					Inventory.Add(payload.machineType, payload.tier, 1)
					PlayerUI.SetTierAmount(payload.tier, Inventory.GetCount(payload.machineType, payload.tier))
					updateDeleteCostLabel(currentSelected)
					if deleteCostLabel and deleteCostLabel:IsA("TextLabel") and payload.price then
						deleteCostLabel.Text = formatCompact(payload.price) .. " C$"
					end
				end
			else
				local Notifier = require(script.Parent.notifier)
				Notifier.Insufficient()
			end
	end)
end

if not characterConn then
	characterConn = player.CharacterAdded:Connect(function()
		clearHover()
		clearSelected()
		if editOptions then
			editOptions.Enabled = false
			editOptions.Adornee = nil
		end
		MachineInteractionState.SetActive(false)
		MachineInteractionState.SetRelocating(false)
		-- refresh UI references because PlayerGui descendants can reset on spawn
		local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
		if pg then
			playerGui = pg
			editOptions = playerGui:FindFirstChild("editoptions") or playerGui:WaitForChild("editoptions", 5)
			editOptionsConnected = false
			deleteCostLabel = nil
			connectEditOptions()
		end
	end)
end

local function refreshDeleteCost()
	if currentSelected then
		updateDeleteCostLabel(currentSelected)
	end
end

player:GetAttributeChangedSignal("Cash"):Connect(refreshDeleteCost)
player:GetAttributeChangedSignal("CashPerSecond"):Connect(refreshDeleteCost)
machinesFolder.ChildAdded:Connect(refreshDeleteCost)
machinesFolder.ChildRemoved:Connect(refreshDeleteCost)

--[[ Command Bar single-use test (client):
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local machines = workspace:WaitForChild("machines")
local first = machines:FindFirstChildWhichIsA("Model")
if first then
    local ui = playerGui:WaitForChild("editoptions")
    ui.Enabled = true
    ui.Adornee = first.PrimaryPart or first:FindFirstChildWhichIsA("BasePart", true)
    print("Select the machine, click move, pick a tile, and confirm. Verify occupancy and model pivot moved.")
end
]]

return MachineInteraction
