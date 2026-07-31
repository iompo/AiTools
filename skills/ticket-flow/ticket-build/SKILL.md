---
name: ticket-build
description: Execute a technical plan into working code and tests on a GitLab branch, or work review findings back into an existing branch. Use whenever the user wants to implement, build, or start coding a planned ticket — e.g. "implement PROJ-123", "build the plan", "code this up" — AND whenever they want to address review feedback, e.g. "fix the review findings", "address the blockers on PROJ-123". This is the SECOND phase of the ticket workflow and also the fix loop after ticket-review. If no plan exists yet, say so and point back to ticket-plan.
---

# ticket-build

Turn `.dev/plans/<KEY>.md` into working, tested code on a properly named GitLab branch. Optimize for "it works and the tests prove it" — deep critique is the next phase's job, done in fresh context, so don't try to review your own work here.

## Why hold back on self-review

You wrote this code and you're invested in it, so your own review will share its blind spots. Get it working and green, then hand a clean diff to `ticket-review` (ideally a fresh conversation). Trying to do both at once produces mediocre code and a shallow review.

## Steps

0. **Pick the mode.** Check for `.dev/reviews/<KEY>.md`:
   - If it exists and has findings without a `Resolution:` line → **fix mode**: your work list is the review's Blocking (and, if the user wants, Should-fix) findings, not the plan's tasks. Stay on the existing branch. Work one finding per approval cycle — never chain fixes or commits automatically. For each finding: fix it, run the relevant tests, then **present the change for review and stop at the approval gate** — show the diff (or a tight summary) and the test result, and **ask for explicit approval before committing.** Only on approval: commit with the key (`PROJ-123: fix — <finding summary>`) and append `Resolution: fixed <commit-sha>` under the finding in the review file — that file is local and uncommitted, so the append never enters a commit. If the user asks for changes, rework and re-present; if they tell you to stop pausing (e.g. "just fix the rest"), you may proceed unattended from that point. If the user decides a finding won't be fixed, record `Resolution: waived — <reason>` instead; never waive silently on your own.
   - Otherwise → **build mode**, steps below.

1. **Load the plan.** Read `.dev/plans/<KEY>.md`. If it's missing, stop and tell the user to run `ticket-plan` first — building without a plan is how the phase separation collapses. Skim the Jira ticket again (`Atlassian:getJiraIssue`) before starting: if acceptance criteria changed since planning, flag it and update the plan rather than building against a stale contract.

2. **Branch.** Create a single branch for the whole ticket, named after the Jira key alone (e.g. `PROJ-123`) — the key is the entire branch name, no description suffix. One branch per ticket, one commit per task — never a branch per task; task-level granularity lives in the commit history, which GitLab's MR UI can review commit-by-commit. The key in the branch name is what makes GitLab↔Jira linking free, so always include it.

   Before the first commit, confirm `.dev/` is git-excluded: `git check-ignore -q .dev`, and if it doesn't match, append `.dev/` to `.git/info/exclude` under a `# ticket-flow workflow artifacts (local only)` comment. `ticket-plan` normally did this already, but this phase can be entered directly with an inline plan, and one unexcluded commit is enough to put the plan in the team's history.

3. **Work task by task, in plan order — one task per approval cycle.** Do one task, then stop for the user; never chain tasks or commits automatically. For each task:
   - Implement the smallest slice that satisfies it.
   - Write or adjust the tests the plan called for, alongside the code — not at the end.
   - Run the relevant Gradle task (`./gradlew test` or the module-scoped task) and confirm green. A branch that's green after every task is trivial to bisect and review; one that's only green at the end hides which change broke what.
   - **Present the task for review and stop at the approval gate.** Show the user what this task changed — the diff (or a tight summary of it) and the test result — name which task it was and what remains, then **ask for explicit approval before committing.** Do not commit and do not start the next task until the user approves. If they ask for changes, rework this task and re-present it; only a clear go-ahead ("approved", "looks good", "commit it", "next") clears the gate. If the user tells you to stop pausing (e.g. "just finish the rest"), you may proceed unattended from that point — but only on that explicit instruction; the default is one task per approval.
   - **On approval, commit and tick.** Stage the concrete files this task touched — never `git add -A`, `git add .`, or `git commit -a`; a blanket add sweeps in unrelated work and is the one habit that would drag `.dev/` into history if the exclude entry were ever missing. Commit with the Jira key in the message, e.g. `PROJ-123: add retry backoff to client` — one commit per task, the granularity reviewers and `git bisect` will lean on — then tick the task in the plan file (`[ ]` → `[x]`). The tick happens after the commit, which is harmless precisely because the plan file is untracked; it never trails into the next task's diff. If a task is genuinely half of an inseparable pair (interface now, implementation next task) and greening it would mean writing throwaway stubs, it's acceptable to commit red **once**, marked `WIP` with the reason in the commit message — but the very next commit must restore green.

4. **Handle plan drift honestly.** If reality contradicts the plan (a task turns out unnecessary, a new one is needed, an assumption was wrong), update the plan file to match what you actually did and note it. A stale plan makes the review phase useless. The no-assumptions rule from planning carries over: if you hit an ambiguity the plan and its Clarifications don't cover, stop and ask the user, record the answer in the plan's Clarifications section, then continue — don't pick an interpretation just to keep momentum.

5. **Watch the things that bit before.** Don't hardcode secrets or credentials into config/ConfigMaps — use the project's secret mechanism. Clean up resources, handle the error paths the plan flagged.

## Boundaries

Don't open the MR or transition the Jira status here. Never stage, commit, or `git add -f` anything under `.dev/` — the plan and review files are local scratch, and the commits on this branch should contain code and tests only. When the branch is green and every task is done, summarize what you built and any deviations from the plan, then point the user at `ticket-review` — and suggest they run it in a fresh conversation so the reviewer isn't anchored by everything above.
