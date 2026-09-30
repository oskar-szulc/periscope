#!/bin/sh
# Prints the Homebrew formula for a release: scripts/formula.sh <version> <tarball sha256>
# Used by release.sh and the update-homebrew-tap workflow, so they cannot drift.
set -eu
VERSION=${1:?usage: formula.sh <version> <tarball-sha256>}
SHA=${2:?usage: formula.sh <version> <tarball-sha256>}
REPO=${REPO:-oskar-szulc/periscope}
cat <<RUBY
class Periscope < Formula
  desc "Headless Safari-engine browser CLI for agents"
  homepage "https://github.com/$REPO"
  url "https://github.com/$REPO/releases/download/v$VERSION/periscope-$VERSION-macos.tar.gz"
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
