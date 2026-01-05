local ReplicatedStorage = game:GetService("ReplicatedStorage")
local debugutil = require(ReplicatedStorage.Shared.debugutil)

local PlacementMode = {}

local active = false
local enterCallback
local cancelCallback
local rotateCallback

function PlacementMode.IsActive()
	return active
end

function PlacementMode.SetActive(value, reason)
	if active == value then
		return
	end
	active = value
	debugutil.log("placement", "state", value and "enter" or "exit", {
		state = value and "active" or "inactive",
		reason = reason or "unspecified",
	})
end

function PlacementMode.SetEnterCallback(fn)
	enterCallback = fn
end

function PlacementMode.SetCancelCallback(fn)
	cancelCallback = fn
end

function PlacementMode.SetRotateCallback(fn)
	rotateCallback = fn
end

function PlacementMode.RequestEnter(payload)
	if typeof(enterCallback) == "function" then
		enterCallback(payload)
		return true
	end
	return false
end

function PlacementMode.RequestCancel(payload)
	if typeof(cancelCallback) == "function" then
		cancelCallback(payload)
		return true
	end
	return false
end

function PlacementMode.RequestRotate(delta)
	if typeof(rotateCallback) == "function" then
		return rotateCallback(delta or 90)
	end
	return false
end

return PlacementMode
