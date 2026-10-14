---
name: ticket-test
description: Manually verify a Jira ticket that someone else implemented, against the real running app — in the app, not the unit suite. Checks out the branch named after the Jira key, derives the manual tests from the ticket and the diff, executes them with screenshots a human can audit, writes a verdict per criterion, and leaves the machine exactly as it was. Use whenever the user wants to test, verify, validate, QA or accept a ticket's branch in the app — e.g. "test PROJ-123", "QA PROJ-123", "run the manual tests for PROJ-123", "verify PROJ-123 actually works", "smoke test the branch of PROJ-123 before I approve it", "screenshot the feature on PROJ-123". It never edits code, never commits and never fixes — a failing test is reported with its evidence, nothing more.
---

# ticket-test

Execute, against the real application, the manual tests that prove a ticket someone else implemented does what the ticket says. Evidence goes to `.dev/tests/<KEY>/` as screenshots a human can audit, verdicts go to `.dev/tests/<KEY>.md`, and the machine is left exactly as it was found except for those two paths and the one git-exclude line that hides them. **The branch is not yours to change.** Nothing in this skill edits a file the app reads — not to make a test reachable, not to make it pass, not to make it faster.

## Why this skill never edits, and never trusts itself

- **You are testing someone else's work.** A pass on a branch you patched to reach the flow is evidence about a branch nobody ships. Removing editing from this skill is what makes the evidence worth anything, and it is also what keeps the verdict honest when the branch is wrong: the right outcome of a flow you cannot reach is a report, not a workaround.
- **"I ran it" is not auditable.** Saved before/action/after screenshots are. A human reading the report cannot tell a test that ran from one that was imagined unless the files exist on disk, so a verdict without files is not a verdict.
- **A machine left dirty costs more than the test saved.** A running stack, a dev database full of test projects, a checkout on the wrong branch — each is a surprise for the next session. The ledger below exists so that cleanup is a walk through a list, not a memory exercise.

## Steps

0. **Pre-flight git, before fetching anything.** Record the branch you start from (`git branch --show-current`, or the detached sha). `git status --porcelain` must print nothing; if it does not, stop and tell the user what is dirty — **never stash, never `checkout -f`, never discard**: the working tree is theirs. Then `git fetch origin`. If `origin/<KEY>` does not exist, stop: there is nothing to test. If a local branch `<KEY>` exists and points at the same commit as `origin/<KEY>`, check it out; **in every other case check out `origin/<KEY>` detached** (`git checkout --detach origin/<KEY>`) and say so in the artifact header. You test what was pushed, you never create a local branch, and you never move one the user already has. Record the sha you are testing (`git rev-parse HEAD`).

   Make sure `.dev/` is git-excluded: `git check-ignore -q .dev`, and if it does not match, append to the file `git rev-parse --git-path info/exclude` names (that form also works inside a worktree):

   ```
   # ticket-test artifacts (local only)
   .dev/
   ```

   The exclude file rather than `.gitignore` because it is per-clone and never committed, so the report and the screenshots stay invisible to `git add -A` and to the developer's diff. That one line is the only thing besides the report that outlives the run, and it is listed as such below.

   **If `.dev/tests/<KEY>.md` already exists, a previous run was interrupted or is being repeated.** Read its ledger first and resolve every open `L-nn` in it — stop what it says is running, remove what it says was created — then rename it to `.dev/tests/<KEY>-<its timestamp>.md`. Only then **create `.dev/tests/<KEY>.md` with the header and an empty ledger**, before any process starts: the ledger must exist before the first thing it records.

1. **Fetch the ticket** (`Atlassian:getJiraIssue`): description, acceptance criteria, comments — the developer often leaves "how to test" notes there — and attachments naming datasets or environments. Restate in one paragraph what the ticket promises. The tests are derived from that promise, not from what the diff happens to do; a diff that does something the ticket never asked for is a finding, not a test.

2. **Derive the test set — written in full before anything runs.**
   - Start from the acceptance criteria. If the ticket has none, derive candidates from its description and say that you did; the user can correct them at the gate.
   - `git diff origin/<default>...HEAD --stat`, then read the touched code enough to know which screens, actions or endpoints reach it. Read the repo's own docs for how the app runs: launch commands, deployment modes, readiness URLs, fixtures, the selectors its own end-to-end suite uses. This skill is generic; the repo tells you how it runs. If the docs do not say and finding out would cost more than the thresholds below allow, that is a `not-testable` line, not an afternoon of archaeology.
   - **Decide the mode, and write the reason down.** If the repo has several deployment modes: files under a mode-specific module or package require that mode; shared code runs in the mode the ticket names, and if it names none, in **the cheapest mode to bring up and clean after** — the one with no login and a database that dies with the process. "Both" means both are run; a mode you reasoned about but never started is `not run`, never `pass`.
   - Per test, write: `T-nn`, the criterion it proves, the mode, the precondition (the smallest fixture in the repo that exercises the criterion), numbered steps naming the selectors or identifiers you will drive, **Expected** as a literal — the text, the element, the file name, the status code — written before you run anything, and the evidence you will capture. **Every criterion that names an error, a cancel, an invalid input or a timeout gets its own `T-nn`** with its own Expected; a test set with only happy paths against such a criterion is incomplete. **Every screen or endpoint the diff touches gets one `T-nn` for the behaviour the ticket did not change**, so a regression shows up as a `fail` instead of going unnoticed.
   - Name everything you will create after the run: project names `ticket-test-<KEY>-T01`, and so on, so nothing you made can be mistaken for the user's own data.
   - **Gate.** Present the test table, the mode decision, the environment you will start, and — if any mode in the set keeps its data after the process stops — that the run ends with the repo's dispose task and exactly what that deletes. Wait for a go. Bring-up is the expensive part, so scope is corrected here. If the user said "just run it" when invoking the skill, you may proceed without waiting — but the table and the announcement are still written first, and **when a mode in the set keeps its data, "just run it" does not apply: wait for the go**, because the dispose task is only ever run after the user has seen what it deletes.

3. **Bring the environment up, and snapshot what was already there.** Before launching anything, record in the artifact: the containers present and their status (`docker ps -a`, if the stack uses containers), the listeners on the app's ports, the listing of the app's storage root where the repo's docs name one, and — once the app is up — the projects or records that already exist, each marked `pre-existing — never touch`. **Read the launcher before running it.** A launcher that writes build output, pid files or logs is fine; one that rewrites a configuration file the app reads at startup is not a launcher you may run — that is a `blocked` line. Launch in the background, and **write the ledger line before the launch**, not after. Wait on the documented readiness URL and on the UI port; do not sleep a fixed number of seconds. Save what readiness returned to `.dev/tests/<KEY>/env-<mode>-ready.txt` — that file is the proof the mode was actually run. Then take `docker ps -a` again and **ledger every container absent from the snapshot**, with pre-state `absent`, and every one whose status changed, with its previous status.

   **Credentials.** If the identity provider is not on localhost, open the tab and ask the human to log in; you never type a password into a page that is not served by the app under test. On localhost, use only values the repo itself ships — a seed, an identity-provider export, a fixture — or values the user typed in chat. **Never open `.env`, `secret*` or `credentials*` for anything, not even a path.** Anything that needs a licence, a token, a dataset not in the repo or a machine you do not have: ask once. A value the user types in chat is passed inline on the one command that needs it (`VAR=… <launcher>`) and ledgered as `env-var`; shell state does not persist between tool calls, so an `export` in a separate call reaches nothing. If the user would rather not put the value in chat, or does not provide it, the dependent tests are `blocked` — not improvised around.

4. **Execute one test at a time, evidence to disk.** For each step that matters, take the screenshot with `save_to_disk: true`, move the file to `.dev/tests/<KEY>/T-nn-<step>-<before|action|after>.png`, and `ls` it. **Evidence standard: a pass needs the triple** — the state before the action, the action itself visible (the button, the dialog, the input filled), and the state after matching Expected. A final-state screenshot alone proves the state exists, not that your action produced it. Where the proof *is* the transition — a progress indicator becoming a result, a modal closing, a cancel mid-run — record it with `gif_creator` instead; the export lands in the browser's download folder, so ledger it and move it. After every test, read the console (`read_console_messages`, errors only) and the failed requests (`read_network_requests`, 4xx/5xx) into `T-nn-console.txt`; an error during a passing test goes into Observed, not under the rug. Never trigger a native `alert`/`confirm` dialog: it blocks the browser tools.

   Long-running steps (long computations, imports): poll the readiness selectors the repo's e2e docs name, with a 5-minute budget per step; past it, the test is `blocked — exceeded budget`, with the elapsed time.

   **Desktop-only flows** — the app's native window, its native menus, its file dialogs — get one attempt with a throwaway driver script in your scratchpad, built on the desktop automation the repo's own tooling already ships (for an Electron app, Playwright's `_electron` launch), against the pieces the launcher would have started. Never a file in the repo. The script is ledgered as `scratch` and **every process it starts is ledgered as `process`**. If that attempt does not reach the flow, the verdict is `not-testable` with what it would take. Native OS file dialogs cannot be driven by either tool; unless the app offers a path around them, they are `not-testable` too.

   **"Changing the code" means any write to a tracked file or to a file the app reads at runtime**: source, properties and environment files, any `.env`, feature flags, build and package scripts, identity-provider or container-stack definitions, fixtures and datasets, and the git exclude file beyond the `.dev/` line. It also means `git checkout -- <file>`, `git apply`, running a task that rewrites local config, and setting an environment variable the app reads — unless the user typed the value in chat, in which case it is ledgered. Running a build or serve configuration that already exists is not changing the code. **The one exception is the repo's dispose task, run only as step 7 says and only after the gate announced it.**

5. **Verdict per test**: `pass` · `fail — <the divergence, quoted from Observed>` · `blocked — <what is missing, and who was asked>` · `not-testable — <the threshold hit, and what it would take>`. **Before writing any verdict, `ls` every path on the test's `Evidence:` line, and a `pass` needs the `-before`, `-action` and `-after` files — or the GIF — in that output.** A missing file downgrades the verdict to `blocked — evidence lost`; an image you saw in context but never saved is not evidence.

6. **Finish the artifact.** It has been appended to throughout — pre-existing state at step 3, each test as it ran, each ledger line before its action. Never write it at the end from memory. Embed each screenshot under its test (`![T-01 before](T-01-1-before.png)`) so a human reading the report sees the evidence without opening files one by one.

7. **Cleanup — walk the ledger in reverse creation order, then run the mechanical check.** Whatever the app can delete, delete through the app while it is still running, so that its own cleanup of files and rows happens. Then stop what *you* started, the way the repo's launcher stops it, and restore containers to the state you snapshotted: a container that was running stays running, one that was stopped goes back to stopped, one that did not exist is removed. Close the tabs you opened, remove downloads you did not keep as evidence, delete the scratch driver. Finish with `git checkout <original branch>`.

   **Data the app cannot delete.** If a mode keeps its data after the process stops (a dev database on a volume, a storage root) and the app has no way to remove what you created, the run ends with the repo's documented dispose task — the one that removes the dev containers, their volumes and the storage roots. Read that task before relying on it and write into the ledger exactly what it removes, including the user's own data. **Run it only if the gate at step 2 announced it.** If the need is discovered only now, or the repo has no such task, **never improvise an equivalent** — no `docker volume rm`, no `rm -rf` of a storage root: report the residue with its identifiers and the user decides.

   **Mechanical check, written into the artifact as the last thing:** `git status --porcelain` prints nothing · `git diff HEAD` prints nothing · `git branch --show-current` is the original branch · listeners on the app's ports match the snapshot · containers match the snapshot, or the dispose task's documented end state · the storage root listing matches the snapshot, where one was taken · the scratchpad holds no driver · every `L-nn` has a `Resolution:`. Any line that fails is reported in chat with what is still there.

8. **Chat summary.** A verdict table, leading with the criterion the ticket exists for; the path of the report and the screenshots; what was not tested and why, in one line each; every ledger line still open, with its identifiers. Offer to draft — not post — a Jira comment with the verdict table and the evidence paths, since the developer is the one who needs to read it. Then stop. What to do about a `fail` is the user's call, not yours.

## Cleanup ledger

Section `## Created (cleanup ledger)` of the artifact, one line per thing:

```
L-nn — <kind> — <identifier or path> — step <n> for T-nn — remove by: <command or UI action> — Resolution:
```

The line is written **before** the creating action and confirmed after it, so an interrupted run leaves a to-do list with at most one unconfirmed entry. Kinds: `process` (the launcher's, and every process a scratch driver starts), `container` (with its pre-state: absent, stopped or running), `project` or whatever the app calls its records, `download`, `tab`, `scratch`, `env-var`, and `dispose` — the task that was run and everything it removed. `Resolution:` closes as `removed <how>`, `kept — evidence` (allowed only for files under `.dev/tests/<KEY>/`), or `left — <reason, user told, identifiers>`. An empty `Resolution:` at the end is a failed cleanup and is reported as such. What survives the run: `.dev/tests/<KEY>.md`, `.dev/tests/<KEY>/`, and the `.dev/` line in the git exclude file. Nothing else.

## Not testable: the thresholds

Each of these ends in a report line with a cost estimate, never in a workaround:

- A licence, token or account the user did not supply after being asked once.
- An operating system you are not on — path or launcher behaviour of another platform, a packaged installer.
- A native OS dialog, after the one desktop-driver attempt, with no path around it in the app.
- A step longer than five minutes, or a dataset that is not in the repo.
- Reaching the flow would need an edit to any tracked or app-read file, a feature flag, a fixture.
- The full distribution build, or a cluster, is the only way to run the flow.
- A second human user, real hardware, or a network the dev stack does not provide.
- More than about thirty minutes of setup beyond the launchers the repo documents. State the estimate and what the time would go into.

## Artifact template

```markdown
# <KEY> — manual test run
Jira: <link>   Tested: <sha> (<local branch <KEY> | origin/<KEY> detached>)   Original branch: <name>
Test set from: ticket acceptance criteria + diff vs origin/<default>
Modes run: <mode(s)> — reason: <…> — readiness: env-<mode>-ready.txt   Modes not run: <mode(s)> — reason: <…>
Environment: <launcher per mode, fixture used, browser | desktop driver>
Pre-existing state: <records, containers + status, listeners, storage root listing — never touched>

## Tests
### T-01 — <criterion it proves> — mode: <…>
Precondition: <fixture, state>
Expected (written before running): <literal>
Steps: 1. <action, selector> 2. …
Observed: <what happened, including console and network errors>
Evidence: .dev/tests/<KEY>/T-01-1-before.png, T-01-2-action.png, T-01-3-after.png, T-01-console.txt
![T-01 before](T-01-1-before.png) ![T-01 action](T-01-2-action.png) ![T-01 after](T-01-3-after.png)
Verdict: pass | fail — <divergence> | blocked — <missing> | not-testable — <threshold>

## Not testable / too complex
- T-nn — <threshold> — what it would take: <estimate, and which file would have to change>

## Created (cleanup ledger)
- L-01 — process — <launcher> pid <n> — step 3 — remove by: SIGINT, then <stop task> — Resolution:
- L-02 — container — <name> (pre-state: absent) — step 3 — remove by: <stop task> — Resolution:
- L-03 — project — "ticket-test-<KEY>-T01" id <n> (<mode>) — remove by: <app delete | dispose task> — Resolution:
- L-nn — dispose — <task> — removes: <containers, volumes, storage roots> — Resolution:

## Cleanup checklist / final state
- [ ] git status clean · [ ] on <original branch> · [ ] app ports as snapshot · [ ] containers as snapshot
- [ ] storage root as snapshot · [ ] no scratch files · [ ] tabs closed · [ ] downloads moved or removed · [ ] every L-nn resolved
Final: <timestamp> — clean | open: L-nn … (identifiers above)
```

## Boundaries

No edits to tracked or app-read files, no commits, no `git add`, no stash, no new or moved local branches, no `git add -f .dev/`. No Jira transitions and no Jira comments — offer to draft one. No posting anywhere. The only write outside `.dev/` is the scratch driver, ledgered and removed. A failing test is reported with its evidence, never fixed and never explained away; the branch belongs to whoever wrote it. Never delete records you did not create; the only thing that may remove them is the repo's dispose task, run as step 7 says and only after the gate announced it. Never claim a mode you did not run: `Modes run` lists only modes whose launcher you started and whose readiness you saved to disk. Never let a verdict rest on an image that is not on disk. When nothing in the ticket can be tested in the app, say exactly that — a ticket whose whole change is unreachable from the UI is a real outcome of this skill, not a failure of it.
