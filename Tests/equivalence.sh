#!/bin/bash
# Phase B acceptance: a command must produce identical stdout, stderr and exit
# code whether it runs in-process or through the daemon. This is the test that
# says the daemon is a transport change and not a behavior change.
set -uo pipefail

# Absolute: the relative-path case runs the binary from other directories.
BIN="$(cd "$(dirname "${1:-.build/release/Periscope}")" && pwd)/$(basename "${1:-.build/release/Periscope}")"
FIXTURES="$(cd "$(dirname "$0")/../TestFixtures" && pwd)"
PASS=0; FAIL=0

# One session per mode for the whole run: these cases are a sequence, and each
# command depends on the page the previous one left behind.
sess_direct="eqv-direct-$$"
sess_daemon="eqv-daemon-$$"

cleanup() {
    rm -rf ~/.periscope/sessions/"$sess_direct" ~/.periscope/sessions/"$sess_daemon"
    rm -f /tmp/eqv.direct.err /tmp/eqv.daemon.err
}
trap cleanup EXIT

run_both() {
    local desc="$1"; shift

    local d_out d_err d_code n_out n_err n_code
    d_out=$("$BIN" "$@" --session "$sess_direct" --no-daemon 2>"/tmp/eqv.direct.err"); d_code=$?
    d_err=$(cat /tmp/eqv.direct.err)
    n_out=$("$BIN" "$@" --session "$sess_daemon" 2>"/tmp/eqv.daemon.err"); n_code=$?
    n_err=$(cat /tmp/eqv.daemon.err)

    if [[ "$d_out" == "$n_out" && "$d_code" == "$n_code" ]]; then
        PASS=$((PASS+1)); printf '  ok   %s\n' "$desc"
    else
        FAIL=$((FAIL+1))
        printf '  FAIL %s\n' "$desc"
        printf '       in-process (exit %s): %.90s\n' "$d_code" "$d_out"
        printf '       daemon     (exit %s): %.90s\n' "$n_code" "$n_out"
    fi
}

echo "equivalence: in-process vs daemon"
run_both "navigate"          navigate "file://$FIXTURES/table.html"
run_both "navigate 2"        navigate "file://$FIXTURES/article.html"
run_both "text"              text
run_both "html"              html
run_both "links"             links
run_both "table"             table
run_both "elements"          elements "p"
run_both "url"               url
run_both "eval"              eval "1 + 1"
run_both "eval string"       eval "document.title"
run_both "bad selector"      attr "#nonexistent-xyz" href
run_both "bad url"           navigate "https://nope-xyz.invalid/p"
run_both "invalid url arg"   navigate "::::"
run_both "cookie list"       cookie list
run_both "json ok"           --json url
run_both "json error"        --json navigate "https://nope-xyz.invalid/p"

# Relative paths must resolve against the CLIENT's directory. The daemon runs in
# whatever directory it was spawned from, so this silently wrote to the wrong
# place while reporting success.
check_relative_paths() {
    local a="${TMPDIR:-/tmp}/eqv-dirA" b="${TMPDIR:-/tmp}/eqv-dirB"
    mkdir -p "$a" "$b"; rm -f "$a/shot.png" "$b/shot.png"

    ( cd "$a" && "$BIN" navigate "file://$FIXTURES/table.html" --session "$sess_daemon" >/dev/null 2>&1 )
    ( cd "$b" && "$BIN" screenshot "shot.png" --session "$sess_daemon" >/dev/null 2>&1 )

    if [[ -f "$b/shot.png" && ! -f "$a/shot.png" ]]; then
        PASS=$((PASS+1)); printf '  ok   relative path resolves against client cwd\n'
    else
        FAIL=$((FAIL+1))
        printf '  FAIL relative path: landed in %s\n' \
            "$([[ -f "$a/shot.png" ]] && echo "daemon cwd" || echo "nowhere")"
    fi
    rm -rf "$a" "$b"
}

echo
check_relative_paths

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
