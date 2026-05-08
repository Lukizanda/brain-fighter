----------------------------------------------------------------------
-- WorldDataService
----------------------------------------------------------------------
-- Server entry point that initializes the WorldDataManager on startup.
-- This runs before the NPC system so that NPCService can safely query
-- WorldDataManager for spawn/patrol positions.
--
-- Responsibilities:
--   - Call WorldDataManager.initialize() on server startup (takes a snapshot)
--   - Nothing else — the module does the actual work
----------------------------------------------------------------------

local WorldDataManager = require(script.Parent.WorldDataManager)

WorldDataManager.initialize()
