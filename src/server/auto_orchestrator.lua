-- auto_orchestrator: coordinates auto tiles / buy / merge to pick the cheapest next action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local debugutil = require(ServerScriptService.Server.debugutil)
local Economy = require(ServerScriptService.Server.economy)
local AutoTiles = require(ServerScriptService.Server.auto_tiles)
local AutoBuy = require(ServerScriptService.Server.auto_buy)
local AutoMerge = require(ServerScriptService.Server.auto_merge)

local remotes = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("remotes")

local toggleFn = remotes:FindFirstChild("auto_flags") or Instance.new("RemoteFunction")
toggleFn.Name = "auto_flags"
toggleFn.Parent = remotes

local AutoOrchestrator = {}

-- state[player] = { tiles=true/false, buy=bool, merge=bool, running=bool }
local stateByPlayer = {}

local function getState(player)
	if not player then
		return nil
	end
	stateByPlayer[player] = stateByPlayer[player] or {
		tiles = false,
		buy = false,
		merge = false,
		running = false,
	}
	return stateByPlayer[player]
end

local function pickAction(player, st)
	local cash = Economy.GetCash(player)
	local candidates = {}

	if st.tiles then
		local price = AutoTiles.NextPrice(player)
		if price and price > 0 then
			table.insert(candidates, { kind = "tiles", price = price })
		end
	end
	if st.buy then
		local price = AutoBuy.NextPrice(player)
		if price and price > 0 then
			table.insert(candidates, { kind = "buy", price = price })
		end
	end
	if st.merge then
		local price = AutoMerge.NextPrice(player)
		if price and price > 0 then
			table.insert(candidates, { kind = "merge", price = price })
		end
	end

	table.sort(candidates, function(a, b)
		return a.price < b.price
	end)

	for _, cand in ipairs(candidates) do
		if cash >= cand.price then
			return cand.kind, cand.price
		end
	end
	return nil, nil
end

local function runLoop(player)
	local st = getState(player)
	if not st or st.running then
		return
	end
	st.running = true
	while player.Parent do
		if not (st.tiles or st.buy or st.merge) then
			break
		end
		local kind = nil
		kind = select(1, pickAction(player, st))
		if not kind then
			task.wait(1)
		else
			if kind == "tiles" then
				AutoTiles.UnlockOne(player)
			elseif kind == "buy" then
				AutoBuy.PlaceOne(player)
			elseif kind == "merge" then
				AutoMerge.MergeOne(player)
			end
			task.wait(0.35)
		end
	end
	st.running = false
end

local function setFlag(player, payload)
	local st = getState(player)
	if not st then
		return { success = false, reason = "no_state" }
	end
	if payload.tiles ~= nil then
		st.tiles = payload.tiles == true
	end
	if payload.buy ~= nil then
		st.buy = payload.buy == true
	end
	if payload.merge ~= nil then
		st.merge = payload.merge == true
	end
	if st.tiles or st.buy or st.merge then
		task.spawn(runLoop, player)
	end
	return { success = true, state = { tiles = st.tiles, buy = st.buy, merge = st.merge } }
end

toggleFn.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" then
		return { success = false, reason = "invalid_payload" }
	end
	return setFlag(player, payload)
end

function AutoOrchestrator.Init()
	debugutil.log("auto", "init", "auto_orchestrator ready", {})
end

return AutoOrchestrator
