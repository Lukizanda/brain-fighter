--!strict

----------------------------------------------------------------------
-- SfxPreloader
----------------------------------------------------------------------
-- Fetches every sound in VfxConfig.SFX when the client starts.
--
-- A Sound whose asset has not been fetched yet starts late the first time
-- it plays (about 0.4 s in Studio, measured 2026-11-28). Most cues can
-- absorb that once. Two cannot, because they are timed to the picture:
-- the collect stream has its landing baked in at the moment the stream
-- arrives, and the boss's slam warning has to end as the slam lands.
--
-- Runs in its own thread and never blocks anything. A sound that fails to
-- load is logged and otherwise ignored: it will simply not play.
----------------------------------------------------------------------

local ContentProvider   = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger    = require(ReplicatedStorage.Shared.Core.Logger)
local VfxConfig = require(ReplicatedStorage.Shared.Vfx.VfxConfig)

local log = Logger.new("SfxPreloader")

task.spawn(function()
	local sounds: { Instance } = {}
	for _, value in VfxConfig.SFX :: { [string]: any } do
		-- The table also holds a few numbers (playback speed, loop volumes).
		if typeof(value) == "string" then
			local sound = Instance.new("Sound")
			sound.SoundId = value
			table.insert(sounds, sound)
		end
	end

	local failed = 0
	local started = os.clock()
	ContentProvider:PreloadAsync(sounds, function(contentId: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			failed += 1
			log:warn(string.format("%s did not load (%s)", contentId, status.Name))
		end
	end)

	log:info(string.format(
		"%d sounds fetched in %.1f s, %d failed", #sounds, os.clock() - started, failed
	))
	for _, sound in sounds do
		sound:Destroy()
	end
end)
