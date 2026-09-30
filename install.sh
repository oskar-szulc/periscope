#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/oskar-szulc/periscope/main/install.sh | sh
#
# Env: PERISCOPE_VERSION (default: latest), PERISCOPE_INSTALL_DIR (default:
# /usr/local/bin), REPO (default: oskar-szulc/periscope), PERISCOPE_DOWNLOAD_BASE
# (a mirror of the release assets, with PERISCOPE_VERSION set).
set -eu
REPO=${REPO:-oskar-szulc/periscope}
DIR=${PERISCOPE_INSTALL_DIR:-/usr/local/bin}

major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || { echo "periscope needs macOS 26 or newer (this is $(sw_vers -productVersion))" >&2; exit 1; }

if [ -n "${PERISCOPE_VERSION:-}" ]; then
    tag="v$PERISCOPE_VERSION"
else
    tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$tag" ] || { echo "could not find the latest release of $REPO" >&2; exit 1; }
fi
tarball="periscope-${tag#v}-macos.tar.gz"
base=${PERISCOPE_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download/$tag}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tarball" "$base/$tarball"
curl -fsSL -o "$tmp/$tarball.sha256" "$base/$tarball.sha256"
(cd "$tmp" && shasum -a 256 -c "$tarball.sha256" >/dev/null) || { echo "checksum mismatch" >&2; exit 1; }
tar -xzf "$tmp/$tarball" -C "$tmp"

# Remove, then copy: macOS caches a code signature per inode, and a binary
# overwritten in place is killed on launch (exit 137).
mkdir -p "$DIR" 2>/dev/null || true
sudo=""; [ -w "$DIR" ] || sudo="sudo"
$sudo mkdir -p "$DIR"
$sudo rm -f "$DIR/periscope"
$sudo cp "$tmp/periscope" "$DIR/periscope"
echo "installed $DIR/periscope ($tag). Stop any running daemon to pick it up: periscope daemon stop"
