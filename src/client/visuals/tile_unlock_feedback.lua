-- Plays a brief visual pulse when a tile is unlocked.
-- Visual-only, client-only: brightens color slightly and applies a tiny size pop, then restores.
-- Safe to call multiple times; per-tile cooldown prevents spam. Silently no-ops on invalid tiles.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local debugutil = require(ReplicatedStorage.Shared.debugutil)

local cooldown = {}
local COOLDOWN_SEC = 0.5
local BRIGHTEN_FACTOR = 0.25
local SIZE_POP = 1.02

local function gatherParts(tile)
	if not tile or (not tile:IsA("BasePart") and not tile:IsA("Model")) then
		return nil
	end
	if tile:IsA("BasePart") then
		return { tile }
	end

	local parts = {}
	for _, inst in ipairs(tile:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	if #parts == 0 then
		return nil
	end
	return parts
end

local function playTweens(parts)
	local upTweens = {}
	local downTweens = {}
	for _, part in ipairs(parts) do
		if part and part.Parent then
			local origColor = part.Color
			local targetColor = origColor:Lerp(Color3.new(1, 1, 1), BRIGHTEN_FACTOR)
			local origSize = part.Size
			local targetSize = origSize * SIZE_POP

			upTweens[#upTweens + 1] = TweenService:Create(
				part,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = targetColor, Size = targetSize }
			)
			downTweens[#downTweens + 1] = TweenService:Create(
				part,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Color = origColor, Size = origSize }
			)
		end
	end

	for _, t in ipairs(upTweens) do
		t:Play()
	end
	for _, t in ipairs(upTweens) do
		t.Completed:Wait()
	end
	for _, t in ipairs(downTweens) do
		t:Play()
	end
end

local function play(tile)
	if not tile then
		return
	end
	local now = os.clock()
	if cooldown[tile] and now - cooldown[tile] < COOLDOWN_SEC then
		return
	end

	local parts = gatherParts(tile)
	if not parts then
		return
	end

	cooldown[tile] = now

	task.spawn(function()
		playTweens(parts)
		local gx = tile:GetAttribute("gridx")
		local gz = tile:GetAttribute("gridz")
		debugutil.log("visual", "state", "unlock_feedback_played", {
			gridx = gx or "unknown",
			gridz = gz or "unknown",
		})
	end)
end

return {
	play = play,
}
