---
name: ticket-plan
description: Turn a Jira ticket into a technical plan before any code is written — including a systematic hunt for what the ticket does NOT say. Use whenever the user wants to plan, scope, design, analyze, or "figure out how to build" a Jira issue — e.g. "plan PROJ-123", "analyze this ticket", "how should we approach this", "break this issue into tasks". This is the FIRST phase of the ticket workflow: it interrogates the ticket for gaps and ambiguities, asks the user instead of assuming, and produces a durable plan artifact that ticket-build later executes. Trigger even when the user just pastes a Jira key and says "let's start", since starting well means planning first.
---

# ticket-plan

Produce a technical plan from a Jira ticket. Output design, tasks, and a test strategy to `.dev/plans/<KEY>.md`. **Do not write production code in this phase** — the goal is a plan another phase (or a fresh agent) can execute without re-deriving the thinking.

## Why this phase is separate

An agent that has already started coding rationalizes its own design. Planning as its own pass, with a written artifact, forces the tradeoffs into the open and gives every later phase a contract to check against.

## Steps

1. **Fetch the ticket.** Use the Atlassian connector (`Atlassian:getJiraIssue`, or `Atlassian:searchJiraIssuesUsingJql` if you only have a description). Read the description, acceptance criteria, comments, and linked issues.

2. **Restate the problem in your own words.** One short paragraph: what outcome the ticket wants and why. This catches misreadings early. List the acceptance criteria explicitly; if the ticket has none, derive candidate criteria and flag that you did.

3. **Interrogate the ticket for gaps.** Jira tickets are written for humans with shared context; assume that context is missing here and hunt for it explicitly. Check each of these and note what the ticket does NOT say:
    - **Scope edges** — what's explicitly out of scope? Does "fix X" include the adjacent Y everyone mentally bundles with it?
    - **Acceptance criteria quality** — are they testable as written, or vibes ("should be faster", "handle errors better")?
    - **Unhappy paths** — does the ticket only describe the success case? What should happen on invalid input, timeout, partial failure?
    - **Data & compatibility** — existing data to migrate? API/contract consumers who'd break? Backwards compatibility expected?
    - **Non-functionals** — any implied performance, security, or resource constraints the ticket never states?
    - **Environment** — which environments/configs does this apply to? Feature-flagged or straight in?
    - **Dependencies** — does this silently depend on another ticket, a team decision, or an external system?

4. **Read the code, don't imagine it.** Explore the affected modules, existing patterns, and neighbouring tests. Note the files and components the change will touch. A plan that names real files and existing conventions is worth ten that describe an idealized codebase. This step also filters the question list from step 3: anything the codebase itself answers (an existing convention, a config that already dictates the choice) gets answered here and noted — never forwarded to the user as busywork.

   **This includes local state, not just source.** If the change reads or writes anything outside version control — untracked config, local credentials, a database, a running container, fixture data — look at the real artifact before designing against an imagined one. Read its **shape, not its contents**: key names, mount points, table names, values redacted, since untracked config is exactly where secrets live. Designing against an imagined config is how a plan ends up telling the developer to run a command that destroys their credentials.

   **When the design reuses an existing call in a new role, read its return contract.** Not its
   signature — its documented semantics, and the implementation if the docs are thin. A call that is
   correct for the job it already does can be wrong for the new one, because what it hands back is
   normalised, filtered or reordered in a way the existing use never depended on. Prior correct use
   elsewhere in this repo proves nothing about the new use.

   **Split the reading: agents for breadth, yourself for depth.** Use subagents to find *where* things live and what conventions exist — file:line plus a one-line characterization, explicitly **not** verbatim file dumps, which cost heavily and still won't be precise enough to design from. Then read the two or three load-bearing files directly. Deciding that split up front avoids the common waste of paying for a long agent report and re-reading the same files anyway. Never sleep-poll for a subagent; launch it, then do non-overlapping work or end the turn.

5. **Clarification gate — ask, don't assume.** This is a hard rule for this phase: **do not resolve any remaining ambiguity by picking an interpretation yourself.** Collect everything still open from steps 2-4 into a single structured question round and put it to the user before designing anything:
    - Number each question, state why it matters (what changes in the design depending on the answer), and — where you can — offer the plausible options so the user can answer fast.
    - Batch them: one round of questions beats a drip-feed. Only ask a second round if an answer genuinely opens a new question.
    - If the user explicitly answers "you decide" or "doesn't matter" to a question, only then may you choose — and you record the choice AND that it was delegated.
    - If the ticket is missing information only its author or a stakeholder can supply, say so plainly and offer to draft the Jira comment asking for it (`Atlassian:addCommentToJiraIssue`) — don't design around the hole.
    - If, unusually, steps 2-4 leave nothing open, say that explicitly ("no open questions — the ticket plus the codebase answer everything") rather than inventing questions to appear thorough.

   Every answer gets recorded in the plan's **Clarifications** section: question, answer, who decided. The plan must be executable by someone who never saw this conversation, so the answers live in the artifact, not the chat scrollback. A plan containing an unstated assumption is a planning bug, exactly like a hardcoded secret is a coding bug.

6. **Design.** Propose the approach. Name at least one alternative and why you rejected it. Call out risky assumptions and anything that could ripple (schema changes, API contracts, config/secrets, migration). Keep it to the decisions — no line-by-line code.

   Two rules about how the design is *written down*, both of which have let real defects through:

    - **Decision tables go over the predicates the code will evaluate, not over prose state names.**
      If the approach turns on more than two outcomes, name each row as the expression that selects it
      rather than as an English description. Prose silently merges states the code must keep apart — a
      row phrased as an absence readily conflates "there was nothing to look at" with "there was
      something and none of it matched", which usually need different handling — and the
      implementation then treats them identically.
    - **If the change makes one class or member the odd one out among the siblings that share its
      role, either follow the sibling convention or write down why not.** Deviating from an
      established pattern is a strong signal the fix belongs at a different level. When every sibling
      carries a declaration and one does not, the fix is usually that missing declaration rather than a
      workaround bolted onto one of the outlier's call sites — a workaround fixes the site you were
      looking at and leaves the others broken.

7. **Break into ordered tasks** with dependencies. Each task should be independently verifiable and small enough to review. Order them so the branch stays green after each.

   Two rules that keep the task list honest:
    - **No standalone "write the tests" task.** Test work belongs to the task whose code it covers, because `ticket-build` writes tests alongside the code. A bundled TASK-N "Tests" guarantees the two phases contradict each other and that tests get written last, or not at all.
    - **If two tasks cannot be split without an inconsistent intermediate state, make them one task.** Splitting a change whose halves only make sense together produces a commit that is broken by construction — sometimes a transient instance of the very bug being fixed.

8. **Test strategy, and mark what can actually be proven.** For each risky path, say what to test and at what level (unit / integration). Name the concrete command this project uses, scoped as narrowly as still covers the change — a single module or suite beats the whole build when the toolchain allows it. Name the build/compile command too, separately: in many toolchains a green suite does not prove the project compiles for shipping. Define what "done" means beyond "it compiles".

   **Every bound, cap, limit or truncation the design introduces needs a named test at its
   boundary.** A limit is always introduced against a stated risk; if you cannot name the test that
   exercises it at the limit, the rationale is decoration. A cap whose only fixture sits below its
   threshold never runs the branch it exists for, and the suite stays green if the bound is deleted.

   Then tag **every acceptance criterion** as one of:
    - **demonstrable-by-test** — an automated check can prove it; name the test or command.
    - **requires-manual-run** — only a human executing the app can prove it (needs Docker, a licence, a dataset, real hardware, a GUI). Say exactly what the person has to do.

   Be honest about the second category rather than hiding it behind a test that merely *approximates* the criterion. This tag is what stops an undemonstrated fix from travelling all the way to the merge request: `ticket-build` may not report completion while a `requires-manual-run` criterion is unexecuted. If the criterion the whole ticket exists for lands in that category, say so in the chat summary — it is the most important thing the user needs to know.

9. **Write the artifact** to `.dev/plans/<KEY>.md` using the template below, then **make sure `.dev/` is git-excluded before anything in this workflow touches git.** Run `git check-ignore -q .dev`; if it doesn't match, append to the target repo's `.git/info/exclude`:

   **If the harness is in plan mode**, it may restrict edits to its own plan file, so `.dev/plans/<KEY>.md` cannot be written yet. Write the plan to the harness path, and the moment the plan is approved and edits are permitted, write the same content to `.dev/plans/<KEY>.md` — that is the path `ticket-build` and `ticket-review` read. Do not consider this phase finished until that file exists; a plan only the harness can see is invisible to every later phase.

   ```
   # ticket-flow workflow artifacts (local only)
   .dev/
   ```

   `.git/info/exclude` rather than `.gitignore` because that file is itself per-clone and never committed, so the workflow leaves no trace in the team's repo and `.dev/` stays invisible to `git add -A`, to reviewers and to the MR diff. The trade-off: the artifacts live only in this working tree, so a fresh session **on this machine** can resume mid-workflow by reading them, while a different clone cannot — there, re-run `ticket-plan` or copy the file across.

10. **Gate the plan before handing it off.** Spawn a subagent (the Task tool in Claude Code) whose prompt contains *only* the raw ticket text and the plan file — none of this conversation — and ask it exactly six questions:
- For each acceptance criterion, which part of the design satisfies it? Name any criterion with no answer.
- What is the most likely failure mode of the chosen approach?
- Is anything in the plan untestable as specified?
- Does the design rely on any interpretation of the ticket that is NOT recorded in the Clarifications section? (A smuggled assumption is a blocking finding.)
- **Does the design hold on every platform, mode and environment this repo supports?** Check the repo's own docs for the supported matrix (OS, deployment mode, packaged vs dev). Name any combination where the design fails or is untested. Shell invocation, path separators, container behaviour and filesystem semantics are the usual offenders.
- Does the plan contradict itself? Name any two statements in it that cannot both be true.

Fold blocking answers back into the plan before finishing — but **verify each one against the code first**, since the gate can confidently report intended behaviour as a defect; note any you rejected and why. **A finding that asserts an absence — "nothing tests this", "there is no caller", "this key is unused" — is verified by a repo-wide search, not by opening the one file the finding names.** A negative confirmed in a single file is not confirmed, and acting on one adds work that was already done elsewhere. This is the cheapest review in the workflow: a design flaw caught here costs a paragraph, the same flaw at code review costs a rewrite, and after merge it costs a broken build for everyone on the unlucky platform.

**Record which version of the plan the gate actually read** — a commit sha, or the timestamp of the
file when you launched it — in the plan's *Plan gate* section. If the plan changes materially
afterwards, **re-run the gate on the changed sections before handing off**: a Clarifications answer
that reverses, a decision table that changes shape, a new error path or public contract, or a
mechanism swapped for a cheaper one. A gate result describes the document it read, not the plan
that ships. This is not hypothetical bookkeeping: a post-gate rewrite that swaps a mechanism for a
cheaper one can introduce the very defect the gate exists to catch, and the eventual fix can turn
out to be a return to the approach the gate already saw and approved.

If subagents aren't available, ask the user to run these questions in a fresh conversation against the plan file.

11. Give the user a 4-6 line summary in chat, the gate's findings, and any open questions.

## Plan template

```markdown
# <KEY> — <ticket title>
Jira: <link>

## Problem
<one paragraph, your words>

## Acceptance criteria
<!-- tag every criterion: how it will be proven -->
- [ ] <criterion> — *demonstrable-by-test*: <test or command>
- [ ] <criterion> — *requires-manual-run*: <exactly what a human must do>

## Design
<approach, chosen over <alternative> because ...>
Affected: <files / components>
Risky assumptions: <...>
Platforms / modes checked: <where this was reasoned through, and where it was not>

## Tasks
<!-- tests belong to the task they cover; no standalone "write the tests" task -->
1. [ ] TASK-01 — <what> (depends on: none)
2. [ ] TASK-02 — <what> (depends on: TASK-01)

## Test strategy
- <path/behaviour> → <unit|integration>, run with `<command>`
- Build/compile command (a green suite is not proof it compiles): `<command>`
- Done when: <criteria beyond compiling>

## Verification status
<!-- maintained by ticket-build; the plan is not done until this is honest -->
- Demonstrated: <what was actually observed to work, and how>
- Not demonstrated: <every requires-manual-run criterion still unexecuted>

## Clarifications
<!-- every ambiguity found in analysis, with its resolution — no unstated assumptions allowed -->
- Q1: <question> → <answer> (decided by: user | ticket author via Jira comment | delegated to Claude by user)
- <or: "No open questions — ticket + codebase answered everything.">

## Ticket gaps flagged, not blocking
- <things the ticket doesn't cover that were deemed out of scope, so nobody rediscovers them later>

## Plan gate
- Gate read: <plan version the gate saw — sha or timestamp>; re-gated after: <material changes since, or "none">
- <finding from the gated review, and how the plan was adjusted — or "no blocking findings">
```

## Boundaries

Do not create a branch, write production code, or touch Jira status here. Never stage, commit, or `git add -f` anything under `.dev/` — it is a local scratch folder in every phase of this workflow, and force-adding it defeats the exclude entry step 9 just wrote. Do not design past an unanswered blocking question — waiting on the user is the correct behavior in this phase, not a failure to make progress. End by pointing the user at `ticket-build` once the plan looks right — and remind them the plan is editable; a plan they disagree with is cheaper to fix now than after implementation.
