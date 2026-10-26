---
name: ticket-test
description: Manually verify a Jira ticket that someone else implemented, against the real running app — in the app, not the unit suite. Checks out the branch named after the Jira key, derives the manual tests from the ticket and the diff, executes them with screenshots a human can audit, writes a verdict per criterion, and leaves the machine exactly as it was. Use whenever the user wants to test, verify, validate, QA or accept a ticket's branch in the app — e.g. "test PROJ-123", "QA PROJ-123", "run the manual tests for PROJ-123", "verify PROJ-123 actually works", "smoke test the branch before I approve it", "re-check T-06 on PROJ-123, the developer fixed it". It never edits code, never commits and never fixes — a failing test is reported with its evidence, nothing more.
---

# ticket-test

Execute, against the real application, the manual tests that prove someone else's branch does what the ticket says. Evidence: screenshots in `.dev/tests/<KEY>/`; verdicts: `.dev/tests/<KEY>.md`. The machine is left as found except for those two paths and the `.dev/` exclude line. **The branch is not yours to change** — a pass on a branch you patched is evidence about a branch nobody ships, and a verdict without files on disk is not a verdict.

## Steps

0. **Pre-flight git, before fetching anything.** Record the starting branch (or detached sha). `git status --porcelain` must be empty; otherwise stop and report — **never stash, `checkout -f` or discard**. `git fetch origin`; no `origin/<KEY>` → stop. A local `<KEY>` at the same commit as `origin/<KEY>` → check it out; **any other case → `git checkout --detach origin/<KEY>`** and say so in the header. Never create or move a local branch. Record `git rev-parse HEAD`.

   Ensure `.dev/` is excluded: `git check-ignore -q .dev`, else append to the file `git rev-parse --git-path info/exclude` names:

   ```
   # ticket-test artifacts (local only)
   .dev/
   ```

   **Existing `.dev/tests/<KEY>.md`** means an interrupted or repeated run: resolve every open `L-nn` in its ledger first (stop what it says is running, remove what it created), then rename it `.dev/tests/<KEY>-<its timestamp>.md`. Create the new file with header and empty ledger **before any process starts**.

   **Re-test mode** ("re-check T-06", "the developer fixed T-03, the branch was rebased"): same pre-flight (the sha will differ — record both), reuse the previous test set verbatim for the named tests only, run just those plus one unchanged-behaviour test on the same screen, and write a new report section `## Re-test of <old sha> → <new sha>` with the old verdict next to the new one. Evidence files get a `-r2` suffix so nothing from the first run is overwritten.

1. **Fetch the ticket** (`Atlassian:getJiraIssue`): description, criteria, comments ("how to test" notes), attachments. Restate the promise in one paragraph; tests derive from it, not from the diff — a diff that does something the ticket never asked for is a finding.

2. **Derive the full test set before anything runs.**
   - From the acceptance criteria (derive candidates if none, and say so).
   - `git diff origin/<default>...HEAD --stat`, then read enough of the touched code to know which screens, actions or endpoints reach it. The repo's docs say how the app runs (launch commands, modes, readiness URLs, fixtures, e2e selectors). If they don't and finding out exceeds the thresholds below, that is `not-testable`, not archaeology.
   - **Decide the mode and write the reason.** Mode-specific files require that mode; shared code runs in the mode the ticket names, else the cheapest to bring up and clean (no login, database that dies with the process). "Both" means both run; a mode reasoned about but not started is `not run`.
   - Per test: `T-nn`, criterion, mode, precondition (smallest fixture in the repo), numbered steps with selectors, **Expected as a literal written before running**, evidence to capture. Every error/cancel/invalid/timeout criterion gets its own `T-nn`. Every touched screen or endpoint gets one `T-nn` for the behaviour the ticket did not change.
   - Name everything you will create `ticket-test-<KEY>-Tnn`.
   - **Gate.** Present the table, the mode decision, the environment to start, and — if any mode keeps its data — that the run ends with the repo's dispose task and exactly what it deletes. Wait for a go. "Just run it" / "go" at invocation skips the wait **except when a mode keeps its data**: the dispose task runs only after the user has seen what it deletes.

3. **Bring the environment up, snapshot first.** Record in the artifact: containers and status (`docker ps -a`), listeners on the app's ports, the storage root listing where the docs name one, and once up, pre-existing records marked `pre-existing — never touch`. **Read the launcher before running it**: one that rewrites a config the app reads at startup is a `blocked` line. Write the ledger line, then launch in the background; wait on the documented readiness URL and UI port (no fixed sleeps); save the readiness response to `.dev/tests/<KEY>/env-<mode>-ready.txt` — the proof the mode ran. Snapshot `docker ps -a` again and ledger every new container (pre-state `absent`) and every status change. **Record the stop procedure now**, from the launcher's docs: a Gradle/Quarkus dev JVM does not die on SIGINT to the wrapper — note the stop task or the pid to SIGTERM, and the port to watch.

   **Credentials.** Identity provider not on localhost → open the tab and ask the human to log in; never type a password into a page the app under test does not serve. On localhost use only values the repo ships or the user typed in chat (passed inline on the one command, ledgered `env-var`; shell state does not persist between calls). **Never open `.env`, `secret*` or `credentials*`.** Licence, token, dataset or machine you lack → ask once; not provided → `blocked`.

4. **Execute one test at a time, evidence to disk.** Screenshots with `save_to_disk: true`, moved to `.dev/tests/<KEY>/T-nn-<step>-<before|action|after>.png`, confirmed with `ls`. **A pass needs the triple** — before, action visible, after matching Expected. Where the proof is a transition, record a GIF with `gif_creator` (ledger the download, move it). After every test, errors from `read_console_messages` and 4xx/5xx from `read_network_requests` go to `T-nn-console.txt`; an error during a passing test goes in Observed. Never trigger a native `alert`/`confirm`. Long steps: poll the repo's readiness selectors, 5-minute budget, then `blocked — exceeded budget`.

   **Desktop-only flows** get one attempt with a throwaway driver in the scratchpad built on the automation the repo already ships (Electron: Playwright `_electron`), never a file in the repo; ledgered `scratch`, every process it starts ledgered `process`. Not reached → `not-testable`. Native OS file dialogs are `not-testable` unless the app offers a path around them.

   **"Changing the code"** means any write to a tracked file or a file the app reads at runtime (source, properties, `.env`, flags, build scripts, container or IdP definitions, fixtures, the exclude file beyond the `.dev/` line), plus `git checkout -- <file>`, `git apply`, config-rewriting tasks, and env vars the app reads unless the user typed the value. Running an existing build/serve configuration is not. The one exception is the dispose task, as step 7 says.

5. **Verdict per test**: `pass` · `fail — <divergence quoted from Observed>` · `blocked — <what is missing, who was asked>` · `not-testable — <threshold, what it would take>`. Before writing any verdict, `ls` every path on the `Evidence:` line; a missing file downgrades to `blocked — evidence lost`.

6. **Finish the artifact** — appended throughout, never written from memory at the end. Embed each screenshot under its test. **The report sits one level above the evidence folder, so links carry the folder prefix**: `![T-01 before](<KEY>/T-01-1-before.png)`, otherwise the images don't render in an editor preview.

7. **Cleanup — walk the ledger in reverse, then the mechanical check.** Delete through the app while it runs; stop what you started the way the launcher stops it (using the stop procedure recorded in step 3, and verify the port is free, not just that the wrapper exited); restore containers to the snapshot; close tabs; remove downloads not kept as evidence; delete the scratch driver; `git checkout <original branch>`. Data the app cannot delete → the repo's documented dispose task, **only if the gate announced it**; otherwise report the residue with identifiers — never improvise `docker volume rm` or `rm -rf`.

   **Mechanical check, last thing in the artifact**: `git status --porcelain` empty · `git diff HEAD` empty · on the original branch · listeners match snapshot · containers match snapshot or the dispose task's documented end state · storage root matches · no scratch driver · every `L-nn` has a `Resolution:`. Any failure is reported in chat with what is still there.

8. **Chat summary**: verdict table leading with the criterion the ticket exists for; report and evidence paths; what was not tested, one line each; open ledger lines with identifiers. Offer to draft — not post — a Jira comment with the table and paths. Then stop; what to do about a `fail` is the user's call.

## Cleanup ledger

Section `## Created (cleanup ledger)`, one line per thing, **written before the creating action** and confirmed after:

```
L-nn — <kind> — <identifier or path> — step <n> for T-nn — remove by: <command or UI action> — Resolution:
```

Kinds: `process`, `container` (with pre-state), `project` or the app's record name, `download`, `tab`, `scratch`, `env-var`, `dispose`. `Resolution:` closes as `removed <how>`, `kept — evidence` (only under `.dev/tests/<KEY>/`), or `left — <reason, user told, identifiers>`. What survives: `.dev/tests/<KEY>.md`, `.dev/tests/<KEY>/`, the `.dev/` exclude line. Nothing else.

## Not testable: the thresholds

Each ends in a report line with a cost estimate, never a workaround: a licence, token or account not supplied after one ask · another operating system or a packaged installer · a native OS dialog after the one driver attempt · a step over five minutes or a dataset not in the repo · reaching the flow needs an edit to a tracked or app-read file, a flag or a fixture · only the full distribution build or a cluster runs the flow · a second human, real hardware or a network the dev stack lacks · more than ~thirty minutes of setup beyond the documented launchers.

## Artifact template

```markdown
# <KEY> — manual test run
Jira: <link>   Tested: <sha> (<local branch <KEY> | origin/<KEY> detached>)   Original branch: <name>
Test set from: ticket acceptance criteria + diff vs origin/<default>
Modes run: <mode(s)> — reason: <…> — readiness: env-<mode>-ready.txt   Modes not run: <mode(s)> — reason: <…>
Environment: <launcher per mode, stop procedure, fixture, browser | desktop driver>
Pre-existing state: <records, containers + status, listeners, storage root — never touched>

## Tests
### T-01 — <criterion> — mode: <…>
Precondition: <fixture, state>
Expected (written before running): <literal>
Steps: 1. <action, selector> 2. …
Observed: <what happened, including console and network errors>
Evidence: .dev/tests/<KEY>/T-01-1-before.png, T-01-2-action.png, T-01-3-after.png, T-01-console.txt
![T-01 before](<KEY>/T-01-1-before.png) ![T-01 action](<KEY>/T-01-2-action.png) ![T-01 after](<KEY>/T-01-3-after.png)
Verdict: pass | fail — <divergence> | blocked — <missing> | not-testable — <threshold>

## Not testable / too complex
- T-nn — <threshold> — what it would take: <estimate, which file would have to change>

## Created (cleanup ledger)
- L-01 — process — <launcher> pid <n> — step 3 — remove by: <stop task>, then SIGTERM pid <n> — Resolution:
- L-02 — container — <name> (pre-state: absent) — step 3 — remove by: <stop task> — Resolution:
- L-03 — project — "ticket-test-<KEY>-T01" id <n> (<mode>) — remove by: <app delete | dispose task> — Resolution:

## Cleanup checklist / final state
- [ ] git status clean · [ ] on <original branch> · [ ] ports as snapshot · [ ] containers as snapshot
- [ ] storage root as snapshot · [ ] no scratch files · [ ] tabs closed · [ ] downloads handled · [ ] every L-nn resolved
Final: <timestamp> — clean | open: L-nn … (identifiers above)
```

## Boundaries

No edits to tracked or app-read files, no commits, no `git add`, no stash, no new or moved local branches, no `git add -f .dev/`. No Jira transitions or comments — offer to draft one. The only write outside `.dev/` is the ledgered, removed scratch driver. A failing test is reported, never fixed or explained away. Never delete records you did not create. Never claim a mode you did not run, never let a verdict rest on an image not on disk. A ticket whose change is unreachable from the UI is a real outcome: say exactly that.
