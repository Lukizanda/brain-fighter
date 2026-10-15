# Studio MCP, playtests and tests

## Debugging loop
- Add `Logger` output and run a playtest **before** you fix anything. Only fix once the logs show the root cause.
- Log state transitions immediately. Throttle per-frame data with `log:infoThrottled(key, seconds, msg)`.
- Cap playtest iterations at **2 per session**. After that, stop and take a diagnosis to the user.
- `start_stop_play` sometimes wedges. If you already have a running playtest, use it, and design your checks up front.

## Playtest lock
Several sessions can try to playtest at once. Acquire the lock before `start_stop_play` and **always** release it afterwards, including after errors. A lock older than 10 minutes is stale. The lock file is `nimbalyst-local/playtest.lock.json` (gitignored).

Acquire:
```powershell
$lockPath = "nimbalyst-local\playtest.lock.json"
$existing = if (Test-Path $lockPath) { Get-Content $lockPath -Raw | ConvertFrom-Json } else { $null }
if ($existing -and ((Get-Date) - [DateTime]$existing.startedAt).TotalMinutes -lt 10) {
    throw "Playtest locked by '$($existing.session)' since $($existing.startedAt) — wait or check if that session is done."
}
New-Item -ItemType Directory -Path "nimbalyst-local" -Force | Out-Null
@{ session = "YOUR_SESSION_NAME"; startedAt = (Get-Date -Format o) } | ConvertTo-Json | Set-Content $lockPath
```
Release:
```powershell
Remove-Item "nimbalyst-local\playtest.lock.json" -ErrorAction SilentlyContinue
```
If acquiring throws, don't start the playtest. Report the conflict to the user.

## Test suites
- Run a suite with `workspace:SetAttribute("RunTests", "<suite>")`. The suites live in `src/shared/Tests/Suites/`.
- When the suite prints `[AUTORUN DONE]`, **immediately** run `workspace:SetAttribute("RunTests", nil)` without asking. The attribute persists in the `.rbxl` and would re-run the suite on every later playtest.
- `TestResult_*` and `TestRunSummary` clear on their own when play stops.

## DataModel mutations through `execute_luau`
Wrap any create, destroy, reparent or rename in a waypoint so the user can undo the whole operation with one Ctrl+Z. Read-only inspection doesn't need one.
```lua
local ok, recording = pcall(function() return ChangeHistoryService:TryBeginRecording("label") end)
-- do the work
if recording then ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
```
- Before you destroy a Part that WeldConstraints point to, re-wire `Part0`/`Part1` to its replacement. Otherwise the welds silently go nil.
- Injected Luau gets its own copies of modules. Drive gameplay through attributes, and observe it through `DescendantAdded`.
- Instances that MCP clones arrive as `nil` when passed as RemoteEvent arguments. Use a real `.server.luau` dev harness instead.
- Details, `datamodel_type`, simulated input and the `start_stop_play` wedge: [wiki/reference/studio-mcp.md](../../wiki/reference/studio-mcp.md).
