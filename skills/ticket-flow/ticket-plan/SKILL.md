---
name: ticket-plan
description: Turn a Jira ticket into a technical plan before any code is written — including a systematic hunt for what the ticket does NOT say. Use whenever the user wants to plan, scope, design, analyze, or "figure out how to build" a Jira issue — e.g. "plan PROJ-123", "analyze this ticket", "how should we approach this", "break this issue into tasks". This is the FIRST phase of the ticket workflow: it interrogates the ticket for gaps and ambiguities, asks the user instead of assuming, and produces a durable plan artifact that ticket-build later executes. Trigger even when the user just pastes a Jira key and says "let's start", since starting well means planning first.
---

# ticket-plan

Produce a technical plan from a Jira ticket: design, tasks and test strategy, written to `.dev/plans/<KEY>.md`. **No production code in this phase.** The plan is a contract that a fresh agent executes without re-deriving the thinking (the README explains why the phases are separate).

## The plan is a contract, not a journal

`.dev/plans/<KEY>.md` holds only what later phases check against: status, criteria, design, tasks, test strategy, clarifications, gate result. **Keep it under ~250 lines.** Evidence, run records, by-hand procedures and build notes go to `.dev/build/<KEY>.md` (written by `ticket-build`), never into the plan. Every phase re-reads the plan, and every reviewer gets a copy; a plan that doubles as a log costs tens of thousands of tokens per session and buries the contract.

## Reading budget

Applies to every step below. Outline before reading: `grep -n` for headings, signatures and the symbols you need, then read only the ranges that matter. Never read more than ~200 lines of a file without a line range, and never `cat` a whole file to "get a feel for it". Use the Read and Grep tools over Bash `cat`/`rg` where available — their output is capped. Use subagents for breadth (where things live, what conventions exist: `file:line` plus a one-line characterization, **never** verbatim dumps), then read the two or three load-bearing files yourself. Never sleep-poll a subagent: launch it, do non-overlapping work or end the turn.

## Steps

1. **Fetch the ticket** (`Atlassian:getJiraIssue`, or `searchJiraIssuesUsingJql` from a description): description, acceptance criteria, comments, linked issues.

2. **Restate the problem** in one short paragraph — the outcome wanted and why. List the acceptance criteria explicitly; if the ticket has none, derive candidates and flag that you did.

3. **Interrogate the ticket for gaps.** Note what it does NOT say about: scope edges (is adjacent Y bundled with "fix X"?); acceptance-criteria quality (testable, or "should be faster"?); unhappy paths (invalid input, timeout, partial failure); data and compatibility (migration, contract consumers, backwards compatibility); non-functionals (performance, security, resources); environment (which configs, feature-flagged or not); dependencies (another ticket, a team decision, an external system).

4. **Read the code, don't imagine it.** Explore the affected modules, existing patterns and neighbouring tests; name the real files the change touches. Anything the codebase already answers (a convention, a config that dictates the choice) is answered here and noted — never forwarded to the user as busywork.
   - **Local state too**: untracked config, credentials, a database, a running container — look at the real artifact's **shape, not its contents** (key names, mount points, table names; values redacted).
   - **Reusing an existing call in a new role?** Read its return contract — documented semantics, and the implementation if the docs are thin. Prior correct use elsewhere proves nothing about the new use.

5. **Clarification gate — ask, don't assume.** Collect everything still open from steps 2-4 into **one** numbered round before designing anything. For each question: why it matters (what changes in the design), and the plausible options so the user can answer fast. A second round only if an answer opens a new question.
   - You may choose only when the user says "you decide" / "doesn't matter" — and you record both the choice and that it was delegated.
   - Information only the ticket author can supply: say so and offer to draft the Jira comment (`Atlassian:addCommentToJiraIssue`); don't design around the hole.
   - Nothing open? Say "no open questions — ticket plus codebase answer everything" rather than inventing some.
   - **Vocabulary is a clarification item.** Every name the design introduces (class, concept, event, state) must derive from a term in the ticket or the codebase. A term found in neither is proposed here with alternatives; it is never coined silently. Invented words ("gate", "arm") have cost whole review rounds.

   Every answer goes in the plan's **Clarifications** section (question, answer, who decided). An unstated assumption in a plan is a bug, like a hardcoded secret in code.

6. **Design.** The approach, at least one rejected alternative and why, risky assumptions, and what ripples (schema, contracts, config/secrets, migration). Decisions only — no line-by-line code. Three rules on how it is written down:
   - **Decision tables go over the predicates the code will evaluate, not prose state names.** Prose silently merges states the code must keep apart ("nothing to look at" vs "something, none matched").
   - **If the change makes one class or member the odd one out among its siblings, follow the sibling convention or write down why not.** The usual fix is the missing declaration, not a workaround at one call site.
   - **Write down the invariants the design leans on that the code does not state** — an order of calls, a precondition established elsewhere — naming the caller that guarantees it and the ordering that would break it. Otherwise a reviewer files a defect for a state no caller can produce.

   **Price every defensive mechanism and let the user decide.** For each retry, fallback, catch-up pass, lock, reconciliation loop or cache: **how the case is reached**, **how likely it is**, **what happens if nothing handles it**. Put it in the clarification round with a recommendation; **do not decide in either direction.** The decision is recorded as designed-in or as a known residue under *Ticket gaps flagged, not blocking* with its likelihood and recovery. Unpriced defences arrive with their own tests, failure modes and maintenance.

7. **Break into ordered tasks** with dependencies; each independently verifiable, small enough to review, and the branch green after each. No standalone "write the tests" task — tests belong to the task they cover. Two tasks that cannot be split without an inconsistent intermediate state are one task.

8. **Test strategy.** Per risky path: what to test, at which level, and the concrete command, scoped as narrowly as still covers the change. Name the build/compile command separately (a green suite is not proof it compiles). Every bound, cap or truncation the design introduces needs a named test at its boundary. Tag **every** acceptance criterion as **demonstrable-by-test** (name the test or command) or **requires-manual-run** (say exactly what a human has to do). `ticket-build` may not report completion with a manual criterion unexecuted; if the criterion the ticket exists for is manual, lead with that in the chat summary.

9. **Write the artifact** to `.dev/plans/<KEY>.md` (template below), then ensure `.dev/` is git-excluded: `git check-ignore -q .dev`; if it fails, append to `.git/info/exclude`:

   ```
   # ticket-flow workflow artifacts (local only)
   .dev/
   ```

   Per-clone and never committed, so the workflow leaves no trace in the repo; the trade-off is that artifacts live only in this working tree. **In harness plan mode**, write to the harness path and, once edits are permitted, copy the same content to `.dev/plans/<KEY>.md` — the phase is not done until that file exists.

10. **Gate the plan.** Spawn a subagent whose prompt contains **only** the raw ticket text and the plan path — none of this conversation — with exactly these questions:
    - For each acceptance criterion, which part of the design satisfies it? Name any with no answer.
    - What is the most likely failure mode of the chosen approach?
    - Is anything untestable as specified?
    - Does the design rely on an interpretation of the ticket not recorded in Clarifications? (A smuggled assumption is blocking.)
    - Does the design hold on every platform, mode and environment the repo supports (check the repo's own docs for the matrix)? Shell invocation, path separators, container and filesystem semantics are the usual offenders.
    - Does the plan contradict itself? Name two statements that cannot both be true.
    - Does any mechanism cost more than the case it handles? Flag every one whose case the plan never states.

    Fold blocking answers back **after verifying each against the code** — the gate can report intended behaviour as a defect, and a finding that asserts an absence ("nothing tests this", "no caller") is verified by a repo-wide search, not by opening one file. Note what you rejected and why. Record in *Plan gate* which version the gate read (sha or file timestamp); **re-gate the changed sections** after any material change (a reversed clarification, a reshaped decision table, a new error path or contract, a swapped mechanism). If subagents are unavailable, ask the user to run the questions in a fresh conversation.

11. **Chat summary**: 4-6 lines, the gate's findings, open questions. Point the user at `ticket-build` and remind them the plan is editable — cheaper to fix now than after implementation.

## Plan template

```markdown
# <KEY> — <ticket title>
Jira: <link>
Status: planned | building TASK-nn | in review | fixing findings   Branch: <KEY>   Last commit: <sha or none>
Open findings: <n blocking / n should-fix> in .dev/reviews, <n> in .dev/mr-comments   Build log: .dev/build/<KEY>.md

## Problem
<one paragraph, your words>

## Acceptance criteria
- [ ] AC1 <criterion> — *demonstrable-by-test*: <test or command>
- [ ] AC2 <criterion> — *requires-manual-run*: <exactly what a human must do>

## Design
<approach, chosen over <alternative> because ...>
Affected: <files / components>
Vocabulary: <each new name → the ticket/codebase term it derives from>
Risky assumptions: <...>
Invariants relied on: <invariant → guaranteed by <caller> → broken by <ordering>>
Defences priced: <mechanism → case → likelihood → without it → build or leave, decided by>
Platforms / modes checked: <where reasoned through, where not>

## Tasks
1. [ ] TASK-01 — <what> (depends on: none)
2. [ ] TASK-02 — <what> (depends on: TASK-01)

## Test strategy
- <path/behaviour> → <unit|integration>, run with `<command>`
- Build/compile command: `<command>`
- Done when: <criteria beyond compiling>

## Verification status
<!-- one line per criterion, maintained by ticket-build; evidence lives in the build log -->
- AC1: demonstrated by <test/command> | not demonstrated

## Clarifications
- Q1: <question> → <answer> (decided by: user | ticket author | delegated)

## Ticket gaps flagged, not blocking
- <out-of-scope things, and priced residues with likelihood and recovery>

## Plan gate
- Gate read: <sha or timestamp>; re-gated after: <changes, or "none">
- <finding and adjustment — or "no blocking findings">
```

## Boundaries

No branch, no production code, no Jira status change. Never stage, commit or `git add -f` anything under `.dev/`. Do not design past an unanswered blocking question — waiting on the user is correct here. Do not put evidence or run records in the plan; that is `ticket-build`'s log.
