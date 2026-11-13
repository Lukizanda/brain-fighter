--!strict

----------------------------------------------------------------------
-- ArenaEntryBoot
----------------------------------------------------------------------
-- Starts ArenaEntryService (the one-way ready-room -> island teleporter).
-- The logic lives in a ModuleScript so the test suite can drive it.
----------------------------------------------------------------------

local ServerScriptService = game:GetService("ServerScriptService")

local ArenaEntryService = require(ServerScriptService.Server.Arena.ArenaEntryService)

ArenaEntryService.enable()
game:BindToClose(ArenaEntryService.destroy)
