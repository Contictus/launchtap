# AGENTS.md

> **Single source of truth.** All agent instructions live in this file.
> `CLAUDE.md` imports this file via `@AGENTS.md`, so the two are always in sync.
> Make changes **only in this file**.

## Project

- **Name:** launchpad
- **Purpose:** a pons (`pons.family`)-style fixed-supply token launchpad. Bonding
  curve → graduation → Uniswap v2 pool with the initial LP position burned.
  EVM chain (Robinhood Chain).
  Sections: Explore (Graduated + Explore lists), coin detail + trade + chart,
  Forum (Memestock), Analytics (own indexer), Docs. Non-custodial.
- **Detailed feature analysis:** `notes.md`
- **Directory:** `C:\Users\mesut\Desktop\workspace\A-projects\launchpad`

## Language

- **English everywhere:** code, comments, identifiers, docs, commit messages, PR text.

## Setup

```bash
# to be filled in
```

## Common commands

| Purpose | Command |
|---------|---------|
| Setup   | _(to be filled in)_ |
| Run     | _(to be filled in)_ |
| Test    | _(to be filled in)_ |
| Lint    | _(to be filled in)_ |
| Build   | _(to be filled in)_ |

## Code standards

- _(to be filled in)_

## Don't / watch out

- _(to be filled in)_

## Working practice — backlog & limit management

- Every unfinished piece of work is written to `backlog.md` → "Active" section
  (reason: time / limit / scope decision). Template is in the file.
- **When usage limits get close to ~90-92%:**
  1. Do not push a new or half-finished task forward under an insufficient limit.
  2. Write the current state clearly to `backlog.md`: files, exact stopping point,
     next concrete step.
  3. Tell the user: "Limit ~X%, moved the work to the backlog."
- **Note:** the usage-limit percentage cannot be read automatically. Triggers:
  the user warns you, or signs such as the context starting to be summarized.
  If the user states a percentage, act on it.
- **Backlog status must be surfaced, not just written.** Every task
  completion/review report (either agent) states backlog status explicitly:
  empty, or the open item count plus a one-line list. A non-empty backlog is
  never passed over in silence — the report must say it out loud so it stays
  prioritized instead of forgotten.

## Multi-agent workflow

Two AI agents may work this repo, in different roles, not simultaneously. This is a
default rhythm, not a rigid gate — scale it to the task.

- **Codex — builder.** Owns the whole implementation lifecycle for a task: the
  implementation plan, the code, migrations/tests/config, running test/lint/build, and
  the commits. Codex owns the repository history for implementation.
- **Claude — independent reviewer / architect / auditor.** Does not take over
  implementation and does not touch implementation history. Value is being a second,
  independent model that catches different bug classes — architecture, security, data
  consistency, concurrency, contract economics, indexer/reorg behaviour, transaction
  lifecycle, test gaps. Claude commits only its own artefacts: `docs/specs/`,
  `docs/plans/`, `notes.md`, `AGENTS.md`, `backlog.md`.
- **Human — product owner and final technical authority.**

Claude is not a manager; Codex is not a reviewer. Codex produces the solution; Claude
independently questions it.

### Per-task rhythm

1. **Claude — pre-flight review** (high-risk tasks). Critiques the task spec; does not
   write code or an implementation plan. Output:
   ```
   BLOCKERS                    - missing/contradictory requirements, decisions needed first
   RISKS                       - security, data-consistency, architecture-boundary concerns
   ACCEPTANCE CRITERIA CHANGES
   ```
   No blockers → Codex starts.
2. **Codex — implementation plan.** Short: affected files/modules, main changes, tests
   needed, migration/contract impact.
3. **Codex — implement.**
4. **Codex — verify.** Run unit/integration tests, lint/typecheck/build; check acceptance
   criteria; review `git diff` for stray changes.
5. **Codex — commit.** Output:
   ```
   Commit: <hash>
   Implemented: ...
   Verified: ...
   Known limitations: ...
   ```
6. **Claude — independent commit review.** Real engineering problems only, not style:
   incorrect behaviour, violated acceptance criteria, architecture-boundary violations,
   security, transaction/data-consistency, concurrency/race, blockchain/reorg/indexing
   edge cases, missing failure handling, insufficient tests. Severity `BLOCKER` /
   `IMPORTANT` / `MINOR`, with exact file/line where possible.
7. **Codex — triage findings.** Each: valid → fix; invalid → reject with rationale. Not
   blind obedience.
8. **Codex — re-verify + follow-up commit.**

### When Claude is in the loop

Optional for small, low-risk work (typo, rename, small DTO change) — Codex proceeds solo.

Near-mandatory on both ends for: smart contract changes, bonding-curve / fee math,
graduation logic, auth / wallet verification, database schema, indexer / reorg handling,
transaction lifecycle, concurrency, security-sensitive code, public API contract, large
refactors, critical infrastructure.

### Claude outside the task lifecycle

Milestone architecture review, threat modeling, contract/economic review, test-gap
analysis, dependency/API research, spec-consistency review, milestone acceptance review,
pre-large-refactor design review, documentation/spec update review.

## Git workflow

- **One repo, one working tree, sequential.** The two agents never run at the same time —
  no per-agent branches, no worktrees.
- **Branches:**
  - `main` — stable, verified state. Only milestone merges land here.
  - `dev` — active development. All task work (Claude docs + Codex implementation +
    review fixes) happens here as linear history.
  - `task/<slug>` — short-lived, **only** for a `high`-risk task whose change is large or
    uncertain; branched from `dev`, merged back to `dev` once its review passes. Not the
    normal path.
- **Handoff rule (the important one).** Every agent handoff happens at a commit boundary:
  1. finish work → commit → `git push`
  2. `git status` must read `nothing to commit, working tree clean`
  3. the next agent starts its turn with `git pull`

  Never hand off with uncommitted changes.
- **Review by hash.** Claude reviews a named commit or range — `review commit d4e5f6` or
  `review commits a1b2c3..e1f2g3` — and states which hash/range it reviewed.
- **Who commits what.** Codex commits implementation (code, tests, migrations, config) on
  `dev`. Claude commits `docs/`, `notes.md`, `AGENTS.md`, `backlog.md` on `dev`. Whoever
  commits, pushes.
- **Milestones.** Do not merge `dev` → `main` per task. At a milestone: open one PR
  `dev` → `main`, let CI pass, eyeball the diff, merge, optionally `git tag vX.Y.Z`.
- **Commit messages.** Conventional prefix (`feat: fix: test: chore: docs: refactor:`),
  imperative, one logical change; reference the plan task where relevant (`Plan 1 Task 6`).

### GitHub

- Public repo — origin of record + off-machine backup + CI.
- CI (`.github/workflows/backend.yml`) runs on every push to `dev` and on the milestone PR.
- `main` is branch-protected: the `backend` check must pass and the branch must be up to
  date before merge. No required human reviewer.
- PRs are used **only** for the `dev` → `main` milestone merge. The Claude↔Codex loop
  happens in `dev` via hash review, not PRs.
- No GitHub issues / project board — the plan docs are the task list.

## Sync rule

- `AGENTS.md` = the only file that holds content.
- `CLAUDE.md` contains only the `@AGENTS.md` line; it holds no content of its own.
- To add/change an instruction: edit **only `AGENTS.md`**. Do not touch `CLAUDE.md`.
