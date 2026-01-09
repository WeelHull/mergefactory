-- timecycle: simple day/night cycle for world lighting.

local Lighting = game:GetService("Lighting")

local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("remotes")

local TimeCycle = {}

local CYCLE_SECONDS = 600 -- real seconds for a full 24h cycle (used only in auto mode)
local DAY_START = 6
local NIGHT_START = 18
local running = false
local autoEnabled = false
local manualClock = 12
local setEvent = remotes:FindFirstChild("timecycle_set") or Instance.new("RemoteEvent")
setEvent.Name = "timecycle_set"
setEvent.Parent = remotes

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function setLighting(clockTime)
	Lighting.ClockTime = clockTime
	local isDay = clockTime >= DAY_START and clockTime < NIGHT_START

	if isDay then
		Lighting.Brightness = 2
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
		Lighting.Ambient = Color3.fromRGB(80, 80, 80)
		Lighting.EnvironmentDiffuseScale = 1
		Lighting.EnvironmentSpecularScale = 1
	else
		Lighting.Brightness = 1
		Lighting.OutdoorAmbient = Color3.fromRGB(40, 40, 60)
		Lighting.Ambient = Color3.fromRGB(20, 20, 30)
		Lighting.EnvironmentDiffuseScale = 0.6
		Lighting.EnvironmentSpecularScale = 0.6
	end

	-- Subtle dawn/dusk tint
	local dawn = DAY_START
	local dusk = NIGHT_START
	local t = 0
	if clockTime < dawn then
		t = math.clamp((clockTime + 24 - dusk) / (dawn + 24 - dusk), 0, 1)
	elseif clockTime > dusk then
		t = math.clamp((clockTime - dusk) / (dawn + 24 - dusk), 0, 1)
	else
		t = math.clamp((clockTime - dawn) / (dusk - dawn), 0, 1)
	end
	local fog = lerp(0.5, 0, t)
	Lighting.FogEnd = 1000 + fog * 500
end

function TimeCycle.Start()
	if running then
		return
	end
	-- Default to manual day.
	autoEnabled = false
	running = false
	manualClock = 12
	setLighting(manualClock)
end

function TimeCycle.SetManual(clockTime)
	autoEnabled = false
	running = false
	manualClock = math.clamp(clockTime or 12, 0, 24)
	setLighting(manualClock)
end

function TimeCycle.Stop()
	running = false
end

setEvent.OnServerEvent:Connect(function(player, payload)
	local clockTime = type(payload) == "table" and tonumber(payload.clockTime) or nil
	if not clockTime then
		return
	end
	TimeCycle.SetManual(clockTime)
end)

return TimeCycle
