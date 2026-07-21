---
name: ticket-review
description: Adversarially review a ticket's implementation against its plan and acceptance criteria. Use whenever the user wants a code review, wants to check a branch or diff before opening a merge request, or asks "does this actually satisfy the ticket" — e.g. "review PROJ-123", "review this branch", "check the diff before I open the MR". This is the THIRD phase of the ticket workflow and works best run in a FRESH conversation, so the reviewer sees only the plan, the acceptance criteria, and the diff — not the reasoning that produced them.
---

# ticket-review

Review the implementation with fresh, adversarial eyes. Load only the artifacts, not the implementer's justifications, and try to find what's wrong before a human (or CI) does.

## Why fresh context matters — and how to enforce it

A reviewer that watched the code being written inherits its assumptions and waves the same things through. Don't rely on discipline: **mechanically restrict the reviewer's context**. In Claude Code, run the analysis as a subagent (Task tool) whose prompt contains only three things — the plan file contents, the acceptance criteria, and the diff — plus the checklist below. Nothing from the implementing conversation goes in. The parent conversation's only jobs are assembling those inputs and writing the subagent's findings to the review file.

Where subagents aren't available, the fallback is a genuinely new conversation. If you're being asked to review code you wrote earlier in this same conversation and can't spawn a subagent, say so plainly and do the review anyway — a biased review beats none — but mark the review file `Context: same-session (weaker)` so the human knows what they're reading.

## Inputs to load

1. The plan: `.dev/plans/<KEY>.md`.
2. The acceptance criteria: from the plan, and re-fetch the Jira ticket (`Atlassian:getJiraIssue`) in case it changed.
3. The diff: `git fetch origin` first, then `git diff origin/<default>...<branch>` — diffing against a stale local base reviews changes that aren't there and misses conflicts with what landed on main since the branch was cut. Review the diff, not the whole repo (but the subagent may open surrounding files when a hunk is unintelligible without them).

## What to check

Go through these deliberately — each is a common source of "passed review, broke in prod":

- **Acceptance criteria, one by one.** For each criterion, point to the code that satisfies it. Any criterion with no corresponding change is a blocking finding.
- **Edge cases and failure modes.** Empty/null inputs, boundary values, concurrent access, partial failure, timeouts, retries. What happens on the unhappy path?
- **Error handling and cleanup.** Are errors swallowed? Are resources (connections, files, locks) released on every path?
- **Secrets and config.** No credentials in code or ConfigMaps; secrets go through the proper mechanism. Flag any plaintext sensitive value.
- **Test quality, not just presence.** Do the tests exercise the risky paths from the plan, or just the happy path? Would they actually fail if the code regressed? Trivial assertions are worse than none because they signal false safety.
- **Consistency.** Does the code match existing conventions and the design in the plan? Undocumented deviations from the plan are findings.

## Output

Write findings to `.dev/reviews/<KEY>.md`, categorized so the user knows what must change vs what's optional:

```markdown
# <KEY> — review
Diff: origin/<default>...<branch> @ <branch HEAD sha>
Context: subagent | fresh-session | same-session (weaker)

## Blocking (must fix before MR)
- B1: <file>:<line> — <problem> — <why it matters>
  Resolution: <left empty by review; filled by ticket-build as `fixed <sha>` or `waived — <reason>`>

## Should fix
- S1: ...
  Resolution:

## Nitpick / optional
- N1: ...

## Acceptance criteria check
- [x] <criterion> — satisfied by <file>
- [ ] <criterion> — NOT addressed → also listed as a Blocking finding
```

Each finding gets an ID and an empty `Resolution:` line — that line is the ledger `ticket-build` fills in fix mode and `ticket-mr` checks as its precondition. Commit the review file on the branch so the ledger travels with the code.

## Boundaries

Do not fix the issues here — reviewing and fixing in one pass reintroduces the anchoring problem. Hand the findings to `ticket-build` (fix mode), then re-review the fix commits or proceed to `ticket-mr`. Re-reviews can be scoped to the fix commits plus any finding marked waived.
