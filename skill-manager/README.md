# skill-manager

`manage-skills.sh` keeps a personal collection of Claude Code skills — and the tools they rely on — in one folder, makes them available in every project on your machine, and keeps them updated from where they came from. It is meant to be **copied into a folder of your own**, not run from this repo: that folder becomes the collection.

## Quick start: the ticket-flow skills

```bash
mkdir -p ~/claude-custom && cp manage-skills.sh ~/claude-custom/ && cd ~/claude-custom

base=https://github.com/iompo/AiTools/tree/main/skills/ticket-flow
for s in ticket-plan ticket-build ticket-review ticket-feedback ticket-test; do
  ./manage-skills.sh add "$s" "$base/$s"
done
./manage-skills.sh add-tool ticket-flow "$base/tools"
./manage-skills.sh sync
```

Then add the `SessionEnd` cost hook from [`skills/ticket-flow/README.md`](../skills/ticket-flow/README.md#measuring-cost). From then on `./manage-skills.sh update` pulls the latest skills and tools in one go.

The rest of this file describes the collection folder (called `claude-custom/` below) and every command.

## Layout

```
claude-custom/
├── manage-skills.sh        # the management script (run this)
├── .gitignore              # excludes the local clone cache
├── .cache/                 # local git clones used by `update` (auto-managed)
├── tools/
│   └── ticket-flow/        # scripts a skill set relies on (no SKILL.md)
│       ├── ctx-report.py
│       ├── prices.json
│       └── .source
└── skills/
    ├── ticket-plan/
    │   ├── SKILL.md        # the actual skill body
    │   └── .source         # where this skill came from (used by `update`)
    ├── ticket-build/
    │   ├── SKILL.md
    │   └── .source
    └── …                   # ticket-review, ticket-feedback, ticket-test
```

A **skill** is a folder containing a `SKILL.md` with YAML frontmatter (`name`,
`description`) followed by the instructions the agent should follow. To add a
new skill, either drop a new folder under `skills/` by hand or use the script
(`add` / `add-git`).

A **tool** is a folder of supporting files that skills or Claude Code hooks rely
on — for example `ticket-flow`'s `ctx-report.py` (session cost report, run by a
`SessionEnd` hook) and its `prices.json`. Tools have no `SKILL.md`, are not
skills, and are not copied into projects; they are linked globally next to the
skills.

## Two layers: distribution and source-tracking

There are two separate ideas working together.

### 1. Making skills available across all projects (distribution)

`skills/` is the **single source of truth**. `sync` symlinks each skill into
Claude Code's global skills directory:

```
~/.claude/skills/<name>  ->  claude-custom/skills/<name>
```

Claude Code automatically discovers skills in `~/.claude/skills/`, so any skill
linked there is available in **every project** without per-project setup.

Tools are linked the same way, into a folder of their own:

```
~/.claude/tools/<name>  ->  claude-custom/tools/<name>
```

Claude Code does not read `~/.claude/tools/` itself; it is a stable path for hooks
and commands to point at (override with `CLAUDE_TOOLS_DIR`). The ticket-flow cost
hook, for instance, runs `python3 ~/.claude/tools/ticket-flow/ctx-report.py`.

Because `sync` uses symlinks, editing or updating a skill or tool in
`claude-custom/` updates the version used everywhere immediately.

### 2. Keeping skills updated from upstream (source-tracking)

Each skill folder can carry a `.source` file that records **where the skill came
from**. The `update` command re-fetches the skill from that source.

Two source types are supported for skills; tools support git sources only (a
tool is usually several files, not one URL):

```ini
# Git repo source — used for GitHub-hosted skills.
type=git
repo=https://github.com/iompo/AiTools.git
path=skills/ticket-flow/ticket-build
ref=main
```

```ini
# Plain URL source — used when there's just a raw SKILL.md somewhere.
type=url
url=https://example.com/path/to/SKILL.md
```

For git sources, the script clones the upstream repo once into
`claude-custom/.cache/repos/`, then runs `git fetch && git reset --hard origin/<ref>`
on subsequent updates and copies the requested folder into `skills/<name>/`. The
cache is `.gitignored` and safe to delete — it'll be re-cloned next time.

**Important:** `update` is a hard sync from upstream. Any local edits to a
tracked skill's or tool's files will be overwritten — this includes a tool's data
files such as `prices.json`: change those upstream (in AiTools) and push, then
`update`. The `.source` file itself is preserved.
If you want to customise a skill, either fork the upstream repo and point
`.source` at your fork, or copy the skill to a new name and drop its `.source`
file so it's no longer tracked.

## Script reference

`manage-skills.sh` figures out its own location, treats the adjacent `skills/`
folder as the source, and targets `~/.claude/skills/` as the destination (override
with the `CLAUDE_SKILLS_DIR` environment variable).

| Command | What it does |
| --- | --- |
| `list` | Lists the skills and tools in the collection, including their source (git repo + ref, or url, or "no source recorded"); for tools, also the files they hold. |
| `installed` | Lists the skills active in `~/.claude/skills/` and the tools in `~/.claude/tools/`, and what they point to. |
| `sync` | Symlinks every skill into `~/.claude/skills/` and every tool into `~/.claude/tools/`. Safe to re-run. This is the "make it available across all projects" step. |
| `add <name> <url>` | Adds a skill. Auto-detects GitHub `tree`/`blob` URLs and `raw.githubusercontent.com` paths to track them as git sources; otherwise records a plain url source. |
| `add-git <name> <repo-url> <path> [ref]` | Adds a skill from a git repo explicitly. Useful for non-GitHub hosts or when you want to pin a specific ref/tag. |
| `add-tool <name> <github-tree-url>` | Adds a tool folder from a GitHub folder URL (tracked as a git source). |
| `add-tool-git <name> <repo-url> <path> [ref]` | Adds a tool folder from a git repo explicitly. |
| `update [<name>]` | Re-fetches one skill or tool from its recorded source, or every skill and tool with a source if no name is given. A name used by both a skill and a tool is refused — keep names distinct. |
| `remove <name>` | Removes the skill's or tool's global link. The source folder is kept. |
| `link-project <path>` | Copies skills into a project's `.claude/skills/` folder (strips `.source` files in the copy) — useful when you want to commit a skill into a repo so teammates get it. |
| `help` | Prints usage. |

### Common workflows

```bash
# First time — make everything available in every project.
./manage-skills.sh sync

# Add a new skill from a GitHub folder URL (auto-detects → git source).
./manage-skills.sh add ticket-review https://github.com/iompo/AiTools/tree/main/skills/ticket-flow/ticket-review
./manage-skills.sh sync

# Add the same skill but pinned to a specific commit/tag.
./manage-skills.sh add-git ticket-review https://github.com/iompo/AiTools.git skills/ticket-flow/ticket-review <tag-or-commit>
./manage-skills.sh sync

# Pull upstream changes for everything.
./manage-skills.sh update
# (no need to re-sync — symlinks already point at the updated folders)

# Pull upstream changes for just one skill.
./manage-skills.sh update ticket-build

# Check what's in the collection and where it comes from.
./manage-skills.sh list

# Track ticket-flow's tools (cost report + price table) from AiTools.
./manage-skills.sh add-tool ticket-flow https://github.com/iompo/AiTools/tree/main/skills/ticket-flow/tools
./manage-skills.sh sync
# then add the SessionEnd hook from AiTools' ticket-flow README to ~/.claude/settings.json
```

---

## How to use a skill inside one of your projects

Once you've run `./manage-skills.sh sync`, the skill is globally available, so
there is **nothing to install per project**. From inside any project (when
running Claude Code in a repo), start the ticket-flow workflow with `ticket-plan` by:

- Typing **`/ticket-plan PROJ-123`** as a slash command, or
- Saying *"plan PROJ-123"*.
- Phrases like *"analyze this ticket"* or *"break this issue into tasks"* also reach
  for the skill, since that's what its `description` matches on.

Claude reads the ticket through the Atlassian connector, collects every open question
into one batched round instead of assuming, and writes the plan to
`.dev/plans/<KEY>.md`. From there `ticket-build`, `ticket-review`, `ticket-feedback`
and `ticket-test` take over — see [`skills/ticket-flow/README.md`](../skills/ticket-flow/README.md)
for the whole workflow.

To confirm a skill is live, you can ask Claude *"what skills do you have available?"*,
or run `./manage-skills.sh installed`.

If you want a skill committed into a specific repo (so teammates pulling the
repo get it automatically), use `./manage-skills.sh link-project /path/to/that/repo`,
which copies the skills into that project's `.claude/skills/` folder.
