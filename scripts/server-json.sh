#!/bin/sh
# Prints the MCP Registry entry for a release: scripts/server-json.sh <version> <mcpb sha256>
# Used by release.sh and the publish-mcp-registry workflow, so they cannot drift.
set -eu
VERSION=${1:?usage: server-json.sh <version> <mcpb-sha256>}
SHA=${2:?usage: server-json.sh <version> <mcpb-sha256>}
REPO=${REPO:-oskar-szulc/periscope}
cat <<JSON
{
  "\$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "io.github.oskar-szulc/periscope",
  "title": "periscope",
  "description": "A real Safari-engine (WebKit) browser for agents on macOS: sessions, extraction, bot checks.",
  "version": "$VERSION",
  "repository": { "url": "https://github.com/$REPO", "source": "github" },
  "packages": [
    {
      "registryType": "mcpb",
      "identifier": "https://github.com/$REPO/releases/download/v$VERSION/periscope-$VERSION.mcpb",
      "fileSha256": "$SHA",
      "transport": { "type": "stdio" }
    }
  ]
}
JSON
