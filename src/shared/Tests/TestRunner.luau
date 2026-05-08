----------------------------------------------------------------------
-- TestRunner
----------------------------------------------------------------------
-- Runs individual tests or suites and reports pass/fail via log output.
-- Designed to be called from MCP execute_luau during a playtest.
--
-- Each test module returns a table:
--   {
--     name = "human-readable description",
--     setup = function(ctx) ... end,   -- prepare state (optional)
--     run = function(ctx) ... end,     -- perform the action (may yield)
--     verify = function(ctx) -> (bool, string?)  -- returns (pass, message)
--     teardown = function(ctx) ... end, -- cleanup (optional, always runs)
--   }
--
-- The context (ctx) is a shared table passed through all phases so tests
-- can stash intermediate state. By default it contains:
--   ctx.player     — the local player (if one exists)
--   ctx.startTime  — os.clock() when setup ran
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)
local log = Logger.new("TestRunner")

local TestRunner = {}

export type TestResult = {
	name: string,
	passed: boolean,
	message: string?,
	elapsed: number,
}

-- Run a single test module. Returns the TestResult.
-- Logs "[TEST PASS]" or "[TEST FAIL]" so external tools (MCP) can parse results.
function TestRunner.run(testModule): TestResult
	if type(testModule) ~= "table" or not testModule.name then
		local err = "Invalid test module (must have .name)"
		log:warn(err)
		return { name = "<unknown>", passed = false, message = err, elapsed = 0 }
	end

	local ctx: { [string]: any } = {
		player = Players:GetPlayers()[1],
		startTime = os.clock(),
	}

	log:info("[TEST RUN] " .. testModule.name)

	-- Pre-test isolation: ensure the player is alive and at full HP before setup
	-- runs, so accumulated damage from a previous test can't poison this one.
	if ctx.player then
		local char = ctx.player.Character or ctx.player.CharacterAdded:Wait()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = hum.MaxHealth
		end
	end

	-- Setup
	if testModule.setup then
		local ok, err = pcall(testModule.setup, ctx)
		if not ok then
			log:warn("[TEST FAIL] " .. testModule.name .. " — setup error: " .. tostring(err))
			return {
				name = testModule.name,
				passed = false,
				message = "setup error: " .. tostring(err),
				elapsed = os.clock() - ctx.startTime,
			}
		end
	end

	-- Run
	if testModule.run then
		local ok, err = pcall(testModule.run, ctx)
		if not ok then
			-- Try teardown before returning
			if testModule.teardown then
				pcall(testModule.teardown, ctx)
			end
			log:warn("[TEST FAIL] " .. testModule.name .. " — run error: " .. tostring(err))
			return {
				name = testModule.name,
				passed = false,
				message = "run error: " .. tostring(err),
				elapsed = os.clock() - ctx.startTime,
			}
		end
	end

	-- Verify
	local passed = false
	local message: string? = nil
	if testModule.verify then
		local ok, res, msg = pcall(testModule.verify, ctx)
		if not ok then
			passed = false
			message = "verify error: " .. tostring(res)
		else
			passed = res == true
			message = msg
		end
	else
		passed = true -- no verify = always pass (only useful for run-only tests)
	end

	-- Teardown (always runs, ignore errors)
	if testModule.teardown then
		pcall(testModule.teardown, ctx)
	end

	local elapsed = os.clock() - ctx.startTime
	local status = passed and "[TEST PASS]" or "[TEST FAIL]"
	local logLine = string.format("%s %s (%.2fs)%s",
		status,
		testModule.name,
		elapsed,
		message and (" — " .. message) or ""
	)
	if passed then
		log:info(logLine)
	else
		log:warn(logLine)
	end

	return { name = testModule.name, passed = passed, message = message, elapsed = elapsed }
end

-- Run a suite (list of test modules). Returns { results, total, passed, failed }.
function TestRunner.runSuite(suiteName: string, testModules: { any })
	log:info(string.format("[SUITE START] %s (%d tests)", suiteName, #testModules))

	local results: { TestResult } = {}
	local passed = 0
	local failed = 0

	for _, testModule in testModules do
		local result = TestRunner.run(testModule)
		table.insert(results, result)
		if result.passed then
			passed += 1
		else
			failed += 1
		end
	end

	log:info(string.format("[SUITE DONE] %s — %d/%d passed, %d failed",
		suiteName, passed, #testModules, failed))

	return {
		suiteName = suiteName,
		results = results,
		total = #testModules,
		passed = passed,
		failed = failed,
	}
end

return TestRunner
