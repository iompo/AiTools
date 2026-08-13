---
name: ticket-mr
description: Prepare and open a GitLab merge request for a completed, reviewed ticket. Use whenever the user wants to ship, open an MR/PR, or hand a branch off for human review — e.g. "prepare the MR for PROJ-123", "open a merge request", "ship this", "write the MR description". This is the FINAL phase of the ticket workflow. It composes a Jira-linked MR description from the plan and review, pushes the branch, and stops at the human approval gate — it never merges or marks the ticket Done automatically.
---

# ticket-mr

Package the finished work into a GitLab merge request that a human can review quickly and that links cleanly back to Jira. Stop at the approval gate — acceptance stays human.

## Preconditions

Before composing anything, confirm mechanically:
- Tests are green, using the project's test command as named in the plan.
- Every acceptance criterion the plan marked *requires-manual-run* has actually been executed by a human, and the plan's **Verification status** says so. If any is still unproven, name it and stop — a fix whose central criterion was never run should not reach a merge request on the strength of unit tests alone.
- Every finding under **Blocking** in `.dev/reviews/<KEY>.md` has a non-empty `Resolution:` line (`fixed <sha>` or `waived — <reason>`). An empty Resolution on a blocker means the fix loop isn't done — say so and stop; don't accept a verbal "it's handled" in place of the ledger.
- If no review file exists at all, say so and ask the user to confirm before proceeding. The file is local and uncommitted, so an absent one can mean either "never reviewed" or "reviewed in a different clone" — ask which, rather than guessing; a review that happened elsewhere is a ledger you cannot check, and skipping review entirely is the user's call to make explicitly.

## Steps

1. **Title.** Lead with the Jira key so GitLab's Jira integration links the MR to the issue: `PROJ-123: <concise change summary>`.

2. **Description.** Fill this template from the plan and review artifacts. Those files never reach the MR — they're local to the machine the work happened on — so this description is the *only* channel through which their context reaches a reviewer. Anything a human needs in order to review well has to be restated here; don't gesture at an artifact they can't open:

```markdown
## What & why
<2-4 sentences: what this changes and the problem it solves>

Closes <Jira link>   <!-- or "Relates to" if it's partial -->

## Changes
- <bullet per meaningful change, reviewer-oriented>

## Testing
- <the test/build commands that were run — all green>
- <what was verified by hand, and on which platforms/modes>
- <anything NOT verified, and why — reviewers need to know where the evidence stops>

## Review notes
- <known tradeoffs, follow-ups deferred to other tickets, anything the reviewer should scrutinize>
- <any waived blocking findings, verbatim with their reasons — human reviewers must see what was consciously skipped>
```

3. **Push and open.** Push the branch. Open the MR via the GitLab connector if available, or `glab mr create --fill --description-file <file>` if `glab` is installed; otherwise present the finished title + description for the user to paste. Set the target to the default branch unless the user says otherwise.

4. **Jira linkage.** The key in the branch, commits, and MR title is what drives GitLab↔Jira linking, so double-check it's present and correctly cased. Only add a smart-commit transition (e.g. moving the issue to a review state) if the user asks — silent status changes surprise teammates.

## Boundaries

Never merge, never mark the Jira ticket Done, never approve on the user's behalf. Report the MR URL and the current ticket status, and leave the merge decision to a human.
