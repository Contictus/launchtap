# Plan 5 Task 1 — Reportability Policy and Finding Template

## Policy

Plan 5 is an evidence audit of immutable commit `6184bc5`, not a cleanup exercise. Tasks 1–7
discover and validate; they do not edit product code, dependencies, generated artifacts,
migrations, workflows, or runtime configuration. Task 8 may remediate only an independently
validated finding or a measured quality/performance case.

An audit hypothesis is not a finding. A scanner alert, dependency advisory, complexity number,
test failure, or stale-looking code becomes reportable only when the report establishes its
reachable source-to-sink or failure path, exact baseline evidence, impact, confidence, and a
reproducible proof or counterproof. A green test suite is evidence for the paths it exercises,
not proof of production safety.

### Reportable classes

- **Security or correctness:** a reachable attacker/failure path violates an explicit security
  objective, contract invariant, authorization rule, canonical-ledger rule, API contract, or
  release trust boundary.
- **Availability or resource safety:** a realistic public or operational input can exhaust a
  bounded resource, bypass a required timeout/limit, or prevent recovery, with measured or
  source-backed impact.
- **Supply chain/release:** a dependency, generated artifact, action, tool, manifest, secret path,
  or workflow can alter released behavior or expose authority without the required review/control.
- **Maintainability/quality:** a concrete defect pattern, ownership violation, duplicated rule
  with drift risk, resource leak, or measured maintenance cost exists. Style-only preferences are
  not reportable.
- **Performance:** a representative workload and environment show a material regression or a
  missed budget. The record must include sample method, median and tail/variance as appropriate,
  target, and semantic-equivalence evidence.

### Not reportable without more evidence

Speculation, scanner labels without reachability, an advisory in an unused dependency, an
unreachable test fixture, a line-count/complexity score without defect or cost, a local-only
configuration with no release path, a signer compromise that grants no new capability, and a
single noisy timing result are hypotheses or observations. Record them as such when useful, but
do not promote them to findings.

## Finding states

```text
hypothesis -> candidate -> validated finding -> assigned fix -> verified fix -> closed
                         \-> rejected/suppressed with evidence
                         \-> deferred with owner, prerequisite, and resume step
```

`candidate` requires a plausible path and exact baseline evidence. `validated finding` requires
independent reproduction or a source-backed proof, severity, confidence, and regression plan.
`rejected/suppressed` requires counterevidence and a reason. `deferred` is not “fixed later”: it
names an owner, prerequisite, risk boundary, and concrete resume step.

## Severity and confidence

Use the threat model's four severity levels. Impact and confidence are separate fields.

| Severity | Threshold |
| --- | --- |
| Critical | Practical theft/loss of contract-held assets, arbitrary mint/supply break, or unauthorized protocol-wide governance/release control. |
| High | Cross-user/cross-token authorization bypass, durable canonical corruption affecting balances/decisions, or material wallet-intent substitution. |
| Medium | Meaningful availability, confidentiality, integrity, or supply-chain weakness with realistic prerequisites but no demonstrated direct fund-loss path. |
| Low | Limited-scope hardening/correctness weakness with small impact and no credible privilege gain. |
| IMPORTANT / MINOR | Code-quality-only defect with a concrete defect, maintenance cost, or measured resource waste. Not style. |

Confidence is `high`, `medium`, or `low` and reflects evidence quality, reachability, deployment
assumptions, and reproduction. Missing production inputs reduce confidence or make a scenario
conditional; they do not automatically reduce impact.

## Canonical finding record

Every candidate and validated finding uses this schema. Empty fields must say `unknown` or `not
applicable` with a reason; they must not be omitted.

```markdown
## [ID] Short title

- State: hypothesis | candidate | validated finding | assigned fix | verified fix | closed |
  rejected/suppressed | deferred
- Severity: Critical | High | Medium | Low | IMPORTANT | MINOR
- Confidence: high | medium | low
- Primary audit task: Task 1 | Task 2 | Task 3 | Task 4 | Task 5 | Task 6 | Task 7
- Affected asset/surface: exact component, resource, and ownership-ledger row
- Baseline: 6184bc5febd43de99ab6cc2b6f71f7f90c878bb6
- Attacker/failure actor and prerequisites: public user, creator, trader, RPC/provider,
  operator, dependency, CI actor, or other; state required privilege explicitly
- Source-to-sink or failure path: ordered explanation from input/event/config to effect
- Exact evidence: `path:line` plus relevant symbol, test, command, or artifact hash
- Impact: security, correctness, availability, data integrity, user intent, or release effect
- Counterevidence and assumptions: controls that held, unreachable branches, and external unknowns
- Reproduction/proof method: exact command, fixture, input shape, invariant, or static proof
- Proposed remediation: smallest safe change; prohibited semantic changes if applicable
- Required regression test: test that fails on baseline or source-backed proof when runtime proof
  is unsafe; name expected pass condition after remediation
- Disposition/owner: fixed, rejected, accepted, deferred; owner and next step if not closed
- Related findings and cross-task references: deduplication links
```

Reports must not include real secrets or private endpoints. Use synthetic canaries and redact
credentials from command output. A finding cannot authorize a broad refactor, dependency swap,
economic change, schema change, or public API change without its normal pre-flight and
compatibility evidence.
