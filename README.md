# AiTools

- [`skills/ticket-flow`](skills/ticket-flow/README.md) — a Jira → GitLab merge-request workflow for Claude Code: plan, build, review, MR feedback, QA, plus a session cost report.
- [`skills/sonar-scan`](skills/sonar-scan/SKILL.md) — Sonar check of the files a commit changed (default `HEAD`) through the SonarQube MCP server and the IDE plugin; never runs a scanner. `install-sonarqube-mcp.sh <sonarqube-url>` sets the server up.
- [`skill-manager`](skill-manager/README.md) — `manage-skills.sh`, which installs skills and their tools from repos like this one into every project and keeps them updated.
