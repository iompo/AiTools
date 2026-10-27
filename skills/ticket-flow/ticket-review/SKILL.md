---
name: ticket-review
description: Adversarially review a ticket's implementation against its plan and acceptance criteria. Use whenever the user wants a code review, wants to check a branch or diff before opening a merge request, or asks "does this actually satisfy the ticket" — e.g. "review PROJ-123", "review this branch", "check the diff before I open the MR". This is the THIRD phase of the ticket workflow and works best run in a FRESH conversation, so the reviewer sees only the plan, the acceptance criteria, and the diff — not the reasoning that produced them.
---

# ticket-review

Review the implementation with fresh, adversarial eyes: only the artifacts, never the implementer's justifications. Find what is wrong before a human or CI does.

## Enforce fresh context mechanically

Run the analysis as subagents whose prompts contain only the inputs below plus the checklist — nothing from the implementing conversation, no hints about what you suspect. Use **two or three reviewers with distinct lenses** (e.g. primary subsystem changed; tests and security; "does this fix the reported bug and match the plan"): each lens finds things the others miss, and independent convergence is a confidence signal. The parent's jobs are assembling inputs, adjudicating and writing the review file.

Where subagents aren't available, use a genuinely new conversation. Reviewing code you wrote in this same conversation with no subagent: say so, review anyway, and mark the file `Context: same-session (weaker)`.

## Inputs — assembled once by the parent, passed by path

Reviewers used to end at 350k+ tokens of context each because every one re-read the whole plan and the whole branch diff and re-ran every suite. Keep them small:

1. **Plan contract**: `.dev/plans/<KEY>.md` — design, acceptance criteria, tasks, clarifications. **Not** `.dev/build/<KEY>.md`: the build log is the implementer's narrative and must not reach a reviewer.
2. **Acceptance criteria**: from the plan, re-fetching the Jira ticket (`Atlassian:getJiraIssue`) in case it changed.
3. **Diff, scoped per lens**: `git fetch origin`, then `git diff origin/<default>...<branch> -- <paths of that lens>` written to a file per lens, plus `--stat` of the whole branch for orientation. Only the "fix matches plan" lens gets the full diff. Diffing against a stale local base reviews changes that aren't there.
4. **Test and build results**: the parent runs the plan's test and build commands **once**, at the shipping commit with a verified-clean tree (`git status` and `git diff HEAD` empty), and writes exit status, counts and sha to a file. Reviewers do **not** re-run suites or builds; they run targeted mutations only, on the files of their lens, each in its own worktree (`isolation: "worktree"`; if unavailable, one at a time with the tree verified restored between them).
5. **Orientation block**: neutral structural facts only — module layout, entry points, where the platform matrix is documented. No conclusions, no suspicions, no "check X".

**Record each reviewer's cost.** The Agent tool reports tokens per subagent (`subagent_tokens`); write them on the review's `Reviewer cost` line. The reviewers share the same start-up overhead, so compare them with each other: one well above the rest → name its oversized input on the same line (its diff file's `wc -l`, a suite it re-ran, a file it read whole) — that is the input to shrink next time. The budget itself is judged by `ctx-report.py`.

**Recorded decisions are passed as claims to test, not as context.** The plan carries the implementer's reasoning: priced defences, residues "deliberately not handled (user decision)", waived lines. State each neutrally in the reviewer prompt — "verify: how is this case reached, how likely, what happens if nothing handles it" — never as settled. A reviewer told the answer confirms it; a reviewer given the question checks it.

## What reviewers check

- **Acceptance criteria, one by one**: point to the code that satisfies each. No corresponding change → blocking. Distinguish *satisfied* from *demonstrated*: a `requires-manual-run` criterion nobody executed is unproven, and blocking if it is the one the ticket exists for.
- **Every platform, mode and environment the repo supports** (from the repo's own docs): shell invocation, path separators, filesystem semantics, container behaviour.
- **Edge cases and failure modes**: empty/null, boundaries, concurrency, partial failure, timeouts, retries.
- **Error handling and cleanup**: swallowed errors; connections, files, locks released on every path.
- **Secrets and config**: no credentials in code or ConfigMaps.
- **Test quality, not presence**: do tests exercise the plan's risky paths; would they fail on regression; fixture-establishes-what-the-assertion-checks tautologies; a name that contradicts its assertion (worse than no test); mocked collaborators asserted as if real; magic-count event-loop drains; race-condition tests in integration suites. Ask what has *no* test: if the change's central line could be reverted with the suite green, say so.
- **Consistency**: existing conventions, the plan's design, undocumented deviations. **Invented vocabulary** — a name with no root in the ticket or codebase — is a finding.
- **Cold-reader check on tracked files**: comments, READMEs, CLAUDE.md that reference plan jargon, finding IDs, guard numbers or `.dev/` paths, or need context the file doesn't give.
- **Recorded decisions are claims**: *left unhandled* — is the window really that narrow, reached only that way, with the stated recovery actually existing? Find the caller. *Built* — reachable from a real caller, and proportionate? Complexity with no reachable case is a finding; so is a mechanism the plan never priced. "The user decided" answers neither — the user decided on what they were told. Do not re-argue a decision whose inputs you checked and found true; record it under *Verified fine*.

## Adjudicate before you record

Reviewer output is evidence, not verdict.

- **Verify every blocking finding yourself** — run the command, read the file, check the caller. A false blocker costs a fix cycle and can push the implementer into "fixing" correct code.
- **Reaching the mechanism is not reaching the state.** A probe that drives internals proves the state is expressible; trace it from real callers. Say which you established: "reached from `<caller>`" or "mechanism only, no caller found".
- **Disagreement**: check the claim against the code, record the finding with its actual scope, note the disagreement — usually the finding is real but conditional.
- **Deduplicate**, keeping the convergence note. **Divergence is not evidence of absence**: the finding one lens raised is the one most needing your verification. Check the mechanism, never the vote count.
- **Severity follows the deliverable, not the patch size.** A one-line flaw in the thing the ticket exists to produce is a correctness finding.

## Output — `.dev/reviews/<KEY>.md`

```markdown
# <KEY> — review
Diff: origin/<default>...<branch> @ <branch HEAD sha>
Tests at shipping commit: <command> exit <n> (<count>)   Build: <command> exit <n>
Context: subagent (<n> reviewers, lenses: <...>) | fresh-session | same-session (weaker)
Reviewer cost: <lens> <n>k · <lens> <n>k · <lens> <n>k (one well above the rest → <oversized input>)

## Blocking (must fix before MR)
- B1: <file>:<line> — <problem> — <concrete failure scenario> — <reached from <caller> | mechanism only>
  <convergence or disagreement note>
  Resolution:

## Should fix
- S1: ...
  Resolution:

## Nitpick / optional
- N1: ...
  Resolution:

## Suggested fix batches
<!-- ticket-build works S/N in these batches, one approval cycle each; B always one per cycle -->
- Batch 1 (same file/concern): S1, S3, N2
- Batch 2: N1, N4, N5

## Acceptance criteria check
- [x] AC1 — satisfied by <file>, demonstrated by <test/command>
- [ ] AC2 — satisfied by <file> but NOT demonstrated (requires-manual-run, unexecuted)
- [ ] AC3 — NOT addressed → B<n>

## Verified fine (recorded so it is not re-derived)
- <plan entry or suspicious thing checked, with the conclusion>
```

Every finding has an ID and an empty `Resolution:` line — the ledger `ticket-build` fills (`fixed <sha> — <subject>`, `waived — <reason>`, `escalated — <question, owner>`; escalated is still open). The file stays local and uncommitted; human reviewers learn about waived findings from the MR description.

## Handing the branch off for a merge request

Opening the MR is the user's action. Before saying "ready", confirm mechanically and report any failure:

- Tests and build green at the exact shipping commit with a clean tree (the parent's run above).
- Every blocking finding has a non-empty `Resolution:` in `.dev/reviews/<KEY>.md` and, if present, `.dev/mr-comments/<KEY>.md`. A verbal "it's handled" does not count.
- Every `requires-manual-run` criterion executed by a human, with the plan's *Verification status* saying so.

Then give the user the MR description material, since the artifacts never reach a reviewer: what changed and why, commands run and what they proved, what was not verified and why, **every waived blocking finding quoted verbatim with its reason**, and every case the plan priced and left unhandled with its likelihood and recovery. Keep the Jira key in branch, commits and MR title.

## Boundaries

Do not fix issues here. Hand findings to `ticket-build` (fix mode). A fix pass across several findings or layers gets a proper re-review with fresh reviewers, scoped to the fix commits plus anything waived; point the test-quality traps at the tests the fix pass wrote. Re-run the decisive test at the exact shipping commit with a verified-clean tree. If a class of defect keeps surfacing here (platform coverage, untested glue, undemonstrated criteria), propose a question for `ticket-plan`'s gate — a defect caught at design costs a paragraph.
