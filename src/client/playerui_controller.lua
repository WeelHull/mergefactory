local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)

local PlayerUI = {}

local refs = {
	playerUI = nil,
	menuButtons = nil,
	buildFrame = nil,
	buildButton = nil,
	closeButton = nil,
	rotationOption = nil,
	rotationButton = nil,
}

local warnedMissing = false

local function ensureRefs()
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if not playerGui then
		if not warnedMissing then
			warnedMissing = true
			debugutil.log("ui", "warn", "playergui_missing", {})
		end
		return false
	end

	if not refs.playerUI or not refs.playerUI.Parent then
		local playerUI = playerGui:FindFirstChild("PlayerUI") or playerGui:WaitForChild("PlayerUI", 5)
		if not playerUI then
			if not warnedMissing then
				warnedMissing = true
				debugutil.log("ui", "warn", "playerui_missing", {})
			end
			return false
		end
		refs.playerUI = playerUI
	end

	if refs.playerUI then
		refs.menuButtons = refs.menuButtons or refs.playerUI:FindFirstChild("menu_buttons")
		refs.buildFrame = refs.buildFrame or refs.playerUI:FindFirstChild("build_frame")
		refs.buildButton = refs.buildButton or (refs.menuButtons and refs.menuButtons:FindFirstChild("build_button") or nil)
		local machineMenu = refs.buildFrame and refs.buildFrame:FindFirstChild("machine_menu") or nil
		refs.closeButton = refs.closeButton or (machineMenu and machineMenu:FindFirstChild("close") or nil)
		if not refs.rotationOption then
			refs.rotationOption = refs.playerUI:FindFirstChild("rotation_option", true) or refs.playerUI:FindFirstChild("rotate_button", true)
		end
		if not refs.rotationOption then
			refs.rotationOption = playerGui:FindFirstChild("rotation_option", true) or playerGui:FindFirstChild("rotate_button", true)
		end
		if refs.rotationOption and not refs.rotationButton then
			if refs.rotationOption:IsA("ImageButton") or refs.rotationOption:IsA("TextButton") then
				refs.rotationButton = refs.rotationOption
			else
				refs.rotationButton = refs.rotationOption:FindFirstChildWhichIsA("ImageButton", true) or refs.rotationOption:FindFirstChildWhichIsA("TextButton", true)
			end
		end
	end

	return true
end

function PlayerUI.IsReady()
	return ensureRefs()
end

function PlayerUI.GetBuildButton()
	ensureRefs()
	return refs.buildButton
end

function PlayerUI.GetCloseButton()
	ensureRefs()
	return refs.closeButton
end

function PlayerUI.IsBuildMenuVisible()
	ensureRefs()
	return refs.buildFrame and refs.buildFrame.Visible or false
end

function PlayerUI.ShowRotationOption()
	if not ensureRefs() then
		return
	end
	if refs.rotationOption then
		if refs.rotationOption:IsA("BillboardGui") or refs.rotationOption:IsA("ScreenGui") then
			refs.rotationOption.Enabled = true
		elseif typeof(refs.rotationOption.Visible) == "boolean" then
			refs.rotationOption.Visible = true
		end
	end
	if refs.rotationButton and typeof(refs.rotationButton.Visible) == "boolean" then
		refs.rotationButton.Visible = true
	end
end

function PlayerUI.HideRotationOption()
	if not ensureRefs() then
		return
	end
	if refs.rotationOption then
		if refs.rotationOption:IsA("BillboardGui") or refs.rotationOption:IsA("ScreenGui") then
			refs.rotationOption.Enabled = false
		elseif typeof(refs.rotationOption.Visible) == "boolean" then
			refs.rotationOption.Visible = false
		end
	end
	if refs.rotationButton and typeof(refs.rotationButton.Visible) == "boolean" then
		refs.rotationButton.Visible = false
	end
end

function PlayerUI.SetRotationAdornee(part)
	if not ensureRefs() then
		return
	end
	if refs.rotationOption and refs.rotationOption:IsA("BillboardGui") then
		refs.rotationOption.Adornee = part
		if part and part:IsA("BasePart") then
			refs.rotationOption.StudsOffset = Vector3.new()
			refs.rotationOption.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y * 0.5 + 3, 0)
		end
	end
end

function PlayerUI.GetRotationButton()
	ensureRefs()
	return refs.rotationButton
end

function PlayerUI.ShowBuildMenu()
	if not ensureRefs() then
		return
	end
	if refs.menuButtons then
		refs.menuButtons.Visible = false
	end
	if refs.buildFrame then
		refs.buildFrame.Visible = true
	end
end

function PlayerUI.ShowMenuButtons()
	if not ensureRefs() then
		return
	end
	if refs.menuButtons then
		refs.menuButtons.Visible = true
	end
	if refs.buildFrame then
		refs.buildFrame.Visible = false
	end
end

return PlayerUI
