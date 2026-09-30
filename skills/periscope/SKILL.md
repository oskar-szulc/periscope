---
name: periscope
description: Use when a task needs a real browser from the shell - Google searches with site:/OR operators, scraping pages that block bots, paginated results, or anything to be re-run from a script or cron. Also use when deciding between periscope and the built-in WebSearch/WebFetch tools, or when a periscope command hangs, hits a CAPTCHA, or returns a DNS error.
---

# Periscope

Headless WebKit (Safari engine) CLI, `periscope` on PATH. Genuine Safari fingerprint, persistent named sessions held by a background daemon.

**Command reference (read it for syntax):** `periscope docs` prints the full reference; `periscope help <command>` gives one command's flags. This skill covers what that reference does not: when to use it, how to search Google with it, and the failures seen in practice.

## Periscope vs built-in tools

| Need | Use |
|---|---|
| One-off lookup during a conversation | Built-in `WebSearch`. Zero setup, no CAPTCHA. |
| Boolean operators honoured exactly (`site:`, `OR` groups, quotes) | Periscope against Google. `WebSearch` treats operators as soft hints and leaks off-target results. |
| Page 2, 3, ... of results | Periscope. `WebSearch` returns ~8 results, no paging. |
| Repeatable / diffable / cron / no model in the loop | Periscope. `WebSearch` only exists inside a Claude session. |
| Follow into each result and extract fields | Periscope, same session. |
| Robust long-term job feed for known companies | Their own APIs (Ashby posting API, etc.) or Google Programmable Search JSON API. Periscope is the bridge until then. |

`WebSearch` is US-based; periscope searches from the local IP, which nudges Google toward local results. Their indexes differ, so running both is complementary, not redundant.

## Google search recipe

Use the script; don't rebuild it from primitives.

```bash
# scripts/ is in this skill's folder
scripts/gsearch.sh --pages 2 'site:jobs.jobvite.com (Ontario OR Toronto) ("ophthalmic" OR "clinical" OR "patient")'
```

Prints `title | url` per line, unwraps Google redirect links, follows "Next". A two-page run normally finishes in under 20 seconds. Env: `SESSION` (default `google`), `PERISCOPE` (binary path).

Exit codes: 0 ok, 2 usage, 5 blocked (CAPTCHA or consent page), 6 landed on something that is not a results page. Periscope's own codes are 0 to 4, so a propagated periscope failure never masquerades as a block.

Follow into a result afterwards in the same session:

```bash
periscope navigate "$url" --session google && periscope text --session google
```

What the script encodes, so you don't rediscover it:

- **Google CAPTCHAs a fresh session whose first request is operator-heavy.** The fix is not backoff. Do one plain search first (any query); the cookies it sets let the same operator query through immediately. Cookies persist on disk per session name, so this is a one-time cost per session, not per run.
- **Pagination:** the `#pnnext` id is gone. Match the anchor whose text is `Next`, or navigate with `&start=10`, `&start=20`.
- **Extraction:** `document.querySelectorAll("a h3")` then `closest("a")`. Class names (`div.g`, `.yuRUbf`) churn; this doesn't.
- **Blocked detection:** `navigate` itself exits 5 with code `BLOCKED` on Google's sorry page, DuckDuckGo's challenge, or a Cloudflare interstitial, and `state` prints a `Blocked: <kind>` line. The script also treats `consent.google.` as blocked. Clear it once by hand with `periscope login 'https://www.google.com/search?q=test' --session google --until 'selector:a h3'`. The `--until` matters: `login` otherwise stops on the first URL change, and the redirect to the CAPTCHA page is itself a URL change. The clearance cookie stays in the session. This needs a person at the Mac.
- **Other engines are not fallbacks.** Bing silently drops `site:` and returns generic results. DuckDuckGo's HTML endpoint serves its own CAPTCHA. Use Google.

## Read the navigate report

Every `navigate` ends with a line like `Status: 404 · Text: 9 chars`. A status of 400 or more, or a text count in single or double digits, means the page is not what you wanted, however normal the title looks. Navigation settles the page first (fetch quiet for 500ms, capped at 5s). If an SPA still shows a tiny count, pass `--wait "selector:<css>"` for something the real content contains. `--wait none` skips settling when speed matters more.

`text --no-links` drops link URLs, which are most of a busy page's `text` (onet.pl: 40k characters, 16k without them); images are left out unless `--images`. `links --match '<regex>'` filters links by absolute URL, which replaces most post-processing of `text` output.

## Target elements the way you see them

Every interaction accepts CSS or a semantic target: `text:Next`, `label:Search Wikipedia`, `placeholder:Email`, `role:button name=Sign in`. A target matching several elements is an error that lists each match with a unique selector; add `--first` only when the first match is what you want. Actions wait up to 5s for the target to appear and be enabled, so do not add `wait` calls before a click. `fill <target> <value> --submit` presses Enter. Clicks and submits that change the URL print the same report as `navigate`.

`state` shows 25 actions by default and says how many it left out. On a dense page use `state --match '<regex>'` for the one you need, or `--out <file>`; never read 80 actions to find one selector.

`requests` lists every fetch/XHR the page made; each reads `=> <status>`, `=> failed` with the error, or `=> pending`. It waits up to 2s for in-flight requests to settle first (`--settle 0` to skip), and `--unresolved` shows only failures and stragglers. It finds the JSON endpoint behind a rendered list and the 404/500 a page swallowed. `console` shows the page's errors, the first thing to check when a page renders empty.

## Get data out, not DOM

`extract` returns JSON, so you read data instead of parsing HTML, and the page's raw markup never enters your context. Start with no fields: it needs no model and is deterministic.

```bash
periscope extract --session s                                  # structured, items, itemSelector, next
periscope extract "title, location, apply_url" --session s     # rows via the on-device model
periscope extract --items "li.result" --session s              # when detection picks the wrong group
periscope extract --prompt "the pricing tiers and prices" --session s   # free-form JSON
```

- `structured` holds the page's schema.org JSON-LD and microdata. Job detail pages carry a whole `JobPosting` (salary as numbers, dates, description): prefer it over anything scraped.
- `items` are the repeated records (cards, results, table rows), found by structure: `text` pieces, `links`, `image`, and header-keyed `fields` for tables. Seen working on Indeed, GitHub search, Hacker News, Wikipedia tables, books.toscrape.
- `next` is the pagination URL; `text` appears only when no items were found.

Fields send those records (not the raw page) to the model. When the model is unavailable, or wedged (seen on some Macs: `respond()` never returns), `extract` gives up after two-thirds of `--timeout` and prints the records with a note on stderr, so it no longer hangs. `query` and `find` still need the model.


## Preflight when anything misbehaves

1. **Sandbox.** periscope cannot run inside the Claude Code Bash sandbox (window server and daemon socket are denied). Every command there exits 3 at once with `periscope cannot run inside a sandbox`. Run all periscope calls with `dangerouslyDisableSandbox: true`.
   A slow network looks similar from outside. Each `navigate` has a 30 second default timeout and the script issues up to five, so two minutes of silence with the sandbox off means slow navigations, not a hang. Rerun one `navigate` with `--verbose` to watch events on stderr.
2. **`NSURLError -1003` / "hostname could not be found".** Machine DNS is down, not periscope. Confirm with `curl -sI https://example.com`.
3. **`periscope daemon status`** shows live sessions and uptime. A leftover `eqv-daemon-*` session is test residue and harmless.
4. **Stale binary:** `periscope --version` against the latest release; with Homebrew, `brew upgrade periscope` then `periscope daemon stop`. When testing a local build, run `.build/release/periscope` directly (it starts its own daemon only after `periscope daemon stop`). If you must put a build on PATH, `rm` then `cp`, never `cp` over the existing file: macOS caches the code signature per inode and kills the overwritten binary on launch with exit 137.

## Rules that prevent most mistakes

- Always pass `--session <name>`. Omitting it shares the `default` session with everything else that omitted it.
- `navigate` first; every other command acts on the page the session is already on.
- `state --session s` orients in one call: URL, content, and clickable selectors.
- `--no-session` across two commands does not work; the second sees a blank page.
- Nothing about warm-up belongs in periscope itself. It is Google-specific and one-time; it lives in the script.

## Common mistakes

| Mistake | Reality |
|---|---|
| Plan for CAPTCHA with delays and single attempts | One plain search warms the session; then operator queries pass. |
| `document.querySelector("#pnnext")` for page 2 | Returns null now; page 2 silently skipped. Match "Next" text or use `start=`. |
| Retrying after `cannot run inside a sandbox` (exit 3) | It will fail the same way. Rerun with the sandbox disabled. |
| Empty output taken as "no jobs" | Exit 6 means wrong page; exit 0 with no lines means Google truly returned nothing. Check the navigate report's `Text:` count too. |
| Grepping `text` for "unusual traffic" | `navigate` already exits 5 with `BLOCKED`. Branch on the exit code. |
| Treating a Cloudflare `BLOCKED` as final | Retry once with `--wait-challenge 20 --timeout 40`; the managed challenge often clears itself. Then `login --until "title!:Just a moment" --timeout 0`. |
| Trusting `WebSearch` with `(A OR B) (C OR D)` | It returned a California hospice job for an Ontario-only query. Filter results yourself or use periscope. |
| Rewriting the search from primitives | `scripts/gsearch.sh` already handles encoding, warm-up, unwrapping, paging, block detection. |
| `state --actions-only` on a dense page to find one selector | 80 actions, 14k chars. Use `state --match` or a semantic target like `label:Search`. |
| Rebuilding periscope and re-testing without restarting the daemon | The daemon keeps serving the old binary unless the protocol version changed. Run `periscope daemon stop` after every reinstall. |
