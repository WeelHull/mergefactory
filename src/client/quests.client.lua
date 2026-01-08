local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)
local Notifier = require(script.Parent.notifier)
local PurchasePrompt = require(script.Parent.purchase_prompt)
local PlayerUI = require(script.Parent.playerui_controller)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local updateEvent = remotes:WaitForChild("quest_update")
local requestFn = remotes:WaitForChild("quest_request")

local sync

local refs = {
	playerGui = nil,
	playerUI = nil,
	questFrame = nil,
	scroll = nil,
	template = nil,
	questButton = nil,
	closeButton = nil,
}

local claimConnections = {}
local menuConnections = {}

local function clearConnections(bucket)
	for _, conn in ipairs(bucket) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(bucket)
end

local function failureMessage(reason)
	if reason == "not_complete" then
		return "Quest not complete yet."
	elseif reason == "not_active" then
		return "Quest already updated, refreshing..."
	elseif reason == "unknown_quest" then
		return "Quest is no longer available."
	end
	return tostring(reason or "Claim failed")
end

local function ensureRefs()
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	if not refs.playerGui or not refs.playerGui.Parent then
		refs.playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	end
	if not refs.playerGui then
		return false
	end

	if not refs.playerUI or not refs.playerUI.Parent then
		refs.playerUI = refs.playerGui:FindFirstChild("PlayerUI") or refs.playerGui:WaitForChild("PlayerUI", 5)
	end
	if not refs.playerUI then
		return false
	end

	refs.questFrame = refs.questFrame or refs.playerUI:FindFirstChild("quest_frame")
	refs.scroll = refs.scroll or (refs.questFrame and refs.questFrame:FindFirstChild("scrolling_frame"))
	refs.template = refs.template or (refs.scroll and refs.scroll:FindFirstChild("quest"))
	refs.questButton = refs.questButton or PlayerUI.GetQuestButton()
	refs.closeButton = refs.closeButton or PlayerUI.GetQuestCloseButton()

	return refs.questFrame ~= nil and refs.scroll ~= nil and refs.template ~= nil
end

local function clearRenderedQuests()
	if not ensureRefs() then
		return
	end
	clearConnections(claimConnections)
	for _, child in ipairs(refs.scroll:GetChildren()) do
		if child ~= refs.template and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	if refs.template then
		refs.template.Visible = false
	end
end

local function setLabel(parent, name, text)
	if not parent then
		return
	end
	local obj = parent:FindFirstChild(name, true)
	if obj and obj:IsA("TextLabel") then
		obj.Text = text or ""
	end
end

local function bindClaim(frame, questId, enabled)
	local button = frame and frame:FindFirstChild("claim_button", true)
	if not button or not button.Activated then
		return
	end
	button.Active = enabled and true or false
	button.AutoButtonColor = enabled and true or false
	button.Selectable = enabled and true or false
	button.Visible = true
	if enabled then
		local conn = button.Activated:Connect(function()
			if questId then
				local ok, result = pcall(function()
					return requestFn:InvokeServer({ action = "claim", questId = questId })
				end)
				if not ok or not result or result.success ~= true then
					local reason = failureMessage(result and result.reason)
					Notifier.Warn(reason)
					if result and result.reason == "not_active" then
						sync()
					end
					return
				end
				if result.message then
					Notifier.Show(result.message, 3)
				else
					Notifier.Show("Quest claimed!", 2)
				end
			end
		end)
		table.insert(claimConnections, conn)
	end
end

local function renderQuests(quests)
	if not ensureRefs() then
		debugutil.log("ui", "warn", "quest_ui_missing", {})
		return
	end

	clearRenderedQuests()

	if type(quests) ~= "table" or #quests == 0 then
		local frame = refs.template:Clone()
		frame.Name = "quest_empty"
		frame.Visible = true
		setLabel(frame, "title", "No missions available")
		setLabel(frame, "info", "Come back later for more quests.")
		setLabel(frame, "requirement", "")
		setLabel(frame, "reward", "")
		local btn = frame:FindFirstChild("claim_button", true)
		if btn then
			btn.Visible = false
		end
		frame.Parent = refs.scroll
		return
	end

	for index, quest in ipairs(quests) do
		local frame = refs.template:Clone()
		frame.Name = quest.id or ("quest_" .. tostring(index))
		frame.Visible = true

		setLabel(frame, "title", quest.title or "Quest")
		setLabel(frame, "info", quest.description or "")
		setLabel(frame, "requirement", quest.requirement or "")
		setLabel(frame, "reward", quest.rewardText or "")

		local claimable = quest.claimable == true
		local claimButton = frame:FindFirstChild("claim_button", true)
		if claimButton and claimButton:IsA("GuiButton") then
			claimButton.Active = claimable
			claimButton.AutoButtonColor = claimable
			claimButton.Selectable = claimable
			claimButton.Text = claimable and "Claim" or "In Progress"
			claimButton.Visible = quest.terminal ~= true
		end

		bindClaim(frame, quest.id, claimable)
		frame.Parent = refs.scroll
	end
end

function sync()
	if not ensureRefs() then
		task.delay(2, sync)
		return
	end
	local ok, result = pcall(function()
		return requestFn:InvokeServer({ action = "sync" })
	end)
	if not ok or not result or result.success ~= true then
		debugutil.log("quest", "warn", "quest_sync_failed", { ok = ok, result = result })
		task.delay(2, sync)
		return
	end
	if result.quests then
		renderQuests(result.quests)
	end
end

updateEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.quests then
		renderQuests(payload.quests)
	end
	if payload.message then
		Notifier.Show(payload.message, 3)
	end
end)

local function hookMenuButtons()
	if not ensureRefs() then
		return
	end
	clearConnections(menuConnections)
	if refs.questButton then
		table.insert(
			menuConnections,
			refs.questButton.Activated:Connect(function()
				PurchasePrompt.Hide("quest_toggle")
				PlayerUI.ToggleQuestMenu()
			end)
		)
	end
	if refs.closeButton then
		table.insert(
			menuConnections,
			refs.closeButton.Activated:Connect(function()
				PurchasePrompt.Hide("quest_toggle_close")
				PlayerUI.ToggleQuestMenu()
			end)
		)
	end
	if not refs.questButton or not refs.closeButton then
		task.delay(2, hookMenuButtons)
	end
end

task.defer(function()
	ensureRefs()
	PlayerUI.HideQuestMenu()
	hookMenuButtons()
	sync()
end)
