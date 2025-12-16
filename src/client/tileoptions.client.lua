local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local debugutil = require(ReplicatedStorage.Shared.debugutil)
local PlacementMode = require(script.Parent.placementmode_state)

local tileoptions = playerGui:WaitForChild("tileoptions")
tileoptions.Enabled = false
tileoptions.Adornee = nil

local optionsFrame = tileoptions:WaitForChild("options", 5)
local buyButton = optionsFrame and optionsFrame:FindFirstChild("buytile")

local remotes = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("remotes")
local tileunlockRemote = remotes and remotes:FindFirstChild("tileunlock")

local currentTile
local currentGridX
local currentGridZ
local hoverAPI
local clickConn
local interactionState = require(script.Parent.tileinteractionstate)
local forceClearHover

local function closeBoard(reason)
	if tileoptions then
		tileoptions.Enabled = false
		tileoptions.Adornee = nil
	end
	currentTile = nil
	currentGridX = nil
	currentGridZ = nil
	debugutil.log("tileoptions", "state", "closed", { reason = reason or "unknown" })
	if reason == "external_cancel" then
		if interactionState then
			interactionState.SetState("Idle", "external_cancel")
			interactionState.ClearHoveredTile()
		end
		if forceClearHover then
			forceClearHover()
		end
		for _, inst in ipairs(playerGui:GetDescendants()) do
			if inst:IsA("Highlight") then
				inst.Enabled = false
				inst.Adornee = nil
			end
		end
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("Highlight") and inst.Parent == workspace then
				inst.Enabled = false
				inst.Adornee = nil
			end
		end
	end
end

local function openBoard(tile, gridx, gridz)
	currentTile = tile
	currentGridX = gridx
	currentGridZ = gridz
	tileoptions.Adornee = tile:IsA("Model") and tile.PrimaryPart or tile
	tileoptions.Enabled = true
	debugutil.log("tileoptions", "state", "open", {
		tile = tile:GetFullName(),
		gridx = gridx,
		gridz = gridz,
	})
end

local api = _G._tileIntentAPI
if api then
	api.PendingSet:Connect(function(tile, gridx, gridz)
		if PlacementMode.IsActive() then
			return
		end
		if tile then
			openBoard(tile, gridx, gridz)
		end
	end)

	api.PendingCleared:Connect(function(reason)
		closeBoard(reason or "pending_cleared")
	end)

	api.Confirmed:Connect(function(tile)
		if PlacementMode.IsActive() then
			return
		end
		if tile then
			local gx = tile:GetAttribute("gridx")
			local gz = tile:GetAttribute("gridz")
			openBoard(tile, gx, gz)
		end
	end)
end

function forceClearHover()
	if not hoverAPI then
		hoverAPI = _G._tileHoverAPI
	end
	if hoverAPI and hoverAPI.ForceClearHover then
		hoverAPI.ForceClearHover()
	end
end

if buyButton and buyButton:IsA("GuiButton") then
	buyButton.Activated:Connect(function()
		if not currentTile then
			debugutil.log("tileoptions", "warn", "buy clicked without tile")
			return
		end
		local gx = currentGridX or currentTile:GetAttribute("gridx")
		local gz = currentGridZ or currentTile:GetAttribute("gridz")
		debugutil.log("tileoptions", "decision", "buy pressed", { gridx = gx, gridz = gz, tile = currentTile:GetFullName() })
		local freshApi = _G._tileIntentAPI
		if freshApi and freshApi.ClearPending then
			freshApi.ClearPending("buy")
		end
		forceClearHover()
		closeBoard("buy")
		if tileunlockRemote then
			tileunlockRemote:FireServer(gx, gz)
		end
		closeBoard("buy_sent")
	end)
end

if tileunlockRemote then
	tileunlockRemote.OnClientEvent:Connect(function()
		forceClearHover()
		local freshApi = _G._tileIntentAPI
		if freshApi and freshApi.ClearPending then
			freshApi.ClearPending("unlock_response")
		end
		closeBoard("unlock_response")
	end)
end

-- click-out to cancel while board open
player:GetMouse().Button1Down:Connect(function()
	if not tileoptions.Enabled then
		return
	end
	-- if click is not on the options UI, treat as cancel
	local target = player:GetMouse().Target
	if not target or (currentTile and target ~= currentTile and target.Parent ~= currentTile) then
		local api2 = _G._tileIntentAPI
		if api2 and api2.ClearPending then
			api2.ClearPending("external_cancel")
		end
		interactionState.SetState("Idle", "external_cancel")
		interactionState.ClearHoveredTile()
		closeBoard("external_cancel")
	end
end)
