---
name: ticket-build
description: Execute a technical plan into working code and tests on a GitLab branch, or work review findings back into an existing branch. Use whenever the user wants to implement, build, or start coding a planned ticket — e.g. "implement PROJ-123", "build the plan", "code this up", "ticket-build TASK-03" — AND whenever they want to apply findings that are already written down, e.g. "fix the review findings", "address the blockers on PROJ-123", "apply H2 and H4". This is the SECOND phase of the ticket workflow and also the fix loop after ticket-review and ticket-feedback. Reading unprocessed GitLab MR comments is ticket-feedback's job, not this one. If no plan exists yet, say so and point back to ticket-plan.
---

# ticket-build

Turn `.dev/plans/<KEY>.md` into working, tested code on the `<KEY>` branch, **one task per session**. Optimize for "it works and the tests prove it"; deep critique is `ticket-review`'s job in fresh context, so don't review your own work here.

## Session scope and reading budget

**One task (or one fix batch) per session.** The plan's status block and `.dev/build/<KEY>.md` carry everything a fresh session needs; a session that carries three tasks of history costs several times more per turn and gets compacted. When a task is approved, end with: "run `/clear`, then `ticket-build <KEY> TASK-nn`". Continue in the same session only if the user asks. If the session was auto-compacted, say so at the gate: the task was too big for one session — propose splitting what remains.

Orient from the plan's **status block and the one task you are building** — not the whole plan, and never the build log unless the task depends on an earlier task's notes. Outline files before reading (`grep -n`), read line ranges, never more than ~200 lines without one, prefer the Read/Grep tools over Bash `cat`/`rg`. Batch independent reads, greps and git queries into one turn — every turn re-reads the whole context. Scope test runs to the module or suite that covers the change; the full suite runs once, at hand-off. Test and build output goes to a file (`<cmd> > .dev/build/<KEY>.out 2>&1; echo "exit $?"`); read the exit status, then only the summary and the failures — a build printed into context costs more than the code it tests.

## Steps

0. **Pick the mode.** Check both ledgers — `.dev/reviews/<KEY>.md` (IDs `B*`/`S*`/`N*`) and `.dev/mr-comments/<KEY>.md` (IDs `H*`). If either has findings without a `Resolution:` line → **fix mode** (below). Otherwise → **build mode**.

1. **Load the plan.** Missing → stop and point to `ticket-plan`. Read the status block, the task, and the design sections it references. Skim the Jira ticket (`Atlassian:getJiraIssue`): if acceptance criteria changed since planning, flag it and update the plan.

2. **Branch.** One branch per ticket, named exactly `<KEY>` (no suffix) — the key drives the GitLab↔Jira link. One commit per task; never a branch per task. Before the first commit confirm `.dev/` is excluded (`git check-ignore -q .dev`; else append `.dev/` to `.git/info/exclude` under `# ticket-flow workflow artifacts (local only)`).

3. **Build the task.**
   - Implement the smallest slice that satisfies it.
   - **Before writing machinery for an edge case the plan did not anticipate, price it and ask**: how the case is reached, how likely, what happens if nothing handles it — with a recommendation. Do not decide in either direction; building it hides best because it reads as thoroughness. Record the ruling in the plan (designed in, or residue with likelihood and recovery).
   - **No invented vocabulary.** Every new name derives from a term in the ticket, the plan's Vocabulary line or the codebase; anything else is proposed at the gate with alternatives, not used.
   - Write tests alongside the code. A standalone "write the tests" task in the plan is a planning bug: fold it into the tasks it covers and note the drift.
   - Run the scoped test command, **green from the runner's exit status, never from a piped tail** (`| tail`/`| grep` report the filter's status). After any mutation experiment force a fresh run — restoring a file can drop the build onto a cached result.
   - **Environment unavailable** (no Docker, licence, device, network)? Don't commit, don't present as green: say which criteria are unproven and what has to be running, and ask the user to bring it up.
   - **Prove each new test bites, per assertion**: revert the specific production line it claims to cover, watch it fail, restore, watch it pass, and report that you did. A task-level revert that reddens some test says nothing about the others. A characterization test of existing behaviour passes either way — say so.
   - **Test clarity rules** (each has cost a review round): the test name states exactly what the assertion checks; a test on a mocked collaborator never asserts the collaborator's own behaviour ("the logic is mocked, so of course it didn't change"); the fixture must not establish the relationship the assertion checks; no magic-count event-loop drains (`for (i<20) await Promise.resolve()`) — use the framework's `fakeAsync`/`tick`/`flush` or the project's helper; race-condition tests do not go in integration suites. A side-channel assertion (log, metric, event) checks the **content**, not merely that it fired.
   - Never add production code for a test's benefit (a field or accessor that exists only to be observed). Where the thing under test *is* a collaborator's behaviour (filesystem naming, a driver's contract), use a real fixture, following any naming/source-set split the repo already has.
   - A throwaway harness that verified something (build scripts, launcher glue) is promoted to a real test or recorded in the build log with its output.
   - **Green tests are not proof it builds.** Run the build/compile command for what you touched (the plan names it; find it once from the repo's docs and record it in the plan if missing). Report only the claims you ran.
   - **Cold-reader rule for tracked files.** Comments, READMEs, CLAUDE.md and commit messages are read by people who never saw the plan: no finding IDs, no plan vocabulary, no guard or clarification numbers, no `.dev/` paths. If a comment needs a paragraph of context, it is explaining the wrong thing — simplify the code or drop the comment. Don't add explanatory inline comments or co-author trailers unless the user asks; they get stripped before commit.

4. **Present at the approval gate and stop.** Name the task and what remains, then:
   - **Diff** (or a tight summary) and the test/build results with exit status.
   - **New names and concepts** — each with the ticket/codebase term it derives from.
   - **Beyond the plan** — every mechanism, edge case or deviation not in the task, with its three priced answers and whether the user already ruled on it.
   - **Tests added** — a table: test name → the one production behaviour it proves → bites (yes/characterization).
   - **Proposed commit**: `<KEY>: <subject>` and the exact file list to stage.
   - **Plan size**: `wc -l .dev/plans/<KEY>.md`. Over ~250 lines → say so and propose what moves to the build log; every later session and reviewer pays for it.

   Only a clear go-ahead ("approved", "commit it", "next") clears the gate; "just finish the rest" lets you proceed unattended from then on. If the user asks for changes, rework and re-present.

5. **Commit — in whichever mode the user works.**
   - **User commits** (say so once, then assume it): after "commit done", verify with `git show --stat HEAD` — subject carries the key, no leading whitespace, file list matches, no `.dev/` file — then tick the task.
   - **You commit**: stage the listed files only — never `git add -A`, `git add .`, `git commit -a` — and commit as proposed.
   - After the user rebases or amends: re-verify with `git log --oneline <base>..HEAD` and `git show --stat`; **do not re-run suites or builds unless the diff changed**. A pushed misleading commit is noted for the MR description, not rewritten.
   - Then tick the task in the plan (`[ ]` → `[x]`), update the status block, and append the task's section to `.dev/build/<KEY>.md` (template below). Commit red **once** only for an inseparable pair, marked `WIP`; prefer merging the two tasks (recorded as drift).

6. **Plan drift.** When reality contradicts the plan (task unnecessary, new task needed, wrong assumption), update the plan's design/tasks to what you did and note it in the build log. An ambiguity the Clarifications don't cover: stop and ask, record the answer, then continue. Keep the plan a contract: decisions and status go in the plan, evidence and narrative go in the build log.

7. **Watch the things that bit before.** No secrets in config/ConfigMaps; release resources on every path; handle the error paths the plan flagged; remove unused imports.

8. **Close the verification gate before claiming done.** Fill the plan's *Verification status* per criterion from what you observed; a `requires-manual-run` criterion is not done until a human executes it. If one is unexecuted, the ticket is not complete: say which, give the exact steps, lead with it if it is the criterion the ticket exists for.

## Fix mode

The work list is the open findings: Blocking (and, if the user wants, Should-fix) from the review, plus whichever `H*` the user picked. Both files open → ask which set. Stay on the branch.

- **Batching**: `B*` findings one per approval cycle. `S*` and `N*` are worked in the batches `ticket-review` proposed (or the user named, e.g. "fix S2 and S3"), one cycle per batch, with the gate's tests table listing every assertion changed.
- **Fix the defect, not the mechanism around it.** Confirm the finding is reachable from a real caller and re-read the callers it names; a finding resting on a state the app cannot produce is closed by saying so. Take the smallest change. Replacing a working primitive or reworking a shipped class is a redesign: name it, give the minimal alternative, get approval. A narrow, recoverable case may be worth `waived` rather than code — the user's call.
- An `H*` "Proposed fix" is a proposal: verify against the code, stop if stale or wrong. Its `plan-impact:` line, when not `none`, is part of the same approval cycle.
- Fix mode is not exempt from step 6: a fix that departs from the design updates the plan in the same cycle (the MR description is written from it). A fix closing a blind-test finding is a prime site for a new blind test.
- On approval and commit, append under the finding **in the file it came from**: `Resolution: fixed <sha> — <commit subject>` (the subject survives a rebase, the sha may not). `Resolution: waived — <reason>` only on the user's explicit decision; `Resolution: escalated — <question, owner>` when it needs a product decision (still open).
- After a fix pass that touched several findings or layers, point the user at `ticket-review` scoped to the fix commits.

## Build log template — `.dev/build/<KEY>.md`

```markdown
# <KEY> — build log
## TASK-01 — <what> — <sha> — <date>
Tests: <command> exit 0 (<n> tests)   Build: <command> exit 0
Bites: <test → mutated line → failed as expected> …
Drift: <none | what changed in the plan and why>
Notes: <harness output, procedures run by hand, environment quirks>
```

## Boundaries

Don't open the MR or transition Jira. Never stage, commit or `git add -f` anything under `.dev/`. When the branch is green, every task done and the verification gate closed, summarize what you built and the deviations, then point the user at `ticket-review` in a fresh conversation.
