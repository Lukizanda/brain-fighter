# Committing and keeping the wiki current

## Before you propose a commit
1. Run `git diff HEAD`, not just `git diff --cached`. Concurrent sessions can leave stale staged changes behind.
2. Run `graphify update .` (AST only, no API cost).
3. Audit the wiki (below). Your global CLAUDE.md says when the wiki gets updated; this page covers how.

## Committing
- Use `mcp__nimbalyst__developer_git_commit_proposal`, not CLI `git commit`. CLI git is fine for status, log, diff, branch and push.
- For renames, list both sides in `filesToStage`: the old path as deleted and the new path as modified.
- Run `git push` right after every commit. You don't need to ask first.

## Wiki audit
1. Grep `wiki/` for renamed symbols and retired concepts.
2. Update the affected system, concept and design pages, and bump their `updated:` frontmatter.
3. Append an ingest entry to `wiki/log.md`.
4. If a phase was added or changed, record it in `wiki/design/build-plan.md`. Plans under `nimbalyst-local/` are invisible to other sessions.

Don't rewrite history. Old `log.md` entries and decision rationales keep their original terms. The operations contract is in [wiki/WIKI.md](../../wiki/WIKI.md).
