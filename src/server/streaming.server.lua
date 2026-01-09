local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Enable streaming to reduce replication/physics cost for distant content (production only).
if not RunService:IsStudio() then
    Workspace.StreamingEnabled = true
    Workspace.StreamingTargetRadius = 150
    Workspace.StreamingMinRadius = 90
    Workspace.StreamingPauseMode = Enum.StreamingPauseMode.None
end
