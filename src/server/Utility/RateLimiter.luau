--!strict

----------------------------------------------------------------------
-- RateLimiter
----------------------------------------------------------------------
-- Per-key token bucket for throttling client→server remote traffic.
--
-- A plain "reject if now - last < interval" check is wrong for remotes:
-- network jitter routinely bunches two legitimately-spaced fires into
-- one frame, so a hard interval rejects real play. A token bucket caps
-- the *sustained* rate at exactly the client's cooldown while letting a
-- small burst through, which is the shape the jitter actually has.
--
-- Timestamps come from os.clock(), which is per-VM. That is correct
-- here — both the fill and the drain happen on the server, so nothing
-- crosses the wire. (Cross-process timing must use
-- workspace:GetServerTimeNow(); see wiki/concepts/CrossProcessTesting.)
--
-- Usage:
--   local limiter = RateLimiter.new(BURST_CAPACITY, REFILL_PER_SEC)
--   if not limiter:consume(player) then return end   -- over budget
--   limiter:forget(player)                           -- on PlayerRemoving
----------------------------------------------------------------------

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = {
	tokens: number,
	lastRefill: number,
}

export type RateLimiter = typeof(setmetatable(
	{} :: {
		_capacity: number,
		_refillPerSec: number,
		_buckets: { [any]: Bucket },
	},
	RateLimiter
))

-- `capacity` is the burst allowance (how many fires may arrive back to
-- back); `refillPerSec` is the sustained ceiling in fires per second.
function RateLimiter.new(capacity: number, refillPerSec: number): RateLimiter
	assert(capacity > 0, "RateLimiter: capacity must be positive")
	assert(refillPerSec > 0, "RateLimiter: refillPerSec must be positive")

	return setmetatable({
		_capacity = capacity,
		_refillPerSec = refillPerSec,
		_buckets = {},
	}, RateLimiter)
end

-- Spend one token for `key`. Returns true if the caller is within
-- budget, false if it should be dropped. Unknown keys start full so a
-- player's first fire is never rejected.
function RateLimiter:consume(key: any): boolean
	local now = os.clock()
	local bucket = self._buckets[key]

	if not bucket then
		bucket = { tokens = self._capacity, lastRefill = now }
		self._buckets[key] = bucket
	else
		local elapsed = now - bucket.lastRefill
		if elapsed > 0 then
			bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refillPerSec)
			bucket.lastRefill = now
		end
	end

	if bucket.tokens < 1 then
		return false
	end

	bucket.tokens -= 1
	return true
end

-- Drop a key's bucket. Call on PlayerRemoving so leavers don't leak.
function RateLimiter:forget(key: any)
	self._buckets[key] = nil
end

-- Drop every string key starting with `prefix`. Callers that use a
-- compound key (a per-player, per-reason log budget, say) can't evict a
-- leaving player with :forget alone, since they never hold the whole
-- key set. Clearing a field during traversal is defined behaviour in
-- Lua, so this is safe to run over the live table.
function RateLimiter:forgetPrefix(prefix: string)
	for key in self._buckets do
		if typeof(key) == "string" and string.sub(key, 1, #prefix) == prefix then
			self._buckets[key] = nil
		end
	end
end

function RateLimiter:destroy()
	table.clear(self._buckets)
end

return RateLimiter
