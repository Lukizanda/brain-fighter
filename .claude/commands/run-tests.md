---
description: Run an in-Studio test suite via the test-runner subagent (default suite "NPC")
argument-hint: [suite-name]
---

Use the `test-runner` subagent (Task tool, `subagent_type: "test-runner"`) to run the test suite matching the argument `$ARGUMENTS`. If no argument was given, default to `NPC`. If the argument is `all`, run every suite.

Follow the subagent's standard flow: set `workspace:GetAttribute("RunTests")` to the suite name via MCP, start a playtest, poll output for `[AUTORUN DONE]`, stop playtest, clear the attribute, and report results.

Run the subagent in the background so I can continue working — notify me with the summary when it's done.
