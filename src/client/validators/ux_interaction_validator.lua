local VALIDATOR_ENABLED = true

if not VALIDATOR_ENABLED then
	return {}
end

local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local debugutil = require(ReplicatedStorage.Shared.debugutil)
local clock = os.clock
local InteractionState = require(script.Parent.Parent.tileinteractionstate)

local shadow = {
	interactionState = "Unknown",
	tileOptionsOpen = false,
	placementActive = false,
	lastInstructionPlaceholder = nil,
	placementInstructionActive = false,
}

local frame = 0
local pendingHoverClear = nil -- { deadline, trigger, satisfied }
local pendingIdleAfterCancel = nil -- { deadline, trigger, satisfied }
local pendingGapExpected = false -- true after Pending->Hovering until Idle or violation
local evaluationRequested = false
local HOVER_GRACE = 0.15
local OPTIONS_GRACE = 0.15
local CANCEL_GRACE = 0.25
local PERSIST_THRESHOLD = 2.0
local lastInteractionTransitionAt = 0
local hoverEnterGraceUntil = 0 -- absolute timestamp

local terminalPlaceholders = {
	confirm = true,
	invalid_generic = true,
	invalid_locked = true,
	unlock_success = true,
}

-- warning heuristics
local hoverEnterTimes = {} -- queue of timestamps
local instructionRecent = {} -- placeholder -> last timestamp
local lastPlacementActiveSet = nil
local lastPlacementActiveCleared = nil
local lastLogByRuleKey = {} -- dedupe identical logs for 1s
local pendingCancelHoverCheck = nil -- { deadline, trigger }
local activeTerminal = nil -- current terminal instruction name

local function currentHover()
	if InteractionState and InteractionState.GetHoveredTile then
		return InteractionState.GetHoveredTile()
	end
	return nil
end

local function snapshot()
	local hover = currentHover()
	return string.format(
		"interaction=%s hover=%s options=%s placement=%s instruction=%s",
		shadow.interactionState,
		hover and (hover:GetAttribute("gridx") and string.format("%s_%s", hover:GetAttribute("gridz"), hover:GetAttribute("gridx")) or hover.Name) or "nil",
		tostring(shadow.tileOptionsOpen),
		tostring(shadow.placementActive),
		shadow.lastInstructionPlaceholder or "nil"
	)
end

local function logViolation(rule, extra)
	local key = "err|" .. rule .. "|" .. snapshot()
	local now = clock()
	if lastLogByRuleKey[key] and (now - lastLogByRuleKey[key]) < 1.0 then
		return
	end
	lastLogByRuleKey[key] = now
	debugutil.log("validator", "error", "invariant_violation", {
		rule = rule,
		snapshot = snapshot(),
		extra = extra,
	})
end

local function logWarn(rule, extra)
	local key = "warn|" .. rule
	local now = clock()
	if lastLogByRuleKey[key] and (now - lastLogByRuleKey[key]) < 1.0 then
		return
	end
	lastLogByRuleKey[key] = now
	debugutil.log("validator", "warn", "ux_noise", {
		rule = rule,
		extra = extra,
	})
end

local function pruneHoverTimes(now)
	local cutoff = now - 0.5
	local i = 1
	while i <= #hoverEnterTimes and hoverEnterTimes[i] < cutoff do
		i += 1
	end
	if i > 1 then
		for j = i, #hoverEnterTimes do
			hoverEnterTimes[j - i + 1] = hoverEnterTimes[j]
		end
		for k = #hoverEnterTimes, #hoverEnterTimes - (i - 2), -1 do
			hoverEnterTimes[k] = nil
		end
	end
end

local function processDeadlines()
	if pendingHoverClear and frame > pendingHoverClear.deadline then
		local hover = currentHover()
		if hover == nil then
			pendingHoverClear.satisfied = true
		end
		if not pendingHoverClear.satisfied then
			logViolation("pending_idle_must_clear_hover", pendingHoverClear.trigger)
		end
		pendingHoverClear = nil
	end

	if pendingIdleAfterCancel and frame > pendingIdleAfterCancel.deadline then
		if not pendingIdleAfterCancel.satisfied then
			logViolation("tileoptions_cancel_must_idle", pendingIdleAfterCancel.trigger)
		end
		pendingIdleAfterCancel = nil
	end

	-- external_cancel hover persistence check
	if pendingCancelHoverCheck and clock() > pendingCancelHoverCheck.deadline then
		local hover = currentHover()
		debugutil.log("validator", "state", "hover_check", {
			source = "interaction",
			value = hover and hover:GetFullName() or "nil",
		})
		if shadow.interactionState == "Idle" and not shadow.tileOptionsOpen and hover ~= nil then
			logViolation("external_cancel_must_eventually_clear_hover", pendingCancelHoverCheck.trigger)
		end
		pendingCancelHoverCheck = nil
	end
end

local mismatchTimers = {
	idleHover = nil,
	optionsNotPending = nil,
	placementHover = nil,
	placementInstruction = nil,
}

local function updateTimer(name, active, trigger, grace)
	local now = clock()
	if active then
		if not mismatchTimers[name] then
			mismatchTimers[name] = { start = now, trigger = trigger }
		elseif (now - mismatchTimers[name].start) > (grace or PERSIST_THRESHOLD) then
			return true
		end
	else
		mismatchTimers[name] = nil
	end
	return false
end

local function checkInvariants(trigger)
	local now = clock()
	-- Idle must mean no hover (grace if hover just entered)
	local idleHoverActive = (shadow.interactionState == "Idle" and currentHover() ~= nil and now > hoverEnterGraceUntil)
	if updateTimer("idleHover", idleHoverActive, trigger, PERSIST_THRESHOLD) then
		logViolation("idle_requires_no_hover", trigger)
	end

	-- TileOptions implies Pending (allow settling)
	local optionsMismatch = (shadow.tileOptionsOpen and shadow.interactionState ~= "Pending")
	if updateTimer("optionsNotPending", optionsMismatch, trigger, PERSIST_THRESHOLD) then
		logViolation("tileoptions_requires_pending", trigger)
	end

	-- Placement blocks interaction hover
	local placementHoverMismatch = (shadow.placementActive and currentHover() ~= nil)
	if updateTimer("placementHover", placementHoverMismatch, trigger, PERSIST_THRESHOLD) then
		logViolation("placement_blocks_hover", trigger)
	end

	-- Placement exit clears placement_active UX
	local placementInstructionMismatch = (not shadow.placementActive and shadow.placementInstructionActive)
	if updateTimer("placementInstruction", placementInstructionMismatch, trigger, PERSIST_THRESHOLD) then
		logViolation("placement_instruction_stuck", trigger)
	end

	-- Terminal instructions handled separately; no timing requirement here
end

local function handleInstructionSet(placeholder, owner)
	shadow.lastInstructionPlaceholder = placeholder
	shadow.placementInstructionActive = (placeholder == "placement_active")
	if terminalPlaceholders[placeholder] then
		if activeTerminal and activeTerminal ~= placeholder then
			logViolation("terminal_singleton_violation", { from = activeTerminal, to = placeholder })
		end
		activeTerminal = placeholder
	else
		activeTerminal = nil
	end
	debugutil.log("validator", "state", "instruction_check", {
		active = activeTerminal or "nil",
		owner = owner or "unknown",
	})
end

local function parseKeyValues(str)
	local data = {}
	for key, value in string.gmatch(str, "(%S+)=([^%s]+)") do
		data[key] = value
	end
	return data
end

local function handleLog(system, level, message, data)
	local trigger = system .. ":" .. level .. ":" .. message

	if system == "interaction" then
		if level == "state" and message == "transition" then
				if data.to then
					shadow.interactionState = data.to
					lastInteractionTransitionAt = clock()
				end
				if data.from == "Pending" and data.to == "Idle" then
					pendingHoverClear = {
						deadline = frame + 1,
						trigger = trigger,
						satisfied = (currentHover() == nil),
					}
				pendingGapExpected = false
			elseif data.from == "Pending" and data.to == "Hovering" then
				pendingGapExpected = true
			elseif data.to == "Idle" then
				pendingGapExpected = false
			end
			elseif level == "state" then
			if message == "hover enter" then
				local tileName = data.name or data.tile or "unknown"
				local now = clock()
				hoverEnterGraceUntil = now + HOVER_GRACE
				if shadow.interactionState ~= "Hovering" and (now - lastInteractionTransitionAt) > HOVER_GRACE then
					logWarn("hover_visual_state_mismatch", trigger)
				end
				-- warning: hover spam
				table.insert(hoverEnterTimes, now)
				pruneHoverTimes(now)
				if #hoverEnterTimes > 6 then
					logWarn("hover_spam", { count = #hoverEnterTimes })
				end
			elseif message == "hover leave" or message == "hover cleared" or message == "hover force-cleared" then
				if pendingHoverClear then
					pendingHoverClear.satisfied = true
				end
			end
		end
	elseif system == "tileoptions" and level == "state" then
		if message == "open" then
			shadow.tileOptionsOpen = true
		elseif message == "closed" then
			shadow.tileOptionsOpen = false
			if data.reason == "external_cancel" then
				pendingIdleAfterCancel = {
					deadline = frame + 1,
					trigger = trigger,
					satisfied = (shadow.interactionState == "Idle"),
				}
				pendingCancelHoverCheck = {
					deadline = clock() + CANCEL_GRACE,
					trigger = trigger,
				}
			end
		end
	elseif system == "placement" and level == "state" then
		if message == "enter" then
			shadow.placementActive = true
		elseif message == "exit" then
			shadow.placementActive = false
		elseif message == "state change" and data.state then
			if data.state == "Idle" or data.state == "Cancelled" then
				shadow.placementActive = false
			else
				shadow.placementActive = true
			end
		end
	elseif system == "ux" and level == "state" then
		if message == "instruction_set" then
			-- warning: placement instruction churn
			if data.placeholder == "placement_active" then
				local now = clock()
				if lastPlacementActiveCleared and now - lastPlacementActiveCleared < 0.4 then
					logWarn("placement_instruction_churn", {})
				end
				lastPlacementActiveSet = now
			end
			-- warning: instruction flicker
			do
				local placeholder = data.placeholder
				local now = clock()
				local last = instructionRecent[placeholder]
				if placeholder and last and (now - last) < 0.25 then
					logWarn("instruction_flicker", { placeholder = placeholder })
				end
				instructionRecent[placeholder] = now
			end
			handleInstructionSet(data.placeholder, "ux")
		elseif message == "instruction_clear" then
			shadow.lastInstructionPlaceholder = nil
			shadow.placementInstructionActive = false
			activeTerminal = nil
			lastPlacementActiveCleared = clock()
		end
	end

	-- external_cancel path requires interaction reaching Idle
	if pendingIdleAfterCancel and shadow.interactionState == "Idle" then
		pendingIdleAfterCancel.satisfied = true
	end

	-- defer evaluation to allow logs to settle
	evaluationRequested = true

	-- warning: Pending -> Hovering -> Pending without Idle
	if pendingGapExpected and shadow.interactionState == "Pending" then
		logWarn("pending_reentry_without_idle", {})
		pendingGapExpected = false
	end
end

local function onMessageOut(message)
	if type(message) ~= "string" then
		return
	end

	local system, level, rest = string.match(message, "^%[(.-)%]%[(.-)%]%s*(.+)$")
	if not system or not level or not rest then
		return
	end

	local msg, kv = rest:match("^(.-)%s+|%s+(.+)$")
	if not msg then
		msg = rest
		kv = nil
	end
	msg = msg and msg:gsub("^%s+", ""):gsub("%s+$", "")

	local data = {}
	if kv then
		data = parseKeyValues(kv)
	end

	handleLog(system, level, msg, data)
end

LogService.MessageOut:Connect(onMessageOut)
RunService.Heartbeat:Connect(function()
	frame += 1
	processDeadlines()
	if evaluationRequested then
		evaluationRequested = false
		task.defer(function()
			checkInvariants("deferred")
		end)
	end
end)

debugutil.log("validator", "init", "ux_interaction_validator_ruleset", { version = 5, defer_checks = true, grace_s = HOVER_GRACE, cancel_grace_s = CANCEL_GRACE, hover_source = "interaction_only", placement_rules = "relaxed", instruction_model = "terminal_singleton" })
debugutil.log("validator", "state", "ux_interaction_validator_ready", {})

return {}
