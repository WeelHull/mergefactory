local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer
local machinesFolder = Workspace:WaitForChild("machines")
local islandsFolder = Workspace:FindFirstChild("islands")

local DEFAULT_NEAR = 90
local DEFAULT_FAR = 250
local nearDistance = DEFAULT_NEAR
local farDistance = DEFAULT_FAR

local originalTransparency = {} -- BasePart -> original LTM

local function setModelVisible(model, visible)
	if not model then
		return
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if visible then
				if originalTransparency[descendant] ~= nil then
					descendant.LocalTransparencyModifier = originalTransparency[descendant]
				else
					descendant.LocalTransparencyModifier = 0
				end
			else
				if originalTransparency[descendant] == nil then
					originalTransparency[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			end
		end
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = visible and 0 or 1
		end
	end
end

machinesFolder.ChildRemoved:Connect(function(child)
	for part in pairs(originalTransparency) do
		if part:IsDescendantOf(child) then
			originalTransparency[part] = nil
		end
	end
end)

local function onRadiusChanged()
	local near = LOCAL_PLAYER:GetAttribute("MachineLODNear")
	local far = LOCAL_PLAYER:GetAttribute("MachineLODFar")
	if typeof(near) == "number" and near > 0 then
		nearDistance = near
	else
		nearDistance = DEFAULT_NEAR
	end
	if typeof(far) == "number" and far > 0 then
		farDistance = math.max(far, nearDistance + 10)
	else
		farDistance = DEFAULT_FAR
	end
end

LOCAL_PLAYER:SetAttribute("MachineLODNear", nearDistance)
LOCAL_PLAYER:SetAttribute("MachineLODFar", farDistance)
LOCAL_PLAYER:GetAttributeChangedSignal("MachineLODNear"):Connect(onRadiusChanged)
LOCAL_PLAYER:GetAttributeChangedSignal("MachineLODFar"):Connect(onRadiusChanged)
onRadiusChanged()

RunService.Heartbeat:Connect(function()
    local character = LOCAL_PLAYER.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        -- Character not ready; keep models visible to avoid flicker.
        for _, model in ipairs(machinesFolder:GetChildren()) do
            if model:IsA("Model") and model.PrimaryPart then
                setModelVisible(model, true)
            end
        end
        return
    end
    for _, model in ipairs(machinesFolder:GetChildren()) do
        if model:IsA("Model") and model.PrimaryPart then
            if model:GetAttribute("HiddenForLocal") == true then
                setModelVisible(model, false)
                continue
            end
            local dist = (model.PrimaryPart.Position - root.Position).Magnitude
            if dist <= nearDistance then
                setModelVisible(model, true)
            elseif dist <= farDistance then
                setModelVisible(model, false)
            else
                setModelVisible(model, false)
            end
        end
    end
end)
