---
name: sonar-scan
description: Run a SonarQube check on the files a commit changed, through the SonarQube for IDE plugin, without publishing anything to the server. The commit defaults to HEAD. Use whenever the user wants a Sonar check of a commit or of their last change — e.g. "sonar scan", "run sonar on the last commit", "sonar-scan abc1234", "check HEAD~2 with sonar", "any sonar issues in what I just committed". Never runs `./gradlew sonar`, `sonar-scanner` or any other scanner.
---

# sonar-scan

Check the files one commit changed with the `analyze_file_list` tool of the `sonarqube` MCP server. That server is SonarSource's SonarQube MCP server bridged to the SonarQube for IDE plugin: the analysis runs inside the IDE, with the rules of the server project the plugin is bound to, and nothing is uploaded.

## Never run a scanner

Do not run `./gradlew sonar`, `mvn sonar:sonar`, `sonar-scanner`, or anything else that posts an analysis. On a Community Build server a project holds one analysis: a run from a developer machine replaces the one CI published, and a run scoped to a few files empties the project. No fallback to a scanner, even if the MCP tool is missing.

Do not call `change_sonar_issue_status` or `change_security_hotspot_status` of the `sonarqube` server either: they change issue and hotspot status on the server. Report findings; marking them is the user's action.

## Steps

1. **Resolve the commit.** Argument = any commit-ish, default `HEAD`. `git rev-parse --verify "<arg>^{commit}"`; show `git log -1 --oneline <sha>`.

2. **List the files it changed**, deleted ones excluded, merges against the first parent:
   ```bash
   git diff-tree -r --root --no-commit-id --name-only --diff-filter=ACMR --diff-merges=first-parent <sha>
   ```
   Prefix each with `git rev-parse --show-toplevel` to get absolute paths. Drop files that no longer exist in the working tree and say which.

3. **Make sure the working tree holds the commit's version.** The plugin analyses files on disk, not git objects. `git diff --name-only <sha> -- <files>`: any file listed differs from the commit (later commits, or uncommitted edits). If any do, name them and ask: analyse the working copy anyway, or stop so the user can check out `<sha>`. Never check out, stash or reset yourself.

4. **Check the tool is there.** If `analyze_file_list` of the `sonarqube` server is not available (load it with ToolSearch `select:mcp__sonarqube__analyze_file_list` if deferred):
   - not configured → tell the user to run `install-sonarqube-mcp.sh <sonarqube-url>` from this skill's base directory (its header lists what it needs: Java 21+, `SONAR_TOKEN` in the login profile, the IDE plugin bound to the project) and then open a new Claude Code session;
   - configured but failing to connect → the IDE is probably closed or not on this project: ask the user to open it, then retry once.
   Until then, the only fallback is the user running `Analyze VCS Changed Files` in the SonarQube for IDE tool window. Stop here.

5. **Analyse.** Call `analyze_file_list` with the absolute paths, in batches of about 50. An empty result for a file is a pass, not an error.

6. **Split findings by whether the commit touched the line.** Changed lines: `git diff -U0 <sha>^ <sha> -- <file>` (`git show -U0 --format= <sha> -- <file>` for a root commit), read the `@@ +start,count @@` hunks. A finding on a changed line is the commit's; one elsewhere in the file was already there.

7. **Report**, briefly:
   ```
   sonar-scan <short-sha> <subject> — N files, X findings on changed lines, Y pre-existing
   <path>:<line>  <severity>  <rule key>  <message>
   ```
   Commit's findings first, grouped by file; pre-existing ones after, collapsed to a count per file unless the user asks. Name files analysed with no findings in one line. Mention it if the IDE binding looks wrong (rules or project not what the user expects) — the binding decides the rules.

8. **Stop.** Offer to fix the commit's findings; do not edit, amend or commit unless asked. If asked to fix, re-run step 5 on the edited files afterwards and report again.
