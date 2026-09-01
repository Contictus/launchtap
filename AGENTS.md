# AGENTS.md

> **Single source of truth.** All agent instructions live in this file.
> `CLAUDE.md` imports this file via `@AGENTS.md`, so the two are always in sync.
> Make changes **only in this file**.

## Project

- **Name:** launchpad
- **Purpose:** a pons (`pons.family`)-style fixed-supply token launchpad. Bonding
  curve → graduation → locked liquidity. EVM chain (Robinhood Chain).
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

## Sync rule

- `AGENTS.md` = the only file that holds content.
- `CLAUDE.md` contains only the `@AGENTS.md` line; it holds no content of its own.
- To add/change an instruction: edit **only `AGENTS.md`**. Do not touch `CLAUDE.md`.
