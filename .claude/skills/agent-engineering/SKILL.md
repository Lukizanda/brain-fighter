---
name: agent-engineering
description: Seven engineering disciplines for building systems that survive production, not just demos — system design, tool/contract design, retrieval, reliability, security, observability, and product thinking. Loads when architecting multi-component systems, designing APIs or RemoteEvents, integrating external services, adding safety/validation, or planning anything non-trivial.
---

# Agent Engineering — 7 Production Disciplines

Distilled playbook for engineering systems that actually work outside a demo. Named after AI-agent work because that's where these disciplines became inescapable, but they apply to any non-trivial system — a Roblox server/client architecture qualifies.

The recipe is the prompt. Being the chef is the engineering. Don't write the recipe; be the chef.

## 1. System design

You're not building one thing — you're building an orchestra. Pieces that need to coordinate, fail gracefully, and not step on each other.

Ask:
- How does data flow through the system?
- What happens when one component fails? Does it cascade?
- Which components are stateful vs stateless? Where does authority live?
- Are the boundaries between components clean, or leaking implementation details?

Red flags: tight coupling between layers; "god" modules that know too much; state mutating in multiple places; no clear single-ownership for shared resources.

## 2. Tool & contract design

Every integration point — function signature, RemoteEvent payload, MCP tool, API endpoint — is a contract. Vague contracts get filled in by imagination (the LLM's, the caller's, the future you's). Imagination is not what you want processing financial transactions.

Ask:
- Does every input have an enforced type + shape + constraint?
- What's the required vs optional distinction?
- Are examples included so the contract is unambiguous?
- What happens when an input violates the contract — silent accept, soft warn, hard reject?

Red flags: parameters typed as `any` / `table` / `string` with no structure; missing required-field enforcement; accepting unknown fields silently; outputs that vary shape based on success/failure without a tagged discriminator.

## 3. Retrieval engineering

For RAG systems specifically: the quality of what you retrieve determines the ceiling of the agent's performance. Garbage context → confidently wrong answers. Applies by analogy anywhere you're injecting external data into a decision (cache reads, DB queries, config lookups).

Ask:
- How is content chunked? Too big → details diluted; too small → context lost.
- Does the embedding model actually group "similar concepts" the way the domain defines similarity?
- Is there a re-ranking pass for relevance, or are you trusting cosine-similarity top-k?

Red flags: hallucinated citations; answers that contradict the provided context; retrieval hits but downstream behavior ignores them.

## 4. Reliability engineering

APIs fail. Networks time out. External services go down. Your system must assume this, not hope against it.

Ask:
- Every external call: does it have a **timeout** so it can't hang forever?
- **Retry with backoff** — are you hammering a failing service, or easing up?
- **Fallback paths** when Plan A fails (cached value, default response, graceful degradation)?
- **Circuit breakers** — does one failing dependency take down the whole system?

Red flags: infinite waits; unbounded retries; no plan-B path; single dependency whose failure cascades.

## 5. Security & safety

Your system is an attack surface. People will manipulate it — via prompt injection, malformed input, replay attacks, authority confusion, whatever shape the surface offers.

Ask:
- **Input validation** — is user/client input parsed against an expected shape before it does anything consequential?
- **Output filtering** — can the system emit something it shouldn't (PII, secrets, policy violations)?
- **Permission boundaries** — does the agent/tool only have the capability it actually needs, or does it have admin-level access "just in case"?
- For client/server: is the client ever trusted for anything consequential without server validation?

Red flags: accepting client-asserted state as ground truth (user IDs, damage values, cooldowns); tools with write access broader than the feature needs; no sanitization between user input and downstream systems.

## 6. Evaluation & observability

You cannot improve what you cannot measure. "Seems better" is not a deployment criterion. Vibes don't scale; metrics do.

Ask:
- **Tracing** — when something breaks, can you reconstruct the full timeline? Which tool was called with what, what did retrieval return, what was the reasoning?
- **Test cases** — is there a known-good-answer set you can regression-test against?
- **Metrics** — success rate, latency, cost per task; are they tracked, or just felt?
- **Automated catches** — do regressions get detected before shipping, or after users complain?

Red flags: debugging by re-running and eyeballing; no structured logs; no way to diff behavior across versions; tests that check "does it compile" instead of "does it work".

## 7. Product thinking

Your system exists to serve humans. Humans have expectations. Unpredictable systems need UX specifically designed for their unpredictability.

Ask:
- Does the system communicate **confidence vs uncertainty**? Can the user tell when it's guessing?
- Does the user understand what it **can and can't do**, or are they building wrong mental models?
- When things go wrong, is the handling **graceful** — error messages that help, escalation paths that work — or cryptic?
- When should it **ask for clarification** vs proceed with a best guess?
- How is **trust** built over time? Is first-run a pit of failure or a scaffolded success?

Red flags: errors that only make sense to the engineer who wrote them; no UI distinction between "high confidence" and "guessing"; no path to recover when the system loops; tone/affordances that don't match the actual reliability.

## Quick self-audit (two moves that usually pay off)

1. **Tighten a schema.** Pick the vaguest contract in your system and add types, required fields, a real example. Highest-leverage fix most systems need.
2. **Trace one failure.** Next bug that bites you: don't tweak the prompt/code. Trace backward. Nine times out of ten the root cause isn't the words — it's the system.

## When loading this skill

Apply the relevant disciplines to the task at hand. Not every task needs all seven:

| Task type | Primary disciplines |
|---|---|
| New remote/API contract | 2 (Tool), 5 (Security), 6 (Observability) |
| Client/server split | 1 (System), 5 (Security), 4 (Reliability) |
| Adding external integration | 4 (Reliability), 5 (Security), 6 (Observability) |
| Authoring tests | 6 (Evaluation) |
| User-facing feature | 7 (Product), 6 (Observability) |
| Refactor across components | 1 (System), 2 (Contract), 6 (Observability) |

Call out which principles you're prioritizing and why — "I'm leaning on #4 here because the hit detection depends on RemoteEvent delivery, and we need a fallback if packets drop" — rather than applying all seven as a generic checklist.
