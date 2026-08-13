---
name: ticket-review
description: Adversarially review a ticket's implementation against its plan and acceptance criteria. Use whenever the user wants a code review, wants to check a branch or diff before opening a merge request, or asks "does this actually satisfy the ticket" — e.g. "review PROJ-123", "review this branch", "check the diff before I open the MR". This is the THIRD phase of the ticket workflow and works best run in a FRESH conversation, so the reviewer sees only the plan, the acceptance criteria, and the diff — not the reasoning that produced them.
---

# ticket-review

Review the implementation with fresh, adversarial eyes. Load only the artifacts, not the implementer's justifications, and try to find what's wrong before a human (or CI) does.

## Why fresh context matters — and how to enforce it

A reviewer that watched the code being written inherits its assumptions and waves the same things through. Don't rely on discipline: **mechanically restrict the reviewer's context**. In Claude Code, run the analysis as subagents (Task tool) whose prompts contain only three things — the plan file contents, the acceptance criteria, and the diff — plus the checklist below. Nothing from the implementing conversation goes in, and no hints about what you suspect: a reviewer told where to look stops looking anywhere else.

**Use two or three reviewers with distinct lenses, not one generalist.** Give each the same three inputs but a different assignment — e.g. one on the primary language/subsystem changed, one on tests and security, one on "does this actually fix the reported bug, and does the diff match the plan". This buys two things a single reviewer cannot:

- **Coverage.** Each lens reliably finds things the others miss entirely.
- **A confidence signal.** When independent reviewers converge on the same defect, that agreement is strong evidence it is real — far stronger than one reviewer asserting it.

The parent conversation's jobs are assembling the inputs, adjudicating (below), and writing the consolidated findings to the review file.

Two things keep the cost of several reviewers reasonable. **Pass artifacts by path, not by pasting**: write the diff and the raw ticket to files once and give every reviewer the paths, rather than inlining the same diff into each prompt. And give them a short **orientation block of neutral structural facts** — module layout, entry points, where the supported-platform matrix is documented — so three agents don't each re-derive the same call graph. Structural facts only: no conclusions, no suspicions, no "check X". Opinion re-anchors them and destroys the thing this phase exists for.

Where subagents aren't available, the fallback is a genuinely new conversation. If you're being asked to review code you wrote earlier in this same conversation and can't spawn a subagent, say so plainly and do the review anyway — a biased review beats none — but mark the review file `Context: same-session (weaker)` so the human knows what they're reading.

## Adjudicate before you record

Reviewer output is evidence, not verdict. Before anything goes in the review file:

- **Verify every blocking finding yourself.** A confident subagent can report intended behaviour as a defect, and a false blocking finding costs a wasted fix cycle and can push the implementer into "fixing" correct code. Reproduce the claim — run the command, read the file, check the caller — and drop or downgrade what doesn't survive.
- **Where reviewers disagree, do not just pick.** Check the disputed claim against the code, then record the finding with its actual scope and note that reviewers differed. Disagreement usually means the finding is real but conditional; the conditions are the useful part.
- **Deduplicate across reviewers**, but keep a note when several found the same thing independently — that convergence is information the human should have.

## Inputs to load

1. The plan: `.dev/plans/<KEY>.md`.
2. The acceptance criteria: from the plan, and re-fetch the Jira ticket (`Atlassian:getJiraIssue`) in case it changed.
3. The diff: `git fetch origin` first, then `git diff origin/<default>...<branch>` — diffing against a stale local base reviews changes that aren't there and misses conflicts with what landed on main since the branch was cut. Review the diff, not the whole repo (but the subagent may open surrounding files when a hunk is unintelligible without them).

## What to check

Go through these deliberately — each is a common source of "passed review, broke in prod":

- **Acceptance criteria, one by one.** For each criterion, point to the code that satisfies it. Any criterion with no corresponding change is a blocking finding. Distinguish *satisfied* from *demonstrated*: a criterion the plan marked `requires-manual-run` and nobody executed is unproven, and if it is the criterion the ticket exists for, that is blocking no matter how green the suite is.
- **Every platform, mode and environment the repo supports.** Read the repo's own docs for the matrix (OS, deployment mode, packaged vs dev, container runtime) and walk the change through each. Shell invocation, path separators, filesystem semantics and container behaviour are where changes verified on one machine quietly break another — and this class of defect survives review precisely because the implementer tested on their own laptop.
- **Edge cases and failure modes.** Empty/null inputs, boundary values, concurrent access, partial failure, timeouts, retries. What happens on the unhappy path?
- **Error handling and cleanup.** Are errors swallowed? Are resources (connections, files, locks) released on every path?
- **Secrets and config.** No credentials in code or ConfigMaps; secrets go through the proper mechanism. Flag any plaintext sensitive value.
- **Test quality, not just presence.** Do the tests exercise the risky paths from the plan, or just the happy path? Would they actually fail if the code regressed? Trivial assertions are worse than none because they signal false safety. Two specific traps: a test whose fixture *establishes* the relationship the assertion then checks proves only that the language works; and a test whose **name contradicts its assertion** is worse than no test, because the next person will "fix" whichever half is wrong — possibly the production code. Also ask what has *no* test: if the change's central line could be reverted with the suite still green, say so.
- **Consistency.** Does the code match existing conventions and the design in the plan? Undocumented deviations from the plan are findings.

## Output

Write findings to `.dev/reviews/<KEY>.md`, categorized so the user knows what must change vs what's optional:

```markdown
# <KEY> — review
Diff: origin/<default>...<branch> @ <branch HEAD sha>
Context: subagent (<n> reviewers, lenses: <...>) | fresh-session | same-session (weaker)

## Blocking (must fix before MR)
- B1: <file>:<line> — <problem> — <why it matters, with a concrete failure scenario>
  <if several reviewers found it independently, or if they disagreed and how you resolved it>
  Resolution: <left empty by review; filled by ticket-build as `fixed <sha>` or `waived — <reason>`>

## Should fix
- S1: ...
  Resolution:

## Nitpick / optional
- N1: ...

## Acceptance criteria check
- [x] <criterion> — satisfied by <file>, demonstrated by <test/command>
- [ ] <criterion> — satisfied by <file> but NOT demonstrated (requires-manual-run, unexecuted)
- [ ] <criterion> — NOT addressed → also listed as a Blocking finding

## Verified fine (recorded so it is not re-derived)
- <thing that looked suspicious and was checked, with the conclusion>
```

Each finding gets an ID and an empty `Resolution:` line — that line is the ledger `ticket-build` fills in fix mode and `ticket-mr` checks as its precondition. The review file stays local and uncommitted: both phases read it from the working tree, and human reviewers learn about waived findings from the MR description, which `ticket-mr` already requires to quote them verbatim. Findings from an automated review don't belong in the team's history.

## Boundaries

Do not fix the issues here — reviewing and fixing in one pass reintroduces the anchoring problem. Hand the findings to `ticket-build` (fix mode), then re-review the fix commits or proceed to `ticket-mr`. Re-reviews can be scoped to the fix commits plus any finding marked waived.

**A large fix batch needs a re-review, not a spot check.** When a fix pass resolves several blocking findings across different layers, the result is a substantial new change written by the same agent — the exact situation this phase exists for. Re-review it properly, with fresh reviewers.

**Feed recurring findings back into `ticket-plan`.** If a whole class of defect keeps surfacing here — platform coverage, untested glue, criteria that were never demonstrated — the cheap fix is a question in the plan gate, not a sharper review. A defect caught at design costs a paragraph; the same defect caught here costs a fix-and-re-review cycle.
