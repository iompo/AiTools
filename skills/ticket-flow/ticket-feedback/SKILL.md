---
name: ticket-feedback
description: Read the unresolved human review comments on a ticket's GitLab merge request, analyse each one against the current code, and write a numbered list of proposed fixes with explanations that the user picks from one at a time. Use whenever the user wants to deal with what a reviewer said on the MR — e.g. "read the MR comments for PROJ-123", "what did the reviewer ask for", "go through the GitLab review comments", "the reviewer left notes on the MR", "check if the comments are resolved by the current code". This is the FIFTH phase of the ticket workflow and closes the loop back into ticket-build: it proposes and explains, it never edits code, never commits, and never posts to GitLab. If the user instead wants findings that are already written down to be applied, that is ticket-build's fix mode.
---

# ticket-feedback

Turn the open reviewer threads on the ticket's merge request into a numbered, explained set of proposals in `.dev/mr-comments/<KEY>.md`, so the user chooses which to apply. **Propose and explain only — no code edits, no commits, nothing posted to GitLab.** `ticket-build` fix mode applies the numbers the user picks. The ledger shape is the same as `ticket-review`'s on purpose: IDs plus `Resolution:` lines, so one mechanical check covers both sources.

A human comment carries authority, which is the hazard: a question answered with a patch becomes an unrequested behaviour change; correct code "fixed" to please a reviewer gets worse; a design objection absorbed as a local workaround leaves the design contradicting itself. So this phase reads, verifies, classifies and proposes.

## Steps

1. **Identify the MR**: the open MR whose source branch is `<KEY>` (or the IID the user names). Record IID, URL, head sha, target branch.

2. **Fetch the threads.** If `.dev/mr-comments/<KEY>.md` exists, read its `Fetched: … via <channel>` line and **use that channel directly** — don't re-probe. Otherwise try in order and record which worked:
   - a GitLab connector authenticated for *this* host (self-hosted instances are common; verify it returns this project);
   - `glab api "projects/:id/merge_requests/<iid>/discussions?per_page=100"` (full thread structure; `glab mr view --comments` flattens it);
   - REST: `curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_HOST/api/v4/projects/<url-encoded-path>/merge_requests/<iid>/discussions?per_page=100"`, paging until short. **No token in the environment → ask for it** (`! export GITLAB_TOKEN=…`); never read `.env`, keychains or dotfiles for one, never echo it;
   - last resort: ask the user to paste the threads (author, file, line, text) and say plainly the API was unreachable.

   Per note capture: discussion id, author, timestamp, resolved flag, file and line, anchored sha, whether replied. **The discussion id is the identity across re-runs.**

   **Filter before analysing.** A thread is resolved when every `"resolvable": true` note is `"resolved": true`; `"resolvable": false` notes (MR-level comments) are always open. Drop resolved threads, system notes, the MR description and bot/CI comments into `## Filtered out` with `resolved_by`. With `glab`/REST, filter the payload:

   ```bash
   jq '[ .[] | select(any(.notes[]; .system | not))
             | select([ .notes[] | select(.resolvable) | .resolved ] | (length == 0 or any(. == false))) ]'
   ```

   A pasted dump has no flags: ask which threads are resolved. Include resolved threads only on explicit request, marked `resolved-on-gitlab`.

3. **Anchor every open comment to the code as it is now.** Open the file at HEAD and establish: **still applies** (record the *current* `file:line`), **already addressed** (name the sha; it still needs a reply), or **outdated**. Never trust the API's line number.

4. **Classify** before proposing: **defect** (blocking) · **improvement** (should-fix) · **question** (deliverable is a drafted reply; reclassify as defect if the answer is "you're right") · **preference / nitpick** · **design objection** (the proposal is a *plan* change; never a local patch) · **reviewer is mistaken** (say so with evidence and draft a reply; **never propose a code change to end an argument**).

   Classification is a claim about the code: reproduce it, read the caller, run the command. An asserted absence ("no test for this", "nothing calls this") is checked with a repo-wide search. **Verify against the repo first**; fetch upstream library or framework sources only when the classification genuinely hinges on their behaviour, and say so — one fetch, not an afternoon.

5. **Merge and split before numbering**: several comments with one cause → one finding listing every thread (note the convergence); one comment demanding independent changes → several findings; inseparable changes stay one finding.

6. **One proposal per finding**, carrying enough to decide: **what changes** (files and shape, at `file:line` you read); **why it answers the comment**; **what proves it** (test and command, or `requires-manual-run` with the steps); **what it risks**; **effort** (line | file | redesign); an alternative in one sentence where one genuinely exists.

7. **Cross-check against the plan.** If the fix contradicts the plan's Design, a Clarification, the task list or a criterion, set `plan-impact:` naming the section and change — `ticket-build` edits the plan only if told what moved. A design objection always has plan impact. A comment that shows a criterion is wrong is bigger than this MR: say so and offer to draft the Jira comment.

8. **Draft a reply per thread, never posted** — two or three sentences for the colleague who wrote it. *Reviewer mistaken*, *already addressed* and *question* threads need it most.

9. **Write the artifact** (template below) after confirming `.dev/` is git-excluded (`git check-ignore -q .dev`; else append `.dev/` to `.git/info/exclude` under `# ticket-flow workflow artifacts (local only)`) — this phase can be the first run in a fresh clone.

   **Re-runs are idempotent.** Match by discussion id; keep every existing number and `Resolution:` exactly; append new threads with the next numbers; mark findings whose thread was resolved upstream `resolved-on-gitlab` and drop them from the actionable list. **Never renumber.**

   **Resolutions the user decides here are recorded here.** Many `H*` findings never reach `ticket-build` (reply-only, won't-do, already addressed). When the user says "waive H13", "H15 ignore it", "H8 answered on my own", write `Resolution: waived — <reason>` / `answered — reply posted by user` / `already addressed <sha>` directly; it is the ledger, not a code edit. When asked "are all comments fixed?", answer from the ledger mechanically: every open `H*` with an empty `Resolution:` listed, or "none open".

10. **Present compactly and stop.** One line per open finding: ID, severity, current `file:line`, the fix in a clause, **`code` or `reply-only`**, and `plan-impact` where set. Blocking first; `resolved-on-gitlab` omitted. Don't paste the artifact. Then wait — no applying, no pre-picking "the obvious ones".

11. **Hand off.** The user picks numbers → `ticket-build` fix mode (one `B` per cycle, batches for the rest), which fills `Resolution:` here. Afterwards: pushing updates the existing MR (don't open a second one); update the MR description by hand if its claims changed; a fix batch across layers deserves `ticket-review` scoped to the fix commits.

## Artifact template

```markdown
# <KEY> — MR review comments
MR: !<iid> <url> → <target branch>
Branch head at analysis: <sha>
Fetched: <ISO timestamp> via <connector | glab | REST | pasted by user>
Threads: <n> total — <n> open analysed, <n> resolved skipped, <n> system/bot filtered

## H1 — <blocking|should-fix|question|nitpick|design-objection|reviewer-mistaken> — <code|reply-only> — @<author>, thread <id>
> <the comment, verbatim>
Anchored: <file>:<line> — <still applies | already addressed by <sha> | outdated>
plan-impact: <none | Design: … | Clarifications: … | Acceptance criteria: …>
Analysis: <what you verified and how>
Proposed fix: <files and shape, at file:line>
Why it answers the comment: <…>
Proof: <test/command — or requires-manual-run: steps>
Risk: <…>  Effort: <line | file | redesign>
Alternative considered: <one sentence, or omit>
Draft reply (NOT posted): <2-3 sentences>
Resolution:

## Converged
- <finding several reviewers raised independently, and who>

## Filtered out
- <thread id> — <resolved upstream by @who | system note | bot> — <one line>
```

## Boundaries

No code edits, no commits, no pushes, nothing posted or resolved on GitLab, no Jira transitions. Never stage or `git add -f` anything under `.dev/` — this file quotes colleagues verbatim. Don't apply a fix "while you're in there". Don't resurrect a resolved thread as a finding; note the disagreement under `## Filtered out`. No open comments → say exactly that.
