-- auto_buy: server-authoritative one-shot Tier 1 purchase + placement on button press.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debugutil = require(ServerScriptService.Server.debugutil)
local MachineSpawn = require(ServerScriptService.Server.machinespawn)
local MachineRegistry = require(ServerScriptService.Server.machineregistry)
local gridregistry = require(ServerScriptService.Server.gridregistry)
local IslandValidator = require(ServerScriptService.Server.islandvalidator)
local Economy = require(ServerScriptService.Server.economy)
local EconomyConfig = require(ReplicatedStorage.Shared.economy_config)
local Inventory = require(ServerScriptService.Server.inventory)
local QuestSystem = require(ServerScriptService.Server.questsystem)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")
local requestFn = remotes:FindFirstChild("auto_buy_request") or Instance.new("RemoteFunction")
requestFn.Name = "auto_buy_request"
requestFn.Parent = remotes

local AutoBuy = {}

local function getFreeTiles(islandid)
	if not IslandValidator.isValidIslandId(islandid) then
		return {}
	end
	local tiles = gridregistry.getUnlockedTiles(islandid)
	local checked = 0
	local free = {}
	for _, entry in ipairs(tiles) do
        if entry and entry.part then
            local gx = tonumber(entry.gridx) or tonumber(entry.part:GetAttribute("gridx"))
            local gz = tonumber(entry.gridz) or tonumber(entry.part:GetAttribute("gridz"))
            local unlockedAttr = entry.part:GetAttribute("unlocked")
            local isUnlocked = (entry.unlocked == true) or (unlockedAttr == true)
            if gx and gz and isUnlocked then
                checked += 1
                local occupied = MachineRegistry.IsTileOccupied(islandid, gx, gz)
                if not occupied then
                    entry.gridx = gx
                    entry.gridz = gz
                    table.insert(free, entry)
                end
            end
        end
    end
    if #free == 0 then
        debugutil.log("autobuy", "warn", "no_free_tiles_found", {
            islandid = islandid,
            tiles_considered = #tiles,
            unlocked_checked = checked,
            sample_gridx = tiles[1] and (tiles[1].gridx or tiles[1].part and tiles[1].part:GetAttribute("gridx")) or nil,
            sample_gridz = tiles[1] and (tiles[1].gridz or tiles[1].part and tiles[1].part:GetAttribute("gridz")) or nil,
            sample_unlocked = tiles[1] and tiles[1].unlocked or nil,
            sample_attr = (tiles[1] and tiles[1].part and tiles[1].part:GetAttribute("unlocked")) or nil,
        })
    end
    return free
end

local function ensurePaid(player, price)
	if price <= 0 then
		return true, "free"
	end
	if Economy.Spend(player, price) then
		return true, "cash"
	end
	return false, "insufficient"
end

local function handleRequest(player)
	if not player then
		return { success = false, reason = "no_player" }
	end
	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return { success = false, reason = "invalid_island" }
	end

	local freeTiles = getFreeTiles(islandid)
	if #freeTiles == 0 then
		return { success = false, reason = "no_tile" }
	end

	local placed = 0
	local spentTotal = 0
	for _, tile in ipairs(freeTiles) do
		local cps = player:GetAttribute("CashPerSecond") or 0
		local price = EconomyConfig.GetMachinePrice("generator", 1, cps)
		local cash = Economy.GetCash(player)
		if price > cash and price > 0 then
			break
		end

		local paid, source = ensurePaid(player, price)
		if not paid then
			break
		end

		local spawned = MachineSpawn.SpawnMachine({
			ownerUserId = player.UserId,
			machineType = "generator",
			tier = 1,
			gridx = tile.gridx,
			gridz = tile.gridz,
			rotation = 0,
		})

		if not spawned then
			if price > 0 then
				Economy.Grant(player, price)
			end
			debugutil.log("autobuy", "warn", "auto_buy_failed_spawn", {
					userid = player.UserId,
					price = price,
					tile = { x = tile.gridx, z = tile.gridz },
				})
			break
		end

		placed += 1
		spentTotal += math.max(0, price)
		QuestSystem.RecordMachine(player, "generator", 1)
	end

	if placed < 1 then
		return { success = false, reason = "insufficient_funds" }
	end

	debugutil.log("autobuy", "state", "auto_buy_success", {
		userid = player.UserId,
		placed = placed,
		spent = spentTotal,
	})

	return {
		success = true,
		placed = placed,
		spent = spentTotal,
	}
end

requestFn.OnServerInvoke = function(player)
	return handleRequest(player)
end

function AutoBuy.Init()
	-- No per-player state needed; RemoteFunction already wired.
end

-- Returns first free tile entry or nil.
local function getFirstFreeTile(islandid)
	local freeTiles = getFreeTiles(islandid)
	if #freeTiles == 0 then
		return nil
	end
	return freeTiles[1]
end

function AutoBuy.NextPrice(player)
	if not player then
		return nil
	end
	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return nil
	end
	local tile = getFirstFreeTile(islandid)
	if not tile then
		return nil
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	return EconomyConfig.GetMachinePrice("generator", 1, cps)
end

function AutoBuy.PlaceOne(player)
	if not player then
		return { success = false, reason = "no_player" }
	end
	local islandid = player:GetAttribute("islandid")
	if not IslandValidator.isValidIslandId(islandid) then
		return { success = false, reason = "invalid_island" }
	end
	local tile = getFirstFreeTile(islandid)
	if not tile then
		return { success = false, reason = "no_tile" }
	end
	local cps = player:GetAttribute("CashPerSecond") or 0
	local price = EconomyConfig.GetMachinePrice("generator", 1, cps)
	local cash = Economy.GetCash(player)
	if price > cash and price > 0 then
		return { success = false, reason = "insufficient_funds", price = price }
	end

	local paid = ensurePaid(player, price)
	if not paid then
		return { success = false, reason = "insufficient_funds", price = price }
	end

	local spawned = MachineSpawn.SpawnMachine({
		ownerUserId = player.UserId,
		machineType = "generator",
		tier = 1,
		gridx = tile.gridx,
		gridz = tile.gridz,
		rotation = 0,
	})
	if not spawned then
		if price > 0 then
			Economy.Grant(player, price)
		end
		return { success = false, reason = "spawn_failed", price = price }
	end

	QuestSystem.RecordMachine(player, "generator", 1)
	return { success = true, placed = 1, spent = math.max(0, price) }
end

return AutoBuy
