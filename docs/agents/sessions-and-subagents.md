# Sessions and subagents

"Session" means a Nimbalyst kanban session. "Subagent" means a subagent started with the Agent/Task tool.

## Model choice
- Hand simple, well-scoped work to subagents on cheaper models: `haiku` for lookups, file sweeps and mechanical edits, and `sonnet` for small module builds.
- Keep reasoning-heavy debugging and design in the main session.

## Fan-out limits
- Never run more than **3** concurrent subagents or sessions.
- Do small module builds (under about 150 lines each) one after another. Run them in parallel only when they are large and truly independent.
- Gather context in the parent session. Never start a session just to read files and pass on a summary.

## Scope for every spawned session
- State which files it owns, what it must not touch, and its done condition.
- If it finds work outside that scope, it stops and reports. It never expands its scope on its own.

## Session phases
- `planning` covers exploration, design and plans, even after the plan is finished. `implementing` starts with code. `validating` covers testing and review.
- Set `complete` **only once the session's work is committed**. The commit is the user's approval.
