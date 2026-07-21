---
name: ticket-mr
description: Prepare and open a GitLab merge request for a completed, reviewed ticket. Use whenever the user wants to ship, open an MR/PR, or hand a branch off for human review — e.g. "prepare the MR for PROJ-123", "open a merge request", "ship this", "write the MR description". This is the FINAL phase of the ticket workflow. It composes a Jira-linked MR description from the plan and review, pushes the branch, and stops at the human approval gate — it never merges or marks the ticket Done automatically.
---

# ticket-mr

Package the finished work into a GitLab merge request that a human can review quickly and that links cleanly back to Jira. Stop at the approval gate — acceptance stays human.

## Preconditions

Before composing anything, confirm mechanically:
- Tests are green (`./gradlew test`).
- Every finding under **Blocking** in `.dev/reviews/<KEY>.md` has a non-empty `Resolution:` line (`fixed <sha>` or `waived — <reason>`). An empty Resolution on a blocker means the fix loop isn't done — say so and stop; don't accept a verbal "it's handled" in place of the ledger.
- If no review file exists at all, flag that the ticket is skipping review and ask the user to confirm before proceeding.

## Steps

1. **Title.** Lead with the Jira key so GitLab's Jira integration links the MR to the issue: `PROJ-123: <concise change summary>`.

2. **Description.** Fill this template from the plan and review artifacts — don't make the human reconstruct the context that already exists in `.dev/`:

```markdown
## What & why
<2-4 sentences: what this changes and the problem it solves>

Closes <Jira link>   <!-- or "Relates to" if it's partial -->

## Changes
- <bullet per meaningful change, reviewer-oriented>

## Testing
- <what was run, e.g. `./gradlew :module:test` — all green>
- <how a reviewer can verify manually, if relevant>

## Review notes
- <known tradeoffs, follow-ups deferred to other tickets, anything the reviewer should scrutinize>
- <any waived blocking findings, verbatim with their reasons — human reviewers must see what was consciously skipped>
```

3. **Decide `.dev/` disposition.** The plan and review files were committed on the branch so the workflow could span sessions — now they're about to enter the MR diff. Ask the user which convention their team uses (once per project, then remember it in the project's CLAUDE.md): **keep** them in the repo as living documentation, or **remove** them with a final `PROJ-123: drop workflow artifacts` commit before pushing. Either is fine; silently surprising human reviewers with review-bot findings in the diff is not. State the choice in the MR description.

4. **Push and open.** Push the branch. Open the MR via the GitLab connector if available, or `glab mr create --fill --description-file <file>` if `glab` is installed; otherwise present the finished title + description for the user to paste. Set the target to the default branch unless the user says otherwise.

5. **Jira linkage.** The key in the branch, commits, and MR title is what drives GitLab↔Jira linking, so double-check it's present and correctly cased. Only add a smart-commit transition (e.g. moving the issue to a review state) if the user asks — silent status changes surprise teammates.

## Boundaries

Never merge, never mark the Jira ticket Done, never approve on the user's behalf. Report the MR URL and the current ticket status, and leave the merge decision to a human.
