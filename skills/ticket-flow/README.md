# ticket-flow

A spec-driven workflow for taking a **Jira ticket → a reviewed branch ready to merge** with Claude Code, tuned for a Gradle codebase. Five skills, one per phase, each producing an artifact the next phase reads. The skills themselves are kept imperative and short — the reasoning behind the rules lives here.

`.dev/` below is local scratch — git-excluded on first use, never committed.

```
Jira ticket
   │
   ▼  /ticket-plan      → .dev/plans/<KEY>.md       the CONTRACT: criteria, design, tasks, clarifications — NO code
   │                       └─ plan gate: a context-free subagent challenges the plan before any code
   ▼  /ticket-build     → ONE branch per ticket, ONE commit per task, ONE task per session, green after each
   │                       └─ .dev/build/<KEY>.md   the LOG: evidence, run records, drift (never read by reviewers)
   │                       └─ stops at an approval gate after every task; you commit, or it does
   │        ▲
   │        │ fix mode: works either findings ledger and fills the Resolution lines
   ▼        │
      /ticket-review    → .dev/reviews/<KEY>.md     2-3 context-restricted reviewers; parent adjudicates
   │                       └─ hands back a branch whose blockers all have a Resolution
   │
   ▼  you open the merge request — humans review it on GitLab
   │
   ├▼ /ticket-feedback  → .dev/mr-comments/<KEY>.md numbered proposals, one per thread, code or reply-only
   │                       └─ the numbers you pick go back to /ticket-build (fix mode)
   │
   └▼ /ticket-test      → .dev/tests/<KEY>.md + screenshots   QA of someone else's branch in the real app
                           never edits, never fixes, leaves the machine as found
```

## The ideas that make it work

1. **Artifacts are the coordination mechanism, and they stay on your machine.** Phases hand off through durable files, so a fresh session resumes mid-workflow by reading them. `.dev/` goes into the repo's `.git/info/exclude` on first use — itself uncommitted — so planning notes and review findings leave no trace and the MR diff contains only code. The tradeoff: continuity spans sessions on this clone, not across machines.

2. **The plan is a contract, the build log is a journal — and they are different files.** Every phase re-reads the plan and every reviewer gets a copy, so it is capped at ~250 lines and holds only what later phases check against. Evidence, mutation results, by-hand procedures and drift narrative go to `.dev/build/<KEY>.md`. Before this split, plans grew to a thousand lines and a single build session spent ~90k tokens re-reading them; reviewers each read the whole thing too.

3. **One task per session.** The artifacts carry the state, so there is no reason to carry a day of history in context. Sessions that spanned several tasks reached 600-900k tokens of context and were compacted a dozen times; most of their cost was re-reading that context on every turn. `ticket-build` ends each approved task by telling you to `/clear` and invoke it again for the next one.

4. **Adversarial passes are context-restricted, and there are two of them.** The plan gate (inside `/ticket-plan`) and the code review (`/ticket-review`) run as subagents that see only the artifacts — never the reasoning that produced them, and never the build log. A design flaw caught before code costs a paragraph; caught after, a rewrite. Reviewers are kept cheap deliberately: the parent runs the suite once at the shipping commit and passes the result; each reviewer gets the diff scoped to its lens and does targeted mutations only. The plan's recorded decisions are passed as *claims to verify*, never as settled context — a reviewer told the answer confirms it.

5. **The approval gate pre-empts the questions you would ask anyway.** Every task is presented with: new names and the codebase term each derives from (no invented vocabulary — "gate" and "arm" cost whole review rounds), every mechanism beyond the plan with its priced case (how reached, how likely, what happens without it — the user decides, never the agent), and a table of tests added with the one behaviour each proves. Test names must say what the assertion checks; mocked collaborators are never asserted as if real; no magic-count event-loop drains; no race-condition tests in integration suites.

6. **Tracked files are written for cold readers.** Comments, READMEs and CLAUDE.md never reference plan vocabulary, finding IDs, guard numbers or `.dev/` paths. Explanatory inline comments and co-author trailers are not added unless asked.

7. **The fix loop is explicit, and both reviewers feed it.** `/ticket-review` writes findings with IDs and empty `Resolution:` lines; `/ticket-feedback` writes human MR threads in the same shape (`H1`, `H2`, …). `/ticket-build` fix mode works either set — blockers one per approval cycle, should-fix and nitpicks in the batches the review proposed — and fills the ledger (`fixed <sha> — <subject>` so a rebase doesn't orphan it, `waived — <reason>`, `escalated — <question, owner>`). Reply-only and won't-do decisions on human comments are recorded directly by `/ticket-feedback`.

8. **Reviewer comments are proposals to triage, not instructions to execute.** `/ticket-feedback` anchors each thread to the code *as it is now*, classifies before proposing (a question wants an answer; a design objection changes the plan; a mistaken reviewer gets a drafted reply and no patch), marks each as `code` or `reply-only`, and posts nothing — replying to colleagues is your action.

9. **One branch per ticket, one commit per task, one approval per task.** Task granularity lives in commit history. `ticket-build` never chains tasks; it implements one, gets it green, presents it, and waits. Either you commit ("commit done") and it verifies what landed, or it commits on your go-ahead. "Just finish the rest" opts into unattended execution.

## Install

```bash
# project-local
cp -r ticket-plan ticket-build ticket-review ticket-feedback ticket-test .claude/skills/

# or global (available in every repo)
cp -r ticket-plan ticket-build ticket-review ticket-feedback ticket-test ~/.claude/skills/
```

Invoke by intent: "plan PROJ-123", "ticket-build PROJ-123 TASK-03", "review PROJ-123", "fix the review findings", "read the MR comments", "test PROJ-123". The skills use the Atlassian connector you already have; `/ticket-feedback` remembers which GitLab channel worked (connector, `glab`, REST with `$GITLAB_TOKEN`, or pasted threads) in its artifact header.

## Human gates (deliberate)

- `/ticket-plan` runs a **clarification gate**: all open questions — including every new name the design needs and every priced defence — go to you in one batched round before any design. No assumption without your answer or an explicit "you decide".
- `/ticket-build` stops at the approval gate after every task and after every blocking fix. Mid-build ambiguity stops and asks.
- `/ticket-feedback` stops after presenting the numbered list; it never applies, posts or resolves anything.
- `/ticket-test` stops at its own gate after presenting the test table and the environment it will start, and never runs a data-destroying dispose task it did not announce.
- Waiving a blocking finding is your explicit decision, recorded with its reason, quoted verbatim in the MR description.
- Opening the MR, merging, and marking the ticket Done are yours.

## Where to bend it

- **Small tickets**: go straight to `/ticket-build` with an inline plan and skip the gate. Ceremony should match risk.
- **Share the artifacts**: drop the exclude entry and commit them if your team wants plans and reviews as living documentation; accept that findings then show up in the MR diff.
- **Jenkins as source of truth**: repoint the "green" commands at the pipeline.
- **Automate the hand-off**: `glab mr create --fill` seeded from the plan's summary and the ledger's waived findings is the natural place to start.

## Validate it before trusting it

- **Seeded-defect test**: plant three flaws in a real branch; review once in the implementing conversation, once through the context-restricted reviewers. If the restriction doesn't catch more, drop it.
- **Plan-gate yield**: count gate findings over 4-5 tickets that would otherwise have required code changes.
- **The number that matters**: blocking comments from *human* MR reviewers per ticket, before vs after.
- **Cost check — measured, not eyeballed.** What you pay is the sum, over every API call, of what the model reads and writes: it is driven by **turns × context**, plus cache **rewrites** (the cache expired during a long pause, the model was switched, the session compacted). `tools/ctx-report.py` reports that sum per session and per subagent. Two guard rails catch the structural failures:
  - **Context growth** — peak context minus the first turn. Cost tells you how much; growth tells you why, and it is also the quality guard: a context full of stale diffs and test output makes the model less reliable at any price. Growth rather than peak because the first turn is fixed overhead (system prompt, tools, MCP servers, CLAUDE.md) that differs between setups and that no rule in these skills can change. Provisional budgets: a `ticket-build` session grows by less than **~200k**, **each** subagent by less than **~150k** — the old peak figures, kept only until your own data replaces them. Once `.dev/cost.tsv` holds ten sessions of a phase, `--summary` prints their 90th percentile: set the budgets there, so "over" means unusual for *your* tickets. `ticket-review` writes each reviewer's tokens into the review header.
  - **No auto-compaction in a build session.** Not because compaction is expensive — it usually makes the following turns cheaper — but because it means the task outgrew a session and the model is continuing from a summary it didn't choose. A manual `/compact` at a clean point is fine; `/clear` at a task boundary is better, because the artifacts restart the next session without loss.

  There is deliberately no cost budget yet: let `.dev/cost.tsv` collect a few tickets, then set one from the data. When a number is off, it points at one cause:

  | Symptom | Usual cause | Fix |
  |---|---|---|
  | build growth high | plan over ~250 lines, or the build log read whole | move evidence to the build log; read only the task's section |
  | build session auto-compacted | the task is too big for one session | split it; record the split as plan drift |
  | build growth climbs in steps | test/build output printed into context | redirect it to a file; read the exit status, summary and failures |
  | many turns at high context | one tool call per turn | batch independent reads, greps and git queries into one turn |
  | rewrites a large share of cost | model switched mid-session; several long pauses | switch models between sessions; one rewrite after you review at the approval gate is the expected price of the gate |
  | first turn over ~50k | MCP servers, CLAUDE.md | disable servers the phase doesn't use; trim CLAUDE.md |
  | one reviewer over | its diff isn't scoped to its lens, or it re-ran a suite | scope the diff; reviewers run targeted mutations only |
  | every reviewer over | build log or whole-branch diff handed to all | plan + per-lens diff only |

## Measuring cost

`tools/ctx-report.py` (Python 3, stdlib only) reads Claude Code's transcript of a session and of its subagents, detects the phase (the `ticket-*` skill invoked), and prints growth with its peak and first turn, turns, total tokens and cost, cache rewrites, auto/manual compactions, a line per subagent, and a token table per model (input, cache write, cache read, output, total). Exit status 1 when a guard rail is broken; the main-session budget is judged only for `ticket-build` sessions (and sessions whose phase wasn't detected), subagent budgets always. A log written by an older version of the script is set aside as `cost.<date>.old.tsv` rather than mixed in.

Prices are data, not code: `tools/prices.json` holds the per-model rates copied from the [pricing page](https://platform.claude.com/docs/en/about-claude/pricing) with the date they were checked. The cost log stores **raw token counts per model**, never dollars, so a price change is one edit to that file and `--summary` re-prices every session already logged. A model missing from the file is reported with its tokens and the cost marked `≥` (excluding it), never guessed; prices checked more than 90 days ago trigger a reminder to verify them.

```bash
python3 tools/ctx-report.py                  # latest session in the current repo
python3 tools/ctx-report.py <session>.jsonl  # a specific one
python3 tools/ctx-report.py --summary .dev/cost.tsv   # per ticket, at today's prices, plus p90 growth per phase
python3 tools/ctx-report.py --main-budget 120000 --agent-budget 90000   # budgets from your p90
```

To log every session without thinking about it, install the script and add a `SessionEnd` hook to `~/.claude/settings.json`. The hook fires on `/clear`, which `ticket-build` asks for after every task, so each task session becomes one row of `.dev/cost.tsv` with its branch (the Jira key). Repos without `.dev/` are skipped; the hook never fails.

```bash
mkdir -p ~/.claude/tools/ticket-flow && cp tools/ctx-report.py tools/prices.json ~/.claude/tools/ticket-flow/
```

```json
{ "hooks": { "SessionEnd": [ { "hooks": [ { "type": "command",
  "command": "python3 ~/.claude/tools/ticket-flow/ctx-report.py --hook --log \"$CLAUDE_PROJECT_DIR/.dev/cost.tsv\"" } ] } ] } }
```
