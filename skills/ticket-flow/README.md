# ticket-flow

A minimal, spec-driven workflow for taking a **Jira ticket → a reviewed branch ready to merge** with Claude Code, tuned for a Gradle codebase. Four skills, one per phase, each producing an artifact the next phase reads.

`.dev/` below is local scratch — git-excluded on first use, never committed.

```
Jira ticket
   │
   ▼  /ticket-plan     → .dev/plans/<KEY>.md      design + tasks + test strategy, NO code
   │                      └─ plan gate: subagent challenges the plan before any code
   ▼  /ticket-build    → ONE branch per ticket, ONE commit per task, green after each
   │                      └─ stops for your approval after every task before committing
   │        ▲
   │        │ fix mode: works either set of findings, fills the Resolution ledger
   ▼        │
      /ticket-review   → .dev/reviews/<KEY>.md    subagent review: plan + criteria + diff ONLY
   │                      └─ hands back a branch whose blockers all have a Resolution
   │
   ▼  you open the merge request — humans review it on GitLab
   │
   ▼  /ticket-feedback  → .dev/mr-comments/<KEY>.md   numbered proposals: one per comment,
                            with its analysis, its fix, and why — you pick which to apply
                            └─ the numbers you pick go back to /ticket-build (fix mode)
```

## The ideas that make it work

1. **Artifacts are the coordination mechanism, and they stay on your machine.** Phases hand off via durable files, not "now continue" — so a fresh session can pick up mid-workflow by reading them. `.dev/` is **never committed**: `/ticket-plan` adds it to the repo's `.git/info/exclude` on first use, which is itself an uncommitted file, so your planning notes and the review bot's findings leave no trace in the team's repo and the MR diff contains only code. The tradeoff is honest and deliberate: continuity spans sessions on this clone, not across machines.

2. **Adversarial passes are context-restricted, and there are two of them.** The plan gate (inside `/ticket-plan`) and the code review (`/ticket-review`) both run as subagents that see only the artifacts — never the reasoning that produced them. The plan gate exists because a design flaw caught before code costs a paragraph; caught after, a rewrite.

3. **The fix loop is explicit, and both reviewers feed it.** `/ticket-review` writes findings with IDs and empty `Resolution:` lines; `/ticket-feedback` writes the human MR comments in the same shape (`H1`, `H2`, …). `/ticket-build` in fix mode works either set and fills the ledger (`fixed <sha>` / `waived — <reason>` / `escalated — <question, owner>`). Before you open the merge request, `/ticket-review` and `/ticket-feedback` both tell you mechanically whether every blocker's ledger line is filled — a check you can run, not a promise you have to take.

4. **Reviewer comments are proposals to triage, not instructions to execute.** `/ticket-feedback` fetches the MR threads, checks each against the code *as it is now* (comments are anchored to an old sha and the branch has moved), and classifies before proposing: a question wants an answer, not a patch; a design objection changes the plan, not one call site; and a reviewer who is simply wrong gets a drafted reply and no code change. Everything is numbered so you apply one at a time — and nothing is posted back to GitLab, because replying to your colleagues is your action, not a bot's.

5. **One branch per ticket, one commit per task — and one approval per task.** Task granularity lives in commit history (bisectable, reviewable commit-by-commit in GitLab), not in a pile of micro-branches. `ticket-build` never chains tasks or commits automatically: it implements one task, gets it green, presents the change, and stops for your explicit approval before committing and moving on (the same gate applies per finding in fix mode). Say "just finish the rest" to let it run unattended. If a ticket feels like it needs per-task branches, split the ticket in Jira instead.

The persona labels ("architect", "tester") are deliberately absent: what carries the weight is explicit criteria and "don't do the next phase yet" boundaries, not role names.

## Install

```bash
# project-local
cp -r ticket-plan ticket-build ticket-review ticket-feedback .claude/skills/

# or global (available in every repo)
cp -r ticket-plan ticket-build ticket-review ticket-feedback ~/.claude/skills/
```

Invoke by intent in Claude Code: "plan PROJ-123", "implement PROJ-123", "review PROJ-123", "fix the review findings", "read the MR comments". Opening the merge request itself is yours — the flow deliberately stops at a reviewed branch. They use the Atlassian and GitLab connectors you already have configured; `/ticket-feedback` falls back to `glab`, then the REST API with `$GITLAB_TOKEN`, then asking you to paste the threads — self-hosted GitLab is the case that usually needs the fallback.

## Human gates (deliberate)

- `/ticket-plan` interrogates the ticket for gaps (scope edges, unhappy paths, non-functionals, dependencies...) and runs a **clarification gate**: all open questions go to you in one batched round before any design. No assumption is made without your answer or your explicit "you decide", and every resolution is recorded in the plan's Clarifications section. The same rule carries into `/ticket-build`: mid-build ambiguity stops and asks, it never guesses.
- `/ticket-build` works one task at a time: it implements a task, runs it green, presents the change, and stops for your explicit approval before committing and starting the next — no commit lands without your go-ahead. The same per-item gate applies in fix mode. Tell it to "just finish the rest" to opt into unattended execution.
- `/ticket-feedback` stops after presenting the numbered proposals. It never applies one, not even a one-line one, and never posts a reply or resolves a thread on GitLab — it drafts replies for you to send.
- Waiving a blocking finding requires the user's explicit decision and is recorded with its reason in the ledger, for you to quote verbatim in the MR description — human reviewers must see what was consciously skipped.
- Opening the merge request, merging it, and marking the ticket Done are all yours. No skill here touches GitLab or Jira state; acceptance is always human.

## Where to bend it

- **Small tickets** (one-line fix): skip straight to `/ticket-build` with an inline plan and skip the plan gate. Ceremony should match risk.
- **Share the artifacts instead of keeping them local:** if your team wants the plan and review in the repo as living documentation — or you hand tickets between machines — drop the `.git/info/exclude` entry and commit the files explicitly. Accept that review findings then show up in the MR diff, which surprises human reviewers unless the team expects it.
- **Jenkins as source of truth:** the "green" checks name local Gradle commands; repoint them at the pipeline if that's your gate.
- **Automate the hand-off:** the flow stops at a reviewed branch on purpose. If you want the merge request scripted, `glab mr create --fill` seeded from the plan's summary and the ledger's waived findings is the natural place to start — and a smart-commit transition if your team uses them.

## Validate it before trusting it

- **Seeded-defect test** (one afternoon): plant three flaws in a real branch — a missed acceptance criterion, a swallowed exception, a test asserting nothing. Review once in the implementing conversation, once via the context-restricted subagent. If the subagent doesn't catch more, drop the restriction.
- **Plan-gate yield**: over 4-5 tickets, count gate findings that would otherwise have required code changes. Zero across five tickets → your tickets are simple enough to skip the gate.
- **The number that matters**: blocking comments from *human* MR reviewers per ticket, before vs after adopting the flow.
