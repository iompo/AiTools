# ticket-flow

A minimal, spec-driven workflow for taking a **Jira ticket → GitLab merge request** with Claude Code, tuned for a Gradle codebase. Four skills, one per phase, each producing an artifact the next phase reads.

```
Jira ticket
   │
   ▼  /ticket-plan     → .dev/plans/<KEY>.md      design + tasks + test strategy, NO code
   │                      └─ plan gate: subagent challenges the plan before any code
   ▼  /ticket-build    → ONE branch per ticket, ONE commit per task, green after each
   │                      └─ stops for your approval after every task before committing
   │        ▲
   │        │ fix mode: works the review findings, fills the Resolution ledger
   ▼        │
      /ticket-review   → .dev/reviews/<KEY>.md    subagent review: plan + criteria + diff ONLY
   │
   ▼  /ticket-mr       → GitLab MR, Jira-linked   precondition: every blocker has a Resolution
                          stops at the human approval gate
```

## The ideas that make it work

1. **Artifacts are the coordination mechanism.** Phases hand off via durable files, not "now continue". The plan and review files are **committed on the feature branch** (plan is the branch's first commit), so any session on any machine can pick up mid-workflow. At MR time you choose once per project whether `.dev/` stays in the repo or gets dropped in a final commit.

2. **Adversarial passes are context-restricted, and there are two of them.** The plan gate (inside `/ticket-plan`) and the code review (`/ticket-review`) both run as subagents that see only the artifacts — never the reasoning that produced them. The plan gate exists because a design flaw caught before code costs a paragraph; caught after, a rewrite.

3. **The fix loop is explicit.** `/ticket-review` writes findings with IDs and empty `Resolution:` lines. `/ticket-build` in fix mode works those findings and fills the ledger (`fixed <sha>` / `waived — <reason>`). `/ticket-mr` refuses to open until every blocker's ledger line is filled — a mechanical check, not a promise.

4. **One branch per ticket, one commit per task — and one approval per task.** Task granularity lives in commit history (bisectable, reviewable commit-by-commit in GitLab), not in a pile of micro-branches. `ticket-build` never chains tasks or commits automatically: it implements one task, gets it green, presents the change, and stops for your explicit approval before committing and moving on (the same gate applies per finding in fix mode). Say "just finish the rest" to let it run unattended. If a ticket feels like it needs per-task branches, split the ticket in Jira instead.

The persona labels ("architect", "tester") are deliberately absent: what carries the weight is explicit criteria and "don't do the next phase yet" boundaries, not role names.

## Install

```bash
# project-local
cp -r ticket-plan ticket-build ticket-review ticket-mr .claude/skills/

# or global (available in every repo)
cp -r ticket-plan ticket-build ticket-review ticket-mr ~/.claude/skills/
```

Invoke by intent in Claude Code: "plan PROJ-123", "implement PROJ-123", "review PROJ-123", "fix the review findings", "open the MR". They use the Atlassian and GitLab connectors you already have configured.

## Human gates (deliberate)

- `/ticket-plan` interrogates the ticket for gaps (scope edges, unhappy paths, non-functionals, dependencies...) and runs a **clarification gate**: all open questions go to you in one batched round before any design. No assumption is made without your answer or your explicit "you decide", and every resolution is recorded in the plan's Clarifications section. The same rule carries into `/ticket-build`: mid-build ambiguity stops and asks, it never guesses.
- `/ticket-build` works one task at a time: it implements a task, runs it green, presents the change, and stops for your explicit approval before committing and starting the next — no commit lands without your go-ahead. The same per-item gate applies in fix mode. Tell it to "just finish the rest" to opt into unattended execution.
- Waiving a blocking finding requires the user's explicit decision, recorded with a reason, and is surfaced verbatim in the MR description.
- `/ticket-mr` never merges and never marks the ticket Done. Acceptance is always human.

## Where to bend it

- **Small tickets** (one-line fix): skip straight to `/ticket-build` with an inline plan and skip the plan gate. Ceremony should match risk.
- **Jenkins as source of truth:** the "green" checks name local Gradle commands; repoint them at the pipeline if that's your gate.
- **Auto-transition Jira status:** off by default; add a smart-commit transition in `/ticket-mr` if your team uses them.

## Validate it before trusting it

- **Seeded-defect test** (one afternoon): plant three flaws in a real branch — a missed acceptance criterion, a swallowed exception, a test asserting nothing. Review once in the implementing conversation, once via the context-restricted subagent. If the subagent doesn't catch more, drop the restriction.
- **Plan-gate yield**: over 4-5 tickets, count gate findings that would otherwise have required code changes. Zero across five tickets → your tickets are simple enough to skip the gate.
- **The number that matters**: blocking comments from *human* MR reviewers per ticket, before vs after adopting the flow.
