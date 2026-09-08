--!strict

----------------------------------------------------------------------
-- DashApi
----------------------------------------------------------------------
-- The client-side seam between whoever owns the dash and whoever asks
-- for one. `DashManager` owns a `DashController` that is rebuilt on
-- every respawn; `DashButtonGui` needs to trigger a dash without
-- reaching into that private state and without caring which character
-- is current.
--
-- This replaces `_G.BrainFighter.requestDash`. A `_G` slot is not a
-- contract: nothing types it, nothing finds it, and a typo reads back
-- `nil` at the call site with no way to tell "not registered yet" from
-- "misspelled". A ModuleScript under `StarterPlayerScripts.Client` is
-- the same one-liner with a name the type checker can see.
--
-- Registration order does not matter. The provider is looked up when a
-- dash is requested, not when this module is required, so a UI script
-- that loads before `DashManager` still works on the first tap.
----------------------------------------------------------------------

local DashApi = {}

type Provider = () -> ()

local provider: Provider? = nil

-- Called by `DashManager`. Pass `nil` to withdraw (there is no dashable
-- character right now); requests then report unavailable rather than
-- silently doing nothing.
function DashApi.setProvider(fn: Provider?)
	provider = fn
end

-- Returns false when nothing has registered — the caller decides whether
-- that is worth logging.
function DashApi.requestDash(): boolean
	local fn = provider
	if not fn then
		return false
	end
	fn()
	return true
end

function DashApi.isAvailable(): boolean
	return provider ~= nil
end

return DashApi
