----------------------------------------------------------------------
-- TestAutoRunner
----------------------------------------------------------------------
-- At playtest start, checks workspace:GetAttribute("RunTests").
-- If set to a suite name (e.g. "NPC"), requires every ModuleScript under
-- ReplicatedStorage.Shared.Tests.Suites.<name> and runs them as a suite.
-- If set to "all", runs every suite folder.
--
-- The attribute is set by the test-runner agent via edit-time execute_luau
-- before calling start_playtest. Results are logged with [TEST PASS] /
-- [TEST FAIL] / [SUITE DONE] / [AUTORUN DONE] markers for MCP parsing.
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ATTRIBUTE_NAME = "RunTests"
local STARTUP_DELAY_SECONDS = 3 -- let world + NPCs initialize
local PLAYER_WAIT_TIMEOUT = 10

local suiteAttr = Workspace:GetAttribute(ATTRIBUTE_NAME)
if type(suiteAttr) ~= "string" or suiteAttr == "" then
	return
end

local TestRunner = require(ReplicatedStorage.Shared.Tests.TestRunner)
local suitesRoot = ReplicatedStorage.Shared.Tests:FindFirstChild("Suites")
if not suitesRoot then
	warn("[AUTORUN ERROR] Suites folder not found")
	return
end

local function collectTestsInFolder(folder: Instance): { any }
	local tests = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok and type(mod) == "table" and mod.name then
				table.insert(tests, mod)
			else
				warn(string.format("[AUTORUN WARN] Skipped %s: %s",
					child.Name, ok and "not a valid test module" or tostring(mod)))
			end
		end
	end
	return tests
end

local function runSuiteFolder(suiteName: string, folder: Instance)
	local tests = collectTestsInFolder(folder)
	if #tests == 0 then
		warn(string.format("[AUTORUN WARN] Suite %s has no tests", suiteName))
		return { passed = 0, total = 0, failed = 0 }
	end
	local result = TestRunner.runSuite(suiteName, tests)
	-- Write per-test results to workspace attributes so external probes
	-- (MCP execute_luau, CI scripts) can read pass/fail without parsing
	-- console output (which truncates the tail in long playtests). Studio
	-- attribute names allow only [A-Za-z0-9_] so test names need sanitising.
	for _, r in result.results do
		local sanitisedName = r.name:gsub("[^%w]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
		local key = "TestResult_" .. suiteName .. "_" .. sanitisedName
		Workspace:SetAttribute(key, r.passed and "PASS" or ("FAIL: " .. (r.message or "")))
	end
	return result
end

task.spawn(function()
	-- Wait for a player so player-dependent tests have ctx.player
	local waitStart = os.clock()
	while #Players:GetPlayers() == 0 and os.clock() - waitStart < PLAYER_WAIT_TIMEOUT do
		task.wait(0.25)
	end

	task.wait(STARTUP_DELAY_SECONDS)

	print(string.format("[AUTORUN START] suite=%s", suiteAttr))

	local totalPassed, totalFailed, totalTests = 0, 0, 0

	if suiteAttr == "all" then
		for _, folder in suitesRoot:GetChildren() do
			if folder:IsA("Folder") then
				local result = runSuiteFolder(folder.Name, folder)
				totalPassed += result.passed
				totalFailed += result.failed
				totalTests += result.total
			end
		end
	else
		local folder = suitesRoot:FindFirstChild(suiteAttr)
		if not folder then
			warn(string.format("[AUTORUN ERROR] Suite folder not found: %s", suiteAttr))
			print("[AUTORUN DONE]")
			return
		end
		local result = runSuiteFolder(suiteAttr, folder)
		totalPassed = result.passed
		totalFailed = result.failed
		totalTests = result.total
	end

	print(string.format("[AUTORUN DONE] %d/%d passed, %d failed",
		totalPassed, totalTests, totalFailed))
	Workspace:SetAttribute("TestRunSummary", string.format("%d/%d passed, %d failed", totalPassed, totalTests, totalFailed))
end)
