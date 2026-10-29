#!/bin/bash
# install-sonarqube-mcp.sh <sonarqube-url> [version]
#
# Installs SonarSource's SonarQube MCP server on this machine and registers it in Claude Code as the
# `sonarqube` MCP server the sonar-scan skill relies on. The server runs locally, forwards
# `analyze_file_list` to the SonarQube for IDE plugin and publishes nothing to the SonarQube server.
# Safe to run again: it replaces the files and the registration.
#
# Needs, before running it:
# - Java 21 or newer on the PATH of a login shell
# - the `claude` CLI (Claude Code), curl, and shasum or sha256sum
# - SONAR_TOKEN exported by the login shell profile (~/.zprofile on macOS): a USER token generated at
#   <sonarqube-url>/account/security. The server does not start without it, and the token stays in
#   the profile, never in a Claude Code config file.
# - IntelliJ with the SonarQube for IDE plugin, bound to the project's key on <sonarqube-url>
#   (Settings > Tools > SonarQube for IDE > Project Settings). The binding decides the rules. The
#   plugin listens on port 64120 while IntelliJ is open on the project, and the analysis runs inside it.
#
# What it does:
# 1. downloads sonarqube-mcp-server-<version>.jar into ~/.local/share/sonarqube-mcp and checks it
#    against the .sha256 file published next to it
# 2. writes start.sh there: exports SONARQUBE_URL, SONARQUBE_TOKEN (from SONAR_TOKEN), STORAGE_PATH,
#    SONARQUBE_IDE_PORT and TELEMETRY_DISABLED, then runs the jar
# 3. registers `$SHELL -l ~/.local/share/sonarqube-mcp/start.sh` at user scope, so the token is read
#    from the profile at launch
#
# Afterwards start a new Claude Code session: MCP servers load at session start.
# To remove: claude mcp remove sonarqube -s user && rm -r ~/.local/share/sonarqube-mcp
# Releases: https://binaries.sonarsource.com/Distribution/sonarqube-mcp-server/
set -eu

[ $# -ge 1 ] || { echo "usage: $0 <sonarqube-url> [version]" >&2; exit 1; }
SONARQUBE_URL="${1%/}"
VERSION="${2:-1.28.0.4397}"
DOWNLOAD_BASE="https://binaries.sonarsource.com/Distribution/sonarqube-mcp-server"
INSTALL_DIR="$HOME/.local/share/sonarqube-mcp"
JAR="sonarqube-mcp-server-$VERSION.jar"
LOGIN_SHELL="${SHELL:-/bin/sh}"

fail() {
  echo "error: $*" >&2
  exit 1
}

sha256_of() {
  if command -v shasum >/dev/null; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

command -v curl >/dev/null || fail "curl is required"
command -v shasum >/dev/null || command -v sha256sum >/dev/null || fail "shasum or sha256sum is required"
command -v claude >/dev/null || fail "the claude CLI is required: https://docs.anthropic.com/en/docs/claude-code"

java_major=$("$LOGIN_SHELL" -l -c 'java -version 2>&1' | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
[ -n "$java_major" ] || fail "no java on the PATH of $LOGIN_SHELL -l"
[ "$java_major" -ge 21 ] || fail "java $java_major found on the PATH of $LOGIN_SHELL -l, the server needs 21 or newer"

"$LOGIN_SHELL" -l -c '[ -n "$SONAR_TOKEN" ]' \
  || fail "SONAR_TOKEN is not exported by $LOGIN_SHELL -l: add 'export SONAR_TOKEN=<user token>' to your profile (~/.zprofile on macOS), token from $SONARQUBE_URL/account/security"

mkdir -p "$INSTALL_DIR/storage"

if [ ! -f "$INSTALL_DIR/$JAR" ]; then
  echo "Downloading $DOWNLOAD_BASE/$JAR"
  curl -fsSL -o "$INSTALL_DIR/$JAR.part" "$DOWNLOAD_BASE/$JAR"
  mv "$INSTALL_DIR/$JAR.part" "$INSTALL_DIR/$JAR"
fi

expected=$(curl -fsSL "$DOWNLOAD_BASE/$JAR.sha256" | cut -d' ' -f1)
[ -n "$expected" ] || fail "no SHA-256 published at $DOWNLOAD_BASE/$JAR.sha256"
actual=$(sha256_of "$INSTALL_DIR/$JAR")
if [ "$actual" != "$expected" ]; then
  rm -f "$INSTALL_DIR/$JAR"
  fail "SHA-256 mismatch for $JAR: expected $expected, got $actual"
fi
echo "$expected" > "$INSTALL_DIR/$JAR.sha256"
ln -sfn "$JAR" "$INSTALL_DIR/sonarqube-mcp-server.jar"
echo "Installed $INSTALL_DIR/$JAR (SHA-256 verified)"

cat > "$INSTALL_DIR/start.sh" <<EOF
#!/bin/sh
export SONARQUBE_URL="\${SONARQUBE_URL:-$SONARQUBE_URL}"
export SONARQUBE_TOKEN="\${SONARQUBE_TOKEN:-\$SONAR_TOKEN}"
export STORAGE_PATH="\${STORAGE_PATH:-\$HOME/.local/share/sonarqube-mcp/storage}"
export SONARQUBE_IDE_PORT="\${SONARQUBE_IDE_PORT:-64120}"
export TELEMETRY_DISABLED="\${TELEMETRY_DISABLED:-true}"
exec java -jar "\$HOME/.local/share/sonarqube-mcp/sonarqube-mcp-server.jar"
EOF
chmod +x "$INSTALL_DIR/start.sh"

claude mcp remove sonarqube -s user >/dev/null 2>&1 || true
claude mcp add --scope user sonarqube -- "$LOGIN_SHELL" -l "$INSTALL_DIR/start.sh"
claude mcp get sonarqube

echo
echo "Done. Start a new Claude Code session to get the sonarqube tools."
echo "Keep IntelliJ open on the project, with SonarQube for IDE bound to the project's key on $SONARQUBE_URL."
