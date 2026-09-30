#!/bin/sh
# Build a release: ./release.sh 0.2.0 [--publish]
#
# Writes dist/periscope-<v>-macos.tar.gz (universal arm64 + x86_64, ad-hoc
# signed, so no Apple Developer ID is needed), its .sha256, and a Homebrew
# formula, dist/periscope.rb. With --publish it also creates the GitHub
# release v<v> with those assets; copy the formula into your tap repo
# (Formula/periscope.rb in <owner>/homebrew-tap) to ship it via brew.
set -eu
cd "$(dirname "$0")"
VERSION=${1:?usage: ./release.sh <version> [--publish]}
PUBLISH=${2:-}
REPO=${REPO:-oskar-szulc/periscope}

grep -q "version: \"$VERSION\"" Sources/Periscope/Commands/PeriscopeCommand.swift \
    || { echo "PeriscopeCommand.swift is not at version $VERSION; bump it first" >&2; exit 1; }
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

cat > dist/periscope.rb <<RUBY
class Periscope < Formula
  desc "Headless Safari-engine browser CLI for agents"
  homepage "https://github.com/$REPO"
  url "https://github.com/$REPO/releases/download/v$VERSION/$TARBALL"
  sha256 "$SHA"
  license "MIT"

  depends_on macos: :tahoe

  def install
    bin.install "periscope"
  end

  test do
    assert_match "$VERSION", shell_output("#{bin}/periscope --version")
  end
end
RUBY

echo "built dist/$TARBALL ($SHA)"
if [ "$PUBLISH" = "--publish" ]; then
    gh release create "v$VERSION" "dist/$TARBALL" "dist/$TARBALL.sha256" \
        -R "$REPO" --title "v$VERSION" --generate-notes
    echo "published; now copy dist/periscope.rb to Formula/periscope.rb in your tap repo"
fi
