local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local machinesFolder = Workspace:WaitForChild("machines")
local islandsFolder = Workspace:FindFirstChild("islands")

local COLOR_ON = Color3.fromRGB(79, 234, 110)
local COLOR_OFF = Color3.fromRGB(255, 106, 106)
local COLOR_EMPTY = Color3.fromRGB(180, 180, 180)

local refs = {
	toggleFrame = nil,
	toggleButton = nil,
	toggleLabel = nil,
	menu = nil,
	scrolling = nil,
	playerFrames = {},
}

local hiddenByUser = {} -- userId -> true
local initialized = false
local toggleConnected = {}
local slotConnected = {}
local hiddenIslands = {} -- islandid -> true

local function findUI()
	if refs.menu and refs.menu.Parent then
		return true
	end

	local ui = playerGui:FindFirstChild("PlayerUI") or playerGui:WaitForChild("PlayerUI", 5)
	if not ui then
		return false
	end
	local settings = ui:FindFirstChild("settings_frame") or ui:WaitForChild("settings_frame", 5)
	if not settings then
		return false
	end

	local toggleFrame = settings:FindFirstChild("hide_generators_frame") or settings:WaitForChild("hide_generators_frame", 5)
	if not toggleFrame then
		return false
	end
	local toggleButton = toggleFrame:FindFirstChild("view_button") or toggleFrame:WaitForChild("view_button", 5)
	local toggleLabel = toggleFrame:FindFirstChild("label") or toggleFrame:FindFirstChildWhichIsA("TextLabel", false)
	local menu = settings:FindFirstChild("hide_generators_menu") or settings:WaitForChild("hide_generators_menu", 5)
	local scrolling = menu and (menu:FindFirstChild("scrolling_frame") or menu:WaitForChild("scrolling_frame", 5))
	if not toggleButton or not toggleLabel or not menu or not scrolling then
		return false
	end

	refs.toggleFrame = toggleFrame
	refs.toggleButton = toggleButton
	refs.toggleLabel = toggleLabel
	refs.menu = menu
	refs.scrolling = scrolling

	refs.playerFrames = {}
	for i = 1, 8 do
		local frame = scrolling:FindFirstChild("player_" .. tostring(i))
		if frame then
			local viewButton = frame:FindFirstChild("view_button", true)
			local avatar = frame:FindFirstChildWhichIsA("ImageLabel", true)
			local label = frame:FindFirstChildWhichIsA("TextLabel", true)
			refs.playerFrames[i] = {
				frame = frame,
				button = viewButton,
				avatar = avatar,
				label = label,
			}
		end
	end

	return true
end

local function setButtonState(button, text, color, enabled)
	if not button then
		return
	end
	button.Text = text
	button.BackgroundColor3 = color
	button.AutoButtonColor = enabled
	button.Active = enabled
end

local function applyHiddenForUser(userId, hidden)
	if typeof(userId) ~= "number" then
		return
	end
	if hidden then
		hiddenByUser[userId] = true
	else
		hiddenByUser[userId] = nil
	end
	for _, model in ipairs(machinesFolder:GetChildren()) do
		if model:IsA("Model") then
			local ownerAttr = model:GetAttribute("ownerUserId")
			if ownerAttr == userId then
				model:SetAttribute("HiddenForLocal", hidden == true)
			end
		end
	end

	-- Hide that user's island if known.
	if islandsFolder then
		for _, island in ipairs(islandsFolder:GetChildren()) do
			if island:GetAttribute("ownerUserId") == userId then
				island:SetAttribute("HiddenForLocal", hidden == true)
				if hidden then
					hiddenIslands[island:GetAttribute("islandid")] = true
				else
					hiddenIslands[island:GetAttribute("islandid")] = nil
				end
			end
		end
	end
end

machinesFolder.ChildAdded:Connect(function(child)
	if not child:IsA("Model") then
		return
	end
	local ownerAttr = child:GetAttribute("ownerUserId")
	if ownerAttr and hiddenByUser[ownerAttr] then
		child:SetAttribute("HiddenForLocal", true)
	end
end)

local function faceUrl(userId)
	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
end

local function refreshList()
	if not findUI() then
		return
	end

	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)

	local islandByPlayer = {}
	for _, plr in ipairs(players) do
		local islandid = plr:GetAttribute("islandid")
		if typeof(islandid) == "number" then
			islandByPlayer[plr] = islandid
		end
	end

	for i = 1, 8 do
		local slot = refs.playerFrames[i]
		if slot then
			local target = players[i]
			if not target then
				setButtonState(slot.button, "Empty", COLOR_EMPTY, false)
				slot.userId = nil
				if slot.avatar then
					slot.avatar.Image = ""
				end
				if slot.label then
					slot.label.Text = ""
				end
			else
				slot.userId = target.UserId
				if slot.label then
					slot.label.Text = target.DisplayName or target.Name
				end
				if slot.avatar then
					slot.avatar.Image = faceUrl(target.UserId)
				end
				if target == player then
					setButtonState(slot.button, "Locked", COLOR_OFF, false)
				else
						local hidden = hiddenByUser[target.UserId] == true
						setButtonState(slot.button, hidden and "Hidden" or "On", hidden and COLOR_OFF or COLOR_ON, true)
						if slot.button and not slotConnected[slot.button] then
							slotConnected[slot.button] = true
							slot.button.MouseButton1Click:Connect(function()
								if not slot.userId then
									return
								end
								local currentlyHidden = hiddenByUser[slot.userId] == true
							local newHidden = not currentlyHidden
							applyHiddenForUser(slot.userId, newHidden)
							setButtonState(slot.button, newHidden and "Hidden" or "On", newHidden and COLOR_OFF or COLOR_ON, true)
						end)
					end
				end
			end
		end
	 end
end

local function bind()
	if not findUI() then
		return
	end

	refs.menu.Visible = false
	refs.toggleButton.BackgroundColor3 = COLOR_ON
	if refs.toggleLabel then
		refs.toggleLabel.Text = "Hide Generators"
	end

	if not toggleConnected[refs.toggleButton] then
		toggleConnected[refs.toggleButton] = true
		refs.toggleButton.MouseButton1Click:Connect(function()
			if not findUI() then
				return
			end
			local newVisible = not refs.menu.Visible
			refs.menu.Visible = newVisible
			if newVisible then
				refs.toggleButton.BackgroundColor3 = COLOR_OFF
				if refs.toggleLabel then
					refs.toggleLabel.Text = "Close"
				end
			else
				refs.toggleButton.BackgroundColor3 = COLOR_ON
				if refs.toggleLabel then
					refs.toggleLabel.Text = "Hide Generators"
				end
			end
		end)
	end

	refreshList()
	initialized = true
end

player:GetAttributeChangedSignal("islandid"):Connect(refreshList)
Players.PlayerAdded:Connect(function()
	task.defer(refreshList)
end)
Players.PlayerRemoving:Connect(function(plr)
	hiddenByUser[plr.UserId] = nil
	task.defer(refreshList)
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "PlayerUI" then
		task.defer(bind)
	end
end)

machinesFolder.ChildAdded:Connect(function(child)
	local ownerAttr = child:GetAttribute("ownerUserId")
	if ownerAttr and hiddenByUser[ownerAttr] then
		child:SetAttribute("HiddenForLocal", true)
	end
end)

if not initialized then
	bind()
end
