# Periscope: Headless Browser CLI

Periscope drives a real WebKit browser (Safari's engine) from the command line. No visible window, no dock icon; clean text or JSON on stdout. Because the engine is native WebKit, it presents a genuine Safari fingerprint rather than an automation-flagged one.

Binary: `/opt/homebrew/bin/periscope`

## Start here

```bash
periscope navigate "https://example.com" --session work
periscope state --session work
```

Three rules cover most mistakes:

1. **Always pass `--session <name>`.** Commands share a browser only when they share a session name.
2. **`navigate` first.** Every other command reads or acts on whatever page the session is already on.
3. **`state` to orient.** One call gives you the URL, the content, and every element you can act on with a ready-to-use selector — instead of `url` + `text` + `elements`.

## Sessions

A session is a **live browser that stays open between commands**. The first command in a session starts it; the rest reuse it, so they cost milliseconds instead of a page load.

```bash
periscope navigate "https://example.com" --session work   # ~400ms, loads the page
periscope text  --session work                            # ~3ms, same live page
periscope links --session work                            # ~3ms, same live page
```

Because the page is genuinely still open, everything survives between commands: JavaScript state, the SPA route you navigated to, scroll position, in-flight requests, `sessionStorage`. This is the difference from a tool that replays cookies into a fresh page.

Sessions are held by a background daemon that starts on demand. You never have to launch it.

| Flag | Meaning |
|---|---|
| `--session <name>` | Use (and create) this named session. **Use this.** |
| *(omitted)* | Uses the session named `default` — shared with everything else that omits it |
| `--no-session` | Throwaway browser, discarded after the command. Only useful for a single self-contained command |
| `--no-daemon` | Run in-process. Correct but slow: rebuilds the page every command |

Sessions are also written to `~/.periscope/sessions/<name>/` so they survive a reboot. A session idle for 30 minutes is flushed to disk and closed; the next command reopens it from that snapshot.

> A saved URL can go stale (a stopped dev server, an expired link). Periscope warns on stderr and continues with the command you actually asked for.

## Commands

### Navigation

```bash
periscope navigate <url>                 # Go to URL; prints title, final URL, HTTP status, text size
periscope back                           # Back in history
periscope forward                        # Forward in history
periscope reload                         # Reload current page
periscope url                            # Print current URL
periscope history                        # Print back/forward list
```

Every navigation command settles the page (fetch/XHR quiet for 500ms, at most 5s) and then reports:

```
Navigated to: Page not found · GitHub
URL: https://github.com/nope
Status: 404 · Text: 1,017 chars
```

`Status` is the main-frame HTTP status (`-` for non-HTTP loads and for `back`/`forward` served from cache). `Text` is the length of the
settled page's visible text. Check both before trusting `text`: a `404` shell or an SPA that
rendered nothing reads as success otherwise. `--json` carries them as `status` and `textChars`.

If the page that loaded is a bot challenge rather than content, the command **fails with exit 5**
and code `BLOCKED`, naming the kind: `google-captcha`, `duckduckgo-challenge`, `cloudflare-challenge`.
Clear it once with `login` (see below); the clearance cookie persists in the session.

### Orienting: `state`

```bash
periscope state                          # URL, title, headings, content, and every action
periscope state --actions-only           # Skip the content, just what is clickable
periscope state --match "<regex>"        # Only actions whose selector, label, text or href matches
periscope state --all                    # Every action; the default shows the first 25 and says how many more
periscope state --out page.txt           # Full output to a file, one summary line to the terminal
periscope state --text-limit 500         # Cap the content
```

This is the command to reach for after `navigate`, and after any click that changes
the page. It answers "where am I and what can I do here" in one round trip:

```
URL: file:///…/form.html
Title: Form Test Page

Content:
User Admin Sign In

Actions (5):
  #username    input[text]
  #password    input[password]
  #role        select  "User Admin"
  #remember    input[checkbox]  unchecked
  #submit-btn  button  "Sign In"
```

Every selector in the `Actions` list is verified to match **exactly one** element,
so you can use it verbatim:

```bash
periscope fill "#username" "bob" --session work
periscope click "#submit-btn" --session work
```

Elements that are hidden or invisible are left out — you cannot act on them — and
disabled ones are marked `DISABLED`. Pages without ids get structural selectors
(`ul > li:nth-of-type(2) > a`), which are still unique and still usable.

`--json` gives the same data structured, under a `state` key.

If the page is a bot challenge, a `Blocked: <kind>` line follows the URL (JSON: `blocked`). Do not
act on the elements of a blocked page; use `login` to clear it.

### Reading the page

```bash
periscope text                           # Page content as markdown (<main>, <article>, or <body>)
periscope text "<selector>"              # One element as markdown
periscope text --raw                     # Plain text, no markdown
periscope html                           # Full page HTML
periscope html "<selector>"              # One element's outer HTML
periscope attr "<selector>" <attribute>  # One attribute value, e.g. href
periscope links                          # All links as a markdown list (absolute URLs)
periscope links --match "<regex>"        # Only links whose URL matches, e.g. --match 'ashbyhq\.com/[^/]+/'
periscope table "<selector>"             # A table as markdown
periscope elements "<selector>"          # Matching elements with tag, id, classes, text
```

Reach for these when you want one specific thing; use `state` when you want to
orient. `text` is the most token-efficient view of a page's prose. `extract` is a
deprecated alias for `text`.

Use `elements` when a selector is not matching what you expected; it shows what is
actually there, including hidden nodes that `state` omits.

### Diagnostics

```bash
periscope requests                       # Every fetch/XHR the page made, with status and timing
periscope requests --match "api\."       # Only URLs matching the regex
periscope console                        # console.* output and uncaught errors since the page loaded
periscope console --level error          # One level only
```

Both monitors are injected before the page's first script runs. `requests` is the fastest way to
find the JSON endpoint behind a rendered list, and to see a 404 or 500 that the page swallowed.
`console` is where a blank page explains itself.

### Interaction

```bash
periscope click  "<target>"              # Click
periscope fill   "<target>" "<value>"    # Set an input (fires input + change)
periscope fill   "<target>" "<value>" --submit   # ...then press Enter, submitting its form
periscope select "<target>" "<value>"    # Choose a <select> option
periscope check   "<target>"             # Check a checkbox
periscope uncheck "<target>"             # Uncheck a checkbox
periscope submit                         # Submit the first form (runs the page's submit handlers)
periscope submit "<target>"              # Submit a specific form, or the form containing a field
periscope hover  "<target>"              # Hover
periscope scroll down|up|top|bottom      # Scroll the page
periscope scroll "<target>"              # Scroll an element into view
```

**Targets.** A target is a CSS selector, or one of four prefixes that name an element the way a
person sees it. Matching is case-insensitive, whitespace-collapsed, and prefers exact matches:

```bash
periscope click "text:Next"                        # visible text
periscope fill  "label:Search Wikipedia" "WebKit"  # <label>, aria-label or title
periscope fill  "placeholder:Email" "a@b.c"        # placeholder attribute
periscope click "role:button name=Sign in"         # role (button, link, textbox, searchbox, checkbox,
                                                   #   radio, combobox, heading, tab, ...) + accessible name
```

**Ambiguity is an error.** A target that matches several elements fails (exit 1, code
`MULTIPLE_ELEMENTS_FOUND`) and lists each match with a unique selector you can use instead:

```
Error: Selector 'input[name=search]' matched 2 elements. Pick one, or pass --first to act on the first:
  #searchInput  input[search] label="Search Wikipedia"
  #vector-sticky-search-form input  input[search]
```

Pass `--first` to act on the first match anyway. In `--json` the list is under `error.candidates`.

**Actions wait for their target.** `click`, `fill` and the rest wait up to 5s for the target to
exist, be visible and be enabled, so a control that renders shortly after `load` is not a
failure. After that: `Element not found` if it never appeared, or `ELEMENT_NOT_ACTIONABLE`
with the reason (`not visible`, `disabled`).

**Actions report navigations.** If a click or submit changed the URL, the output is the same
report `navigate` prints (title, URL, status, text size), so you know where you landed without
another call. Otherwise it is a one-line confirmation.

### Asking about the page

```bash
periscope query "<question>"             # Answer a question about the page in prose
periscope find  "<description>"          # Resolve a description to a CSS selector
```

`find "the sign in button"` returns a selector you can hand straight to `click`. Both use on-device Apple Intelligence, so they need it available and cost more than a plain selector — prefer `elements` when you already know roughly what you are looking for.

### Waiting

```bash
periscope wait load                      # Document load
periscope wait fetchquiet                # fetch/XHR settled (500ms quiet), no cap
periscope wait "fetchquiet:<maxMs>"      # Same, but give up after maxMs and continue
periscope wait "selector:<css>"          # Until an element exists
periscope wait "time:<ms>"               # Fixed duration
```

Navigation and interaction commands take `--wait <strategy>` to wait before producing output,
which saves a round trip. Defaults: `navigate`/`back`/`forward`/`reload` use `fetchquiet:5000`;
`click` uses `fetchquiet`. Pass `--wait none` to skip waiting entirely.

```bash
periscope click "#load-more" --wait fetchquiet --session work
periscope navigate "https://spa.example" --wait "selector:.job-card" --session work
```

An unknown strategy is an argument error (exit 4), not a silent fallback.

### JavaScript

```bash
periscope eval "<code>"                  # Run JS, print the return value
periscope eval --file script.js          # Run JS from a file
```

### Screenshots

```bash
periscope screenshot /path/to/file.png   # To a file
periscope screenshot                     # To stdout as base64
periscope screenshot --full              # Full page, not just viewport
```

### Cookies

```bash
periscope cookie list                    # Every cookie in the session's jar, all hosts, HttpOnly included
periscope cookie set <name> <value>      # Set a cookie
periscope cookie set <name> <value> --domain .example.com --secure
periscope cookie delete <name>           # Delete a cookie
```

### Session management

```bash
periscope session list                   # Saved sessions
periscope session delete <name>          # Delete one
periscope session export <name> <path>   # Export to a directory
periscope session import <name> <path>   # Import from a directory
```

### Logging in as a human

```bash
periscope login <url> --session myapp
```

Opens a **visible** window so a person can log in by hand, then saves cookies and storage to the session. Detects completion by URL change; use `--until "selector:.dashboard"` or `--until "url:/home"` to be explicit.

After this, the session is authenticated and normal commands work:

```bash
periscope navigate "https://app.example.com/dashboard" --session myapp
periscope text ".metrics" --session myapp
```

### Daemon

Managed automatically — reach for these only when debugging.

```bash
periscope daemon status                  # pid, uptime, live sessions
periscope daemon status --json           # Same, structured
periscope daemon stop                    # Flush sessions to disk and exit
periscope serve                          # Run in the foreground (development)
```

## Global flags

| Flag | Default | Description |
|---|---|---|
| `--session <name>` | `default` | Named session |
| `--no-session` | off | Throwaway browser |
| `--no-daemon` | off | Run in-process; slower, no shared page |
| `--json` | off | JSON output |
| `--timeout <seconds>` | `30` | Max wait |
| `--viewport <WxH>` | `1920x1080` | Viewport size |
| `--user-agent <string>` | system | Override UA (raises detection risk — usually leave alone) |
| `--wait <strategy>` | none | Wait before producing output |
| `--first` | off | Act on the first match when a target matches several (default: error with candidates) |
| `--verbose` | off | Navigation events on stderr |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Element not found, JS error, screenshot failure |
| 2 | Navigation failure or timeout |
| 3 | Session error |
| 4 | Argument error |
| 5 | Blocked: the page is a bot challenge (Google CAPTCHA, DuckDuckGo, Cloudflare) |

## Errors

Text mode writes the message to stderr and exits non-zero:

```
Error: Navigation to https://nope.invalid/p failed: A server with the
specified hostname could not be found. (NSURLError -1003)
```

The message names the URL that failed and the underlying error code, so a failure after a redirect points at the redirect target rather than what you asked for.

JSON mode puts a stable machine-readable code on stdout — branch on `code`, never on the message text:

```json
{"ok": false, "error": {"code": "NAVIGATION_FAILED", "message": "...", "url": "https://nope.invalid/p"}}
```

Codes: `NAVIGATION_FAILED`, `ELEMENT_NOT_FOUND`, `MULTIPLE_ELEMENTS_FOUND` (with `candidates`), `ELEMENT_NOT_ACTIONABLE`, `TIMEOUT`, `SESSION_ERROR`, `JAVASCRIPT_ERROR`, `ARGUMENT_ERROR`, `SCREENSHOT_FAILED`, `BLOCKED`.

## Patterns

**Read a page**

```bash
periscope navigate "https://example.com" --session s1
periscope text --session s1
```

**Fill and submit a form, without guessing selectors**

```bash
periscope navigate "https://example.com/search" --session s1
periscope state --actions-only --session s1     # read the real selectors
periscope fill "#query" "search terms" --session s1
periscope click "#submit" --wait fetchquiet --session s1
periscope state --session s1                    # see what the click produced
```

**Walk several pages**

One session, reused — each `navigate` is a real navigation in the same live browser, so history and cookies accumulate as they would for a person.

```bash
for url in https://example.com/a https://example.com/b; do
  periscope navigate "$url" --session scrape
  periscope text --session scrape
done
```

**Click something you cannot write a selector for**

```bash
selector=$(periscope find "the accept cookies button" --session s1)
periscope click "$selector" --session s1
```

**Structured data out**

```bash
periscope eval "JSON.stringify([...document.querySelectorAll('h2')].map(h => h.textContent))" --session s1
```

**Debug a selector that is not matching**

```bash
periscope state --actions-only --session s1    # the selectors that do work
periscope elements "button" --session s1       # everything, hidden included
periscope html ".container" --session s1
```

## Gotchas

- **Omitting `--session`** puts you in the shared `default` session, alongside anything else that omitted it. Name your sessions.
- **`--no-session` across two commands does not work.** Each gets its own throwaway browser, so the second sees a blank page. Use a named session.
- **`find` and `query` need Apple Intelligence.** They fail with an argument error where it is unavailable.
- **`navigate` output that says `Text: 0 chars` or a small number is the signal an SPA has not rendered.** Try `--wait "selector:<css>"` for something the real content contains, or `--wait fetchquiet` without the cap.
- **A first command in a cold session is slow** (~400ms plus page load); the rest are milliseconds. Batch work into one session rather than spreading it across many.
