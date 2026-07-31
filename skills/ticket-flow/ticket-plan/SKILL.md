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

5. **Clarification gate — ask, don't assume.** This is a hard rule for this phase: **do not resolve any remaining ambiguity by picking an interpretation yourself.** Collect everything still open from steps 2-4 into a single structured question round and put it to the user before designing anything:
   - Number each question, state why it matters (what changes in the design depending on the answer), and — where you can — offer the plausible options so the user can answer fast.
   - Batch them: one round of questions beats a drip-feed. Only ask a second round if an answer genuinely opens a new question.
   - If the user explicitly answers "you decide" or "doesn't matter" to a question, only then may you choose — and you record the choice AND that it was delegated.
   - If the ticket is missing information only its author or a stakeholder can supply, say so plainly and offer to draft the Jira comment asking for it (`Atlassian:addCommentToJiraIssue`) — don't design around the hole.
   - If, unusually, steps 2-4 leave nothing open, say that explicitly ("no open questions — the ticket plus the codebase answer everything") rather than inventing questions to appear thorough.

   Every answer gets recorded in the plan's **Clarifications** section: question, answer, who decided. The plan must be executable by someone who never saw this conversation, so the answers live in the artifact, not the chat scrollback. A plan containing an unstated assumption is a planning bug, exactly like a hardcoded secret is a coding bug.

6. **Design.** Propose the approach. Name at least one alternative and why you rejected it. Call out risky assumptions and anything that could ripple (schema changes, API contracts, config/secrets, migration). Keep it to the decisions — no line-by-line code.

7. **Break into ordered tasks** with dependencies. Each task should be independently verifiable and small enough to review. Order them so the branch stays green after each.

8. **Test strategy.** For each risky path, say what to test and at what level (unit / integration). Name the concrete command (`./gradlew test`, or the specific module task like `./gradlew :rombox-gym:test`). Define what "done" means beyond "it compiles".

9. **Write the artifact** to `.dev/plans/<KEY>.md` using the template below, then **make sure `.dev/` is git-excluded before anything in this workflow touches git.** Run `git check-ignore -q .dev`; if it doesn't match, append to the target repo's `.git/info/exclude`:

   ```
   # ticket-flow workflow artifacts (local only)
   .dev/
   ```

   `.git/info/exclude` rather than `.gitignore` because that file is itself per-clone and never committed — the workflow leaves no trace in the team's repo, and `.dev/` is invisible to `git add -A`, to reviewers, and to the MR diff. Doing this now, before a branch exists, is what keeps every later commit clean.

   The consequence is worth stating: the artifacts live only in this working tree. A fresh session **on this machine** can pick up mid-workflow by reading them; a different machine or a different clone cannot — there, re-run `ticket-plan` or copy the file across by hand.

10. **Gate the plan before handing it off.** Spawn a subagent (the Task tool in Claude Code) whose prompt contains *only* the raw ticket text and the plan file — none of this conversation — and ask it exactly four questions:
   - For each acceptance criterion, which part of the design satisfies it? Name any criterion with no answer.
   - What is the most likely failure mode of the chosen approach?
   - Is anything in the plan untestable as specified?
   - Does the design rely on any interpretation of the ticket that is NOT recorded in the Clarifications section? (A smuggled assumption is a blocking finding.)

   Fold blocking answers back into the plan before finishing. This is the cheapest review in the whole workflow — a design flaw caught here costs a paragraph edit; the same flaw caught at code review costs a rewrite. If subagents aren't available, ask the user to run these three questions in a fresh conversation against the plan file.

11. Give the user a 4-6 line summary in chat, the gate's findings, and any open questions.

## Plan template

```markdown
# <KEY> — <ticket title>
Jira: <link>

## Problem
<one paragraph, your words>

## Acceptance criteria
- [ ] ...

## Design
<approach, chosen over <alternative> because ...>
Affected: <files / components>
Risky assumptions: <...>

## Tasks
1. [ ] TASK-01 — <what> (depends on: none)
2. [ ] TASK-02 — <what> (depends on: TASK-01)

## Test strategy
- <path/behaviour> → <unit|integration>, run with `<command>`
- Done when: <criteria beyond compiling>

## Clarifications
<!-- every ambiguity found in analysis, with its resolution — no unstated assumptions allowed -->
- Q1: <question> → <answer> (decided by: user | ticket author via Jira comment | delegated to Claude by user)
- <or: "No open questions — ticket + codebase answered everything.">

## Ticket gaps flagged, not blocking
- <things the ticket doesn't cover that were deemed out of scope, so nobody rediscovers them later>

## Plan gate
- <finding from the gated review, and how the plan was adjusted — or "no blocking findings">
```

## Boundaries

Do not create a branch, write production code, or touch Jira status here. Never stage, commit, or `git add -f` anything under `.dev/` — it is a local scratch folder in every phase of this workflow, and force-adding it defeats the exclude entry step 9 just wrote. Do not design past an unanswered blocking question — waiting on the user is the correct behavior in this phase, not a failure to make progress. End by pointing the user at `ticket-build` once the plan looks right — and remind them the plan is editable; a plan they disagree with is cheaper to fix now than after implementation.
