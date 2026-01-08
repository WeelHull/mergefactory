-- playerlifecycle: initializes player progression safely (session-only).

local Players = game:GetService("Players")

local debug = require(script.Parent.debugutil)
debug.log("boot", "lifecycle", "loaded", { module = "playerlifecycle" })
local islandcontroller = require(script.Parent.islandcontroller)
local unlockcontroller = require(script.Parent.unlockcontroller)

debug.log("lifecycle", "init", "module ready")
debug.log("boot", "lifecycle", "init start", { module = "playerlifecycle" })

local function warn(message, data)
	debug.log("lifecycle", "warn", message, data)
end

local function decision(message, data)
	debug.log("lifecycle", "decision", message, data)
end

local function state(message, data)
	debug.log("lifecycle", "state", message, data)
end

local function ensureLeaderstats(player)
	if player:FindFirstChild("leaderstats") then
		return player.leaderstats
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	debug.log("leaderstats", "state", "leaderstats_created", {
		userid = player.UserId,
	})

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = player:GetAttribute("Cash") or 0
	cash.Parent = ls

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = player:GetAttribute("Rebirths") or 0
	rebirths.Parent = ls

	player:GetAttributeChangedSignal("Cash"):Connect(function()
		cash.Value = math.floor(player:GetAttribute("Cash") or 0)
	end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		rebirths.Value = math.floor(player:GetAttribute("Rebirths") or 0)
	end)

	return ls
end

local function ensureProgression(player)
	debug.log("boot", "lifecycle", "player added", { module = "playerlifecycle", userid = player.UserId })

	-- Always create leaderstats immediately so the player list shows values.
	ensureLeaderstats(player)

	-- Wait until an island is assigned.
	local islandid = islandcontroller.getIslandForPlayer(player)
	local tries = 0
	while islandid == nil and tries < 50 do
		task.wait(0.1)
		islandid = islandcontroller.getIslandForPlayer(player)
		tries += 1
	end

	decision("check initial state", {
		userid = player.UserId,
		islandid = islandid,
	})

	if not islandid then
		warn("no island assigned", { userid = player.UserId })
		return
	end

	state("player joined", {
		userid = player.UserId,
		islandid = islandid,
	})

	local unlocked = unlockcontroller.unlockTile(player, 1, 1)
	if unlocked then
		state("start unlocked", {
			userid = player.UserId,
			islandid = islandid,
			gridx = 1,
			gridz = 1,
		})
		else
			warn("start unlock failed", {
				userid = player.UserId,
				islandid = islandid,
				reason = "blocked or already unlocked",
			})
		end

end

Players.PlayerAdded:Connect(ensureProgression)
debug.log("boot", "lifecycle", "hook players", { module = "playerlifecycle" })
debug.log("boot", "lifecycle", "init end", { module = "playerlifecycle" })

for _, player in ipairs(Players:GetPlayers()) do
	ensureProgression(player)
end

return {}
