# Plan 5 Task 1 Audit Pack

This directory is the Task 1 baseline and audit-policy pack for Plan 5. It is documentation
only. The implementation under review is immutable commit
`6184bc5febd43de99ab6cc2b6f71f7f90c878bb6`; the Plan 5 plan, threat model, and this pack do not
move that target.

| Artifact | Purpose |
| --- | --- |
| [00-baseline-provenance.md](00-baseline-provenance.md) | Baseline identity, submodules, generated inputs, toolchain pins, gate commands, observed results, and caveated metrics. |
| [01-surface-ownership.md](01-surface-ownership.md) | Primary audit ownership for every first-party runtime and release surface, with explicit shared boundaries. |
| [02-audit-harness.md](02-audit-harness.md) | Clean-machine prerequisites, reproducible command sequence, host requirements, skip conditions, and expected evidence. |
| [03-policy-and-finding-template.md](03-policy-and-finding-template.md) | Reportability policy, severity/confidence rules, canonical finding schema, and state transitions. |
| [04-exclusions-and-unknowns.md](04-exclusions-and-unknowns.md) | Threat-model reconciliation, exclusions, external prerequisites, unknowns, and baseline caveats. |

Task 1 did not change product source, dependencies, generated artifacts, workflows, migrations,
runtime configuration, plans, specifications, `AGENTS.md`, `CLAUDE.md`, `notes.md`, or
`backlog.md`.
