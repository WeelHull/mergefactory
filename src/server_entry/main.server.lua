local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local debugutil = require(game.ServerScriptService.Server.debugutil)
local islandcontroller = require(game.ServerScriptService.Server.islandcontroller)
local unlockcontroller = require(game.ServerScriptService.Server.unlockcontroller)
local PlacementPermission = require(game.ServerScriptService.Server.modules.placementpermission)
local MachineRegistry = require(game.ServerScriptService.Server.machineregistry)
local Economy = require(game.ServerScriptService.Server.economy)
local gridregistry = require(game.ServerScriptService.Server.gridregistry)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local Inventory = require(game.ServerScriptService.Server.inventory)
local Rebirth = require(game.ServerScriptService.Server.rebirth)
local QuestSystem = require(game.ServerScriptService.Server.questsystem)
local TimeCycle = require(game.ServerScriptService.Server.timecycle)
local AutoBuy = require(game.ServerScriptService.Server.auto_buy)
local AutoTiles = require(game.ServerScriptService.Server.auto_tiles)
local AutoMerge = require(game.ServerScriptService.Server.auto_merge)
local AutoOrchestrator = require(game.ServerScriptService.Server.auto_orchestrator)
require(game.ServerScriptService.Server.playerlifecycle)

local START_GRIDX = 1
local START_GRIDZ = 1
local HRP_TIMEOUT = 5
local function ensureLeaderstats(player)
	if not player then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local function ensureInt(name, initial)
		local val = ls:FindFirstChild(name)
		if not val then
			val = Instance.new("IntValue")
			val.Name = name
			val.Parent = ls
		end
		val.Value = math.floor(initial or 0)
		return val
	end

	local cashValue = ensureInt("Cash", player:GetAttribute("Cash"))
	local rebirthValue = ensureInt("Rebirths", player:GetAttribute("Rebirths"))

	player:GetAttributeChangedSignal("Cash"):Connect(function()
		cashValue.Value = math.floor(player:GetAttribute("Cash") or 0)
	end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		rebirthValue.Value = math.floor(player:GetAttribute("Rebirths") or 0)
	end)
end

-- Instant respawn
Players.RespawnTime = 0

local function findIslandSpawn(islandid)
	local islandsFolder = workspace:FindFirstChild("islands")
	if not islandsFolder then
		return nil
	end

	for _, model in ipairs(islandsFolder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("islandid") == islandid then
			return model:FindFirstChild("spawn")
		end
	end

	return nil
end

local function teleportToSpawn(player, islandid, character)
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", HRP_TIMEOUT)
	if not hrp then
		return
	end

	local spawnPart = findIslandSpawn(islandid)
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return
	end

	debugutil.log("lifecycle", "state", "character spawned", {
		userid = player.UserId,
		islandid = islandid,
	})

	hrp.CFrame = spawnPart.CFrame

	debugutil.log("lifecycle", "state", "teleported to spawn", {
		userid = player.UserId,
		islandid = islandid,
	})
end

local function ensureStartUnlocked(player)
	debugutil.log("lifecycle", "state", "player joined", {
		userid = player.UserId,
	})

	ensureLeaderstats(player)

	-- Wait for island assignment from islandcontroller
	local islandid
	while islandid == nil do
		islandid = islandcontroller.getIslandForPlayer(player)
		if islandid then
			break
		end
		task.wait()
	end

	debugutil.log("lifecycle", "state", "island ready", {
		userid = player.UserId,
		islandid = islandid,
	})

	player:SetAttribute("islandid", islandid)
	debugutil.log("lifecycle", "state", "islandid set", {
		userid = player.UserId,
		islandid = islandid,
	})

	Inventory.Reset(player.UserId)
	Inventory.Grant(player.UserId, "generator", 1, 1)

	local unlocked = unlockcontroller.unlockTile(player, START_GRIDX, START_GRIDZ)
	if unlocked then
		debugutil.log("lifecycle", "state", "start unlocked", {
			userid = player.UserId,
			islandid = islandid,
			gridx = START_GRIDX,
			gridz = START_GRIDZ,
		})
	else
		debugutil.log("lifecycle", "warn", "start unlock failed", {
			userid = player.UserId,
			islandid = islandid,
			gridx = START_GRIDX,
			gridz = START_GRIDZ,
			reason = "blocked or already unlocked",
		})
	end

	local function onCharacterAdded(character)
		teleportToSpawn(player, islandid, character)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	Economy.Start(player)
end

Players.PlayerAdded:Connect(ensureStartUnlocked)
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(ensureLeaderstats, player)
end
QuestSystem.Init()
TimeCycle.Start()
AutoBuy.Init()
AutoTiles.Init()
AutoMerge.Init()
AutoOrchestrator.Init()

-- client unlock intent handler (server-authoritative)
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local remotes = sharedFolder:WaitForChild("remotes")
local tileunlockEvent = remotes:WaitForChild("tileunlock")
local canPlaceFunction = remotes:WaitForChild("canplaceontile")
local spendCashFn = remotes:FindFirstChild("spend_cash") or Instance.new("RemoteFunction")
local rebirthFn = remotes:FindFirstChild("rebirth_request") or Instance.new("RemoteFunction")
local shopCoinsFn = remotes:FindFirstChild("shop_coins_purchase") or Instance.new("RemoteFunction")
local SHOP_TEST_ENABLED = RunService:IsStudio()
local SHOP_FREE_ACCESS = true -- set false when you wire this to paid access
local SHOP_ALLOWED_MINUTES = {
	[15] = true,
	[30] = true,
	[60] = true,
	[180] = true,
}
local SHOP_DEFAULT_MINUTES = 15
local SHOP_MAX_GRANT = 1_000_000 -- cap per request for test mode
local SHOP_COOLDOWN_SECONDS = 5
local shopCooldowns = {}
spendCashFn.Name = "spend_cash"
spendCashFn.Parent = remotes
spendCashFn.OnServerInvoke = function(player, amount)
	debugutil.log("economy", "warn", "spend_cash_remote_blocked", {
		userid = player and player.UserId,
		requested = amount,
	})
	return false
end
rebirthFn.Name = "rebirth_request"
rebirthFn.Parent = remotes
rebirthFn.OnServerInvoke = function(player, payload)
	local action = type(payload) == "table" and payload.action or "preview"
	if action == "execute" then
		return Rebirth.Perform(player)
	end
	return Rebirth.Preview(player)
end
shopCoinsFn.Name = "shop_coins_purchase"
shopCoinsFn.Parent = remotes
shopCoinsFn.OnServerInvoke = function(player, payload)
	if not SHOP_TEST_ENABLED and not SHOP_FREE_ACCESS then
		return { success = false, reason = "disabled" }
	end
	if not player then
		return { success = false, reason = "no_player" }
	end
	local now = os.clock()
	if shopCooldowns[player] and now - shopCooldowns[player] < SHOP_COOLDOWN_SECONDS then
		return { success = false, reason = "cooldown" }
	end
	shopCooldowns[player] = now
	local stamp = os.clock()
	local minutesRaw = type(payload) == "table" and tonumber(payload.minutes) or SHOP_DEFAULT_MINUTES
	local minutes = SHOP_ALLOWED_MINUTES[minutesRaw] and minutesRaw or SHOP_DEFAULT_MINUTES
	local cps = math.max(0, player:GetAttribute("CashPerSecond") or 0)
	local durationSeconds = math.max(0, math.floor(minutes * 60))
	local amount = math.max(0, math.floor(cps * durationSeconds))
	if amount > SHOP_MAX_GRANT then
		amount = SHOP_MAX_GRANT
	end
	local granted = Economy.Grant(player, amount)
	debugutil.log("shop", granted and "state" or "warn", "coins_purchase", {
		userid = player and player.UserId,
		cps = cps,
		minutes = minutes,
		amount = amount,
		granted = granted,
		stamp = stamp,
	})
	return {
		success = granted,
		amount = amount,
		stamp = stamp,
	}
end

Players.PlayerRemoving:Connect(function(player)
	shopCooldowns[player] = nil
end)

local function onTileUnlock(player, gridx, gridz)
	debugutil.log("interaction", "decision", "tile unlock intent", {
		userid = player.UserId,
		gridx = gridx,
		gridz = gridz,
	})

	local gx = tonumber(gridx)
	local gz = tonumber(gridz)
	if not gx or not gz then
		debugutil.log("interaction", "warn", "tile unlock invalid coords", {
			userid = player.UserId,
			gridx = gridx,
			gridz = gridz,
		})
		return
	end

	local tileEntry = gridregistry.getTile(player:GetAttribute("islandid"), gx, gz)
	local cps = player:GetAttribute("CashPerSecond") or 0
	local discount = player:GetAttribute("RebirthTileDiscount") or 0
	local price = EconomyConfig.GetTilePrice(gx, gz, cps, discount)
	if tileEntry and tileEntry.part then
		tileEntry.part:SetAttribute("price", price)
	end
	if price > 0 and Economy.GetCash(player) < price then
		debugutil.log("interaction", "warn", "tile unlock blocked", {
			userid = player.UserId,
			gridx = gx,
			gridz = gz,
			reason = "insufficient_funds",
			price = price,
			cash = Economy.GetCash(player),
		})
		tileunlockEvent:FireClient(player, {
			success = false,
			gridx = gx,
			gridz = gz,
			reason = "insufficient_funds",
			price = price,
		})
		return
	end

	if price > 0 then
		local spent = Economy.Spend(player, price)
		if not spent then
			debugutil.log("interaction", "warn", "tile unlock spend blocked", {
				userid = player.UserId,
				gridx = gx,
				gridz = gz,
				price = price,
				cash = Economy.GetCash(player),
			})
			tileunlockEvent:FireClient(player, {
				success = false,
				gridx = gx,
				gridz = gz,
				reason = "insufficient_funds",
				price = price,
			})
			return
		end
	end

	local success = unlockcontroller.unlockTile(player, gx, gz)
	if success then
		debugutil.log("interaction", "state", "tile unlock success", {
			userid = player.UserId,
			gridx = gx,
			gridz = gz,
		})
		tileunlockEvent:FireClient(player, {
			success = true,
			gridx = gx,
			gridz = gz,
		})
	else
		-- Unlock failed after spend: refund for safety.
		if price > 0 then
			Economy.Grant(player, price)
		end
		debugutil.log("interaction", "warn", "tile unlock blocked", {
			userid = player.UserId,
			gridx = gx,
			gridz = gz,
			reason = "blocked",
		})
		tileunlockEvent:FireClient(player, {
			success = false,
			gridx = gx,
			gridz = gz,
			reason = "blocked",
		})
	end
end

tileunlockEvent.OnServerEvent:Connect(onTileUnlock)

canPlaceFunction.OnServerInvoke = function(player, tile, ignoreMachineId)
	local allowed, reason = PlacementPermission.CanPlaceOnTile(player, tile, ignoreMachineId)
	if tile then
		local gridx = tile:GetAttribute("gridx")
		local gridz = tile:GetAttribute("gridz")
		local islandid = player:GetAttribute("islandid")
		if typeof(gridx) == "number" and typeof(gridz) == "number" and typeof(islandid) == "number" then
			local occupied, occupantId = MachineRegistry.IsTileOccupied(islandid, gridx, gridz)
			if occupied then
				if occupantId == ignoreMachineId then
					allowed = true
					reason = "self_tile"
				elseif reason ~= "merge_possible" then
					allowed = false
					reason = "tile_occupied"
				end
			end
		end
	end
	debugutil.log("placement", "decision", "canplaceontile result", {
		userid = player.UserId,
		tile = tile,
		allowed = allowed,
		reason = reason,
		ignore = ignoreMachineId,
	})
	return allowed, reason
end
