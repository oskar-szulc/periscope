#!/bin/sh
# Build a release: ./release.sh 0.2.0 [--publish]
#
# Writes to dist/: periscope-<v>-macos.tar.gz (universal arm64 + x86_64,
# ad-hoc signed, so no Apple Developer ID is needed) and its .sha256, and an
# MCP bundle, periscope-<v>.mcpb. With --publish it also creates the GitHub
# release v<v> with the tarball and bundle, which triggers the workflows that
# list it in the MCP Registry and update <owner>/homebrew-tap.
set -eu
cd "$(dirname "$0")"
VERSION=${1:?usage: ./release.sh <version> [--publish]}
PUBLISH=${2:-}
REPO=${REPO:-oskar-szulc/periscope}

grep -q "version: \"$VERSION\"" Sources/Periscope/Commands/PeriscopeCommand.swift \
    || { echo "PeriscopeCommand.swift is not at version $VERSION; bump it first" >&2; exit 1; }
grep -q "\"version\": \"$VERSION\"" .claude-plugin/plugin.json \
    || { echo ".claude-plugin/plugin.json is not at version $VERSION; bump it first" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }
./scripts/embed-skill.sh >/dev/null
[ -z "$(git status --porcelain)" ] || { echo "embedded skill was stale; commit Sources/Periscope/Generated" >&2; exit 1; }

swift test
swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/periscope
codesign --force --sign - "$BIN"

rm -rf dist && mkdir dist
TARBALL=periscope-$VERSION-macos.tar.gz
tar -czf "dist/$TARBALL" -C "$(dirname "$BIN")" periscope
(cd dist && shasum -a 256 "$TARBALL" > "$TARBALL.sha256")
SHA=$(cut -d' ' -f1 "dist/$TARBALL.sha256")


# MCP bundle: the same binary, run as `periscope mcp`. The tool list comes
# from the server itself, so it cannot drift from the code.
mkdir -p dist/mcpb/server
cp "$BIN" dist/mcpb/server/periscope
TOOLS=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | "$BIN" mcp \
    | python3 -c 'import json,sys; print(json.dumps([{"name": t["name"], "description": t["description"]} for t in json.load(sys.stdin)["result"]["tools"]]))')
cat > dist/mcpb/manifest.json <<JSON
{
  "manifest_version": "0.3",
  "name": "periscope",
  "display_name": "periscope",
  "version": "$VERSION",
  "description": "A real Safari-engine browser for agents: open pages, read them as text or structured JSON, click and type, with sessions that stay open.",
  "author": { "name": "Oskar Szulc", "url": "https://github.com/oskar-szulc" },
  "homepage": "https://github.com/$REPO",
  "repository": { "type": "git", "url": "https://github.com/$REPO" },
  "license": "MIT",
  "keywords": ["browser", "scraping", "webkit", "safari", "headless"],
  "server": {
    "type": "binary",
    "entry_point": "server/periscope",
    "mcp_config": { "command": "\${__dirname}/server/periscope", "args": ["mcp"] }
  },
  "tools": $TOOLS,
  "compatibility": { "platforms": ["darwin"] }
}
JSON
MCPB=periscope-$VERSION.mcpb
npx -y @anthropic-ai/mcpb validate dist/mcpb/manifest.json
npx -y @anthropic-ai/mcpb pack dist/mcpb "dist/$MCPB" >/dev/null
MCPB_SHA=$(shasum -a 256 "dist/$MCPB" | cut -d' ' -f1)

echo "built dist/$TARBALL ($SHA) and dist/$MCPB ($MCPB_SHA)"
if [ "$PUBLISH" = "--publish" ]; then
    gh release create "v$VERSION" "dist/$TARBALL" "dist/$TARBALL.sha256" "dist/$MCPB" \
        -R "$REPO" --title "v$VERSION" --generate-notes
    echo "published; workflows now list it in the MCP Registry and update the Homebrew tap."
fi
