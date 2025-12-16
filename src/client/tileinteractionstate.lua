local ReplicatedStorage = game:GetService("ReplicatedStorage")
local debugutil = require(ReplicatedStorage.Shared.debugutil)

local TileInteractionState = {}

local currentState = "Idle"
local currentHoveredTile = nil
local currentPendingTile = nil

local allowed = {
	Idle = { Hovering = true, Idle = true },
	Hovering = { Pending = true, Idle = true, Hovering = true },
	Pending = { Confirmed = true, Idle = true, Pending = true },
	Confirmed = { Idle = true, Confirmed = true },
}

local function logTransition(fromState, toState, reason)
	if fromState == toState then
		return
	end
	debugutil.log("interaction", "state", "transition", {
		from = fromState,
		to = toState,
		reason = reason or "unspecified",
	})
end

local function checkInvariants()
	if currentState == "Idle" then
		if currentHoveredTile ~= nil or currentPendingTile ~= nil then
			debugutil.log("interaction", "error", "invariant broken", { state = currentState, reason = "idle_has_references" })
		end
	elseif currentState == "Hovering" then
		if currentHoveredTile == nil or currentPendingTile ~= nil then
			debugutil.log("interaction", "error", "invariant broken", { state = currentState, reason = "hover_refs_invalid" })
		end
	elseif currentState == "Pending" then
		if currentPendingTile == nil or currentHoveredTile ~= nil then
			debugutil.log("interaction", "error", "invariant broken", { state = currentState, reason = "pending_refs_invalid" })
		end
	elseif currentState == "Confirmed" then
		if currentHoveredTile ~= nil or currentPendingTile ~= nil then
			debugutil.log("interaction", "error", "invariant broken", { state = currentState, reason = "confirmed_has_refs" })
		end
	end
end

function TileInteractionState.SetState(state, reason)
	local prev = currentState
	if prev ~= state and not (allowed[prev] and allowed[prev][state]) then
		debugutil.log("interaction", "warn", "illegal state transition", {
			from = prev,
			to = state,
			reason = reason,
		})
		return
	end
	currentState = state
	logTransition(prev, state, reason)
	checkInvariants()
end

function TileInteractionState.GetState()
	return currentState
end

function TileInteractionState.SetHoveredTile(tile)
	currentHoveredTile = tile
	if tile and currentPendingTile then
		debugutil.log("interaction", "warn", "input blocked", { reason = "pending_active_hover_set" })
	end
end

function TileInteractionState.ClearHoveredTile()
	currentHoveredTile = nil
end

function TileInteractionState.GetHoveredTile()
	return currentHoveredTile
end

function TileInteractionState.IsBlocked()
	return currentState == "Blocked"
end

function TileInteractionState.SetPendingTile(tile)
	currentPendingTile = tile
	if tile and currentState ~= "Pending" and currentState ~= "Hovering" then
		debugutil.log("interaction", "warn", "input blocked", { reason = "pending_set_wrong_state" })
	end
end

function TileInteractionState.ClearPendingTile()
	currentPendingTile = nil
end

function TileInteractionState.GetPendingTile()
	return currentPendingTile
end

return TileInteractionState
