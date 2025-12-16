-- machine_bootstrap: initializes machine runtime containers.

local ServerScriptService = game:GetService("ServerScriptService")

local debug = require(ServerScriptService.Server.debugutil)
local machineregistry = require(ServerScriptService.Server.machineregistry)

local folder = machineregistry.ensureMachinesFolder()

debug.log("machine", "init", "bootstrap complete", {
	machines_folder = folder,
})
