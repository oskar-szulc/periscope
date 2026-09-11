#!/bin/bash
# Google search via periscope. Prints "title | url" per result.
#
#   gsearch.sh 'site:jobs.ashbyhq.com (Toronto OR Ontario) ("clinical" OR "patient")'
#   gsearch.sh --pages 3 'query'      # follow "Next" up to N pages
#
# Google CAPTCHAs a *fresh* browser whose first request is an operator-heavy
# query (site:, OR, quotes). A session that has already done one plain search
# carries cookies that let the same query through, so we warm the session once.
#
# Canonical copy: ~/.claude/skills/periscope/scripts/gsearch.sh
# (a copy also lives in the periscope repo under examples/)
#
# Exit codes: 0 ok, 2 usage, 5 blocked by a challenge page, 6 not a results page.
# periscope itself uses 0-4 for its own errors and 5 for BLOCKED, so a propagated
# periscope failure keeps its meaning.
set -euo pipefail

P=${PERISCOPE:-/opt/homebrew/bin/periscope}
SESSION=${SESSION:-google}
PAGES=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pages) PAGES=$2; shift 2 ;;
    --session) SESSION=$2; shift 2 ;;
    *) break ;;
  esac
done
[[ $# -ge 1 ]] || { echo "usage: $0 [--pages N] [--session NAME] 'query'" >&2; exit 2; }
QUERY=$1

enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote_plus(sys.argv[1]))' "$1"; }

# Organic results: every result title is an <h3> inside an <a>. Class names churn; this doesn't.
# Google sometimes wraps hrefs as /url?q=<real>&sa=...; unwrap them.
EXTRACT='JSON.stringify([...document.querySelectorAll("a h3")].map(h=>{
  const a=h.closest("a"); let u=a.href;
  const m=u.match(/[?&]q=([^&]+)/); if(u.includes("/url?")&&m) u=decodeURIComponent(m[1]);
  return h.textContent.trim()+" | "+u;}))'
# Google dropped the #pnnext id (observed 2026-09). Match the "Next" anchor by text, id as fallback.
NEXT_HREF='([...document.querySelectorAll("a")].find(a=>a.id==="pnnext"||/^Next\s*>?$/i.test(a.textContent.trim()))||{}).href||""'

# navigate: 0 = loaded, 1 = periscope reported BLOCKED (exit 5). Anything else is fatal.
nav() {
  local out rc=0
  out=$($P navigate "$1" --session "$SESSION" 2>&1) || rc=$?
  case $rc in
    0) return 0 ;;
    5) return 1 ;;
    *) echo "$out" >&2; exit "$rc" ;;
  esac
}

# Google's markup varies (sometimes only a #main container), so judge by URL, not by element ids.
assert_results_page() {
  local u; u=$($P url --session "$SESSION")
  [[ "$u" =~ ^https://www\.google\.[a-z.]+/search\? ]] || { echo "UNEXPECTED PAGE (not Google results): $u" >&2; exit 6; }
}

warm() {
  # Only warm if the session has no Google cookies yet.
  if ! $P cookie list --session "$SESSION" 2>/dev/null | grep -q 'google'; then
    nav 'https://www.google.com/search?q=weather+toronto&hl=en' || true
  fi
}

SEARCH_URL="https://www.google.com/search?q=$(enc "$QUERY")&hl=en"

warm
if ! nav "$SEARCH_URL"; then
  # One retry after a fresh warm, in case cookies were stale.
  nav 'https://www.google.com/search?q=toronto+news&hl=en' || true
  if ! nav "$SEARCH_URL"; then
    echo "BLOCKED: Google served a CAPTCHA. Solve it once with:" >&2
    echo "  $P login 'https://www.google.com/search?q=test' --session $SESSION --until 'selector:a h3'" >&2
    exit 5
  fi
fi

assert_results_page
page=1
while :; do
  $P eval "$EXTRACT" --session "$SESSION" | python3 -c 'import sys,json; [print(r) for r in json.load(sys.stdin)]'
  (( page < PAGES )) || break
  next=$($P eval "$NEXT_HREF" --session "$SESSION" | tr -d '"')
  [[ -n "$next" ]] || break
  nav "$next" || { echo "BLOCKED on page $((page+1))" >&2; exit 5; }
  page=$((page+1))
done
