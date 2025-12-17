-- machine_bootstrap: initializes machine runtime containers.

local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local machineregistry = require(ServerScriptService.Server.machineregistry)

local function actorPath()
	local a = script:FindFirstAncestorOfClass("Actor")
	return a and a:GetFullName() or "none"
end

debug.log("machine", "init", "context", {
	script = script:GetFullName(),
	actor = actorPath(),
})

local folder = machineregistry.ensureMachinesFolder()

debug.log("machine", "init", "bootstrap complete", {
	machines_folder = folder,
})
