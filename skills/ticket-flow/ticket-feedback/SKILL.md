---
name: ticket-feedback
description: Read the human review comments on a ticket's GitLab merge request, analyse each one against the current code, and write a numbered list of proposed fixes with explanations that the user picks from one at a time. Use whenever the user wants to deal with what a reviewer said on the MR — e.g. "read the MR comments for PROJ-123", "what did the reviewer ask for", "go through the GitLab review comments", "the reviewer left notes on the MR". This is the FIFTH phase of the ticket workflow and closes the loop back into ticket-build: it proposes and explains, it never edits code, never commits, and never posts to GitLab. If the user instead wants findings that are already written down to be applied, that is ticket-build's fix mode.
---

# ticket-feedback

Turn the reviewer comments on an open GitLab merge request into a numbered, explained set of proposed fixes in `.dev/mr-comments/<KEY>.md`, so the user can choose which ones to apply and in what order. **Propose and explain only — no code edits, no commits, no replies posted to GitLab.** `ticket-build` in fix mode applies whichever numbers the user picks.

## Where this sits

```
ticket-plan → ticket-build → ticket-review → you open the MR
                   ▲                                    │
                   │                        human reviewers comment
                   │                                    │
                   └──────── ticket-feedback ◄──────────┘
                             (this skill: read, analyse, propose, number)
```

It is the same fix loop `ticket-review` feeds, with a different source of findings. The ledger shape is identical on purpose: IDs plus an empty `Resolution:` line, so `ticket-build` needs no new machinery and the same mechanical check — every blocking finding has a filled `Resolution:` — covers both sources before you re-request review.

## Why this phase is separate — and why it does not fix anything

A human reviewer's comment carries authority that a subagent finding does not, and that authority is exactly the hazard. Three failure modes follow from acting on comments directly:

- **Patching a comment that was a question.** "Why does this retry twice?" is a request for an answer. Answering it with a code change is how a reviewer's curiosity turns into an unrequested behaviour change nobody signed off on.
- **"Fixing" correct code to please a reviewer.** Reviewers are wrong sometimes — about intended behaviour, about a convention this repo deliberately departs from, about code that a later commit already changed. Deference produces a patch that makes the code worse and the reviewer none the wiser.
- **Accepting a design objection as a code fix.** When a comment disputes the *approach*, the change belongs in the plan first. Bolting a local workaround onto the site the reviewer happened to be reading leaves the rest of the design contradicting itself.

So this phase reads, verifies, classifies and proposes. Judgement about which proposals to accept is the user's, one at a time, which is why every finding is numbered and independently actionable.

## Steps

1. **Identify the MR.** The branch is the Jira key (`ticket-build` names it that way), so find the open MR whose source branch is `<KEY>`. If several match, or the user names an MR/IID explicitly, use that. Record the MR IID, its web URL, its current head sha, and the target branch — the artifact header needs all four, and the head sha is what "still applies" is judged against.

2. **Fetch the threads, through whichever channel actually works here.** Try in order and say which one you used, because they differ in what they return:
   - **The GitLab connector**, if this session has one authenticated for *this* host. Self-hosted instances are common; a connector configured for gitlab.com will not see `gitlab.<company>.net`. Verify it returns this project rather than assuming.
   - **`glab`**, if installed and authenticated: `glab api "projects/:id/merge_requests/<iid>/discussions?per_page=100"` returns the full thread structure, which `glab mr view --comments` flattens and partly loses.
   - **The REST API directly**: `curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_HOST/api/v4/projects/<url-encoded-path>/merge_requests/<iid>/discussions?per_page=100"`. Page until the result is short — a long review overflows one page and the comments that fall off are silently the newest ones.
     **If no token is in the environment, ask for it; do not go looking.** Never read `.env`, keychains, dotfiles or credential stores to find one — hand the user the one line to run in this session instead (`! export GITLAB_TOKEN=…`), and never echo the variable back into the transcript.
   - **Last resort: ask the user to paste the threads.** Say plainly that you could not reach the API and what you need — author, file, line, and text per comment. A pasted dump analysed honestly beats a fabricated fetch.

   Whatever the channel, capture per note: **thread (discussion) id, author, timestamp, resolved flag, file path and line, the sha the comment was anchored to, and whether the thread already has replies.** The thread id is the identity this artifact is keyed on across re-runs; without it, a second run cannot tell a new comment from one you already processed.

   Filter out what is not review feedback: system notes (label/assignee/pipeline events), the MR description itself, bot and CI comments, and — by default — threads already marked resolved. Say how many you filtered and why, so a reviewer's point that was auto-resolved by a force-push does not vanish without trace. If the user asks for resolved threads too, include them marked as such.

3. **Anchor every comment to the code as it is now, before analysing it.** A comment is pinned to the sha it was written against, and the branch has usually moved since. For each one, open the file at the current HEAD and establish which of these is true:
   - **Still applies** — the code the comment describes is there, at that line or wherever it moved to. Record the *current* file:line, not the one the API returned.
   - **Already addressed** — a later commit changed it. Name the sha. This is a real outcome, not a way to duck the comment: it still needs a reply telling the reviewer where it was handled.
   - **Outdated** — the code the comment refers to no longer exists in any form.

   Do this by reading the file, never by trusting the API's line number. A stale anchor is how a proposal ends up describing a fix to a line that now contains something else entirely.

4. **Classify each comment before proposing anything.** "Propose a fix for each comment" is the goal, but a fix is only the right response to some of these:
   - **defect** — the code is wrong. Blocking.
   - **improvement** — the code works, the reviewer wants it better. Should-fix.
   - **question** — wants an answer, not a patch. The deliverable is a drafted reply. If the answer turns out to be "you're right, that is a bug", reclassify it as a defect and say that it started as a question.
   - **preference / nitpick** — style, naming, ordering with no behavioural consequence.
   - **design objection** — disputes the approach the plan chose. The proposal is a *plan* change, and any code fix is downstream of it. Never absorb one of these as a local patch.
   - **reviewer is mistaken** — you checked and the code is right. Say so, with the evidence that shows it, and draft a reply. **Do not propose a code change to close a comment you believe is wrong**; a patch written to end an argument is worse than the argument.

   Classification is a claim about the code, so it needs the same verification a `ticket-review` blocking finding does: reproduce it, read the caller, run the command. **A comment asserting an absence — "there's no test for this", "nothing calls this", "this config is never read" — is checked with a repo-wide search, not by opening the file the comment sits in.**

5. **Merge and split before numbering.** The numbering is what the user acts on, so it has to match the units of work, not the units of typing:
   - Several comments pointing at one underlying cause become **one** finding, listing every thread it answers. Two reviewers hitting the same line is strong evidence it is real — note that convergence.
   - One comment demanding several independent changes becomes **several** findings, so the user can take one and decline another.
   - Two changes that cannot land separately without leaving the tree incoherent stay **one** finding, for the same reason `ticket-plan` merges inseparable tasks.

6. **Propose exactly one fix per finding, and explain it.** The explanation is the deliverable — the user is deciding from it, so it has to carry enough to decide with. Each proposal states:
   - **What changes**, concretely: the files and the shape of the edit, named at `file:line` you have actually read. A proposal you cannot anchor to real code is a guess; mark it as one or go read the code.
   - **Why it answers the comment** — connect the edit back to what the reviewer actually asked for, not to a more convenient adjacent problem.
   - **What proves it** — the test to add or change, and the command that runs it. If the comment concerns something the suite cannot reach (packaging, a platform, a container), say `requires-manual-run` and what a human has to do, in the same vocabulary the plan uses.
   - **What it risks** — what else the edit touches, which callers move, whether it can ripple into another criterion.
   - **Effort**, roughly: a line, a file, or a redesign. A one-line fix and a two-day one should not look identical in a numbered list the user is triaging.

   Where a comment has a genuinely better alternative fix, give the alternative in one sentence and say why you chose the one you did — the reviewer may prefer the other, and this is cheaper to raise now than after it is committed.

7. **Cross-check every proposal against the plan, and mark the ones that move it.** This is what keeps `.dev/plans/<KEY>.md` honest across the loop. For each finding, ask whether the fix contradicts the plan's Design, one of its recorded Clarifications, its task list, or its acceptance criteria. If it does, set `plan-impact:` on the finding and name **which section changes and how** — `ticket-build` makes the edit when it applies the fix (its step 4), but it only does so if this phase told it what moved. A design objection (step 4) always has plan impact by definition; so does any fix that changes a behaviour an acceptance criterion asserts.

   If a comment reveals that an acceptance criterion itself is wrong or missing, that is bigger than this MR: say so, and offer to draft the Jira comment (`Atlassian:addCommentToJiraIssue`) rather than quietly re-interpreting the ticket.

8. **Draft a reply per thread — and do not post it.** Every finding gets a proposed reply, two or three sentences, written to be read by the colleague who left the comment: what will change and where, or why it will not. Threads classified *reviewer is mistaken*, *already addressed* and *question* need their reply most, since those are the ones with no commit to speak for them. Posting the replies and resolving the threads stays the user's action — a bot answering teammates under the user's name is a social act, not a code change.

9. **Write the artifact** to `.dev/mr-comments/<KEY>.md` with the template below. First confirm `.dev/` is git-excluded — `git check-ignore -q .dev`, and if it does not match, append to `.git/info/exclude`:

   ```
   # ticket-flow workflow artifacts (local only)
   .dev/
   ```

   This phase can be the first one run in a fresh clone (reviewing an MR built elsewhere), so do not assume `ticket-plan` already did it. One unexcluded commit puts a transcript of your colleagues' review comments in the team's repository.

   **Re-runs must be idempotent.** Comments arrive over days, so this skill gets run repeatedly against a growing MR. If the artifact already exists: match incoming threads by **thread id**, keep every existing finding's number and its `Resolution:` line exactly as it is, append new threads with the next free numbers, and mark findings whose thread has since been resolved upstream as `resolved-on-gitlab` without deleting them. **Never renumber.** The user refers to these by number in chat and `ticket-build` writes shas against them; renumbering silently reassigns work that was already approved.

10. **Present the numbered list in chat, compactly, and stop.** One line per finding: ID, severity, current `file:line`, the fix in a clause, and a `plan-impact` marker where it applies. Lead with the blocking ones. Do not paste the full artifact into chat — it is on disk and the point of the summary is that the user can triage it in one screen. Then stop and let the user pick; do not start applying, and do not pre-emptively pick "the obvious ones" yourself.

11. **Hand off.** The user picks numbers; `ticket-build` fix mode applies them one at a time under its own approval gate, proving each new assertion bites and filling the `Resolution:` line here. Point them at it explicitly with the numbers they chose. Two things about what happens after:
    - After the fix pass, pushing the branch updates the existing MR by itself — do not open a second one. Update the MR description by hand if what it claims has changed: newly waived findings quoted verbatim, new testing evidence, a tradeoff the reviewer raised.
    - **A fix batch answering human review deserves the same re-review as any other**, especially where several fixes cross layers. Point them at `ticket-review` scoped to the fix commits before they ask the reviewer to look again.

## Artifact template

```markdown
# <KEY> — MR review comments
MR: !<iid> <url> → <target branch>
Branch head at analysis: <sha>
Fetched: <ISO timestamp> via <connector | glab | REST | pasted by user>
Threads: <n> total — <n> open analysed, <n> resolved skipped, <n> system/bot filtered

## H1 — <blocking|should-fix|question|nitpick|design-objection|reviewer-mistaken> — @<author>, thread <id>
> <the comment, quoted verbatim>
Anchored: <file>:<line> — <still applies | already addressed by <sha> | outdated>
plan-impact: <none | Design: … | Clarifications: … | Acceptance criteria: …>
Analysis: <what you verified, and how — the check you ran, the caller you read>
Proposed fix: <files and shape of the edit, at file:line>
Why it answers the comment: <…>
Proof: <test/command — or `requires-manual-run`: what a human must do>
Risk: <what else this touches>  Effort: <line | file | redesign>
Alternative considered: <one sentence, and why not — omit if there is none>
Draft reply (NOT posted): <2-3 sentences for the reviewer>
Resolution: <left empty here; filled by ticket-build as `fixed <sha>`, `waived — <reason>`, or `escalated — <question, owner>`>

## H2 — …

## Converged
- <finding several reviewers raised independently, and who>

## Filtered out
- <thread id> — <resolved upstream | system note | bot> — <one line, so nothing disappears silently>
```

## Boundaries

Do not edit code, do not commit, do not push, do not post or resolve anything on GitLab, and do not transition Jira. Never stage, commit, or `git add -f` anything under `.dev/` — this artifact quotes colleagues' review comments verbatim and belongs in the working tree only. Do not apply a fix "while you're in there" because it is one line; the numbering exists so the user decides, and a proposal silently applied is a decision taken from them. If there are no open comments, say exactly that rather than manufacturing findings — an MR with a clean review is the expected outcome, not a failure of this phase.
