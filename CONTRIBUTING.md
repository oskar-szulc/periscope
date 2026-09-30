# Contributing

periscope builds on macOS 26 or newer with Xcode 26 (Swift 6.2).

```bash
swift build            # warnings are errors for periscope's own targets
swift test             # includes tests that load real pages in WebKit
./scripts/lint.sh      # swift-format, strict; ./scripts/format.sh fixes it
```

- **Skill or reference changes:** edit `skills/periscope/` or `PERISCOPE.md`, then run
  `./scripts/embed-skill.sh` and commit the regenerated
  `Sources/Periscope/Generated/EmbeddedSkill.swift`. A test fails when they drift.
- **Trying a build:** run `.build/release/periscope` directly, after `periscope daemon stop`
  so the next command starts a daemon on the new build. If periscope came from Homebrew,
  `brew unlink periscope` before putting a build on PATH (`brew link periscope` to go
  back). Put it there with `rm` then `cp`, never `cp` over the old binary: macOS caches
  code signatures per inode and kills an overwritten binary.
- **Wire changes:** bump `periscopeProtocolVersion` whenever `Request`, `Response` or
  `CommandResult` change shape; a mismatched daemon restarts itself.
- **Commits:** one change per commit, with the reason in the message.
- **Releases:** `./release.sh <version>` builds `dist/`; `--publish` creates the GitHub
  release. See the script's header.
