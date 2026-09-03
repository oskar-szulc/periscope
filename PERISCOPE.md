# Periscope: Headless Browser CLI

Periscope drives a real WebKit browser (Safari's engine) from the command line. No visible window, no dock icon; clean text or JSON on stdout. Because the engine is native WebKit, it presents a genuine Safari fingerprint rather than an automation-flagged one.

Binary: `/opt/homebrew/bin/periscope`

## Start here

```bash
periscope navigate "https://example.com" --session work
periscope text --session work
```

Two rules cover most mistakes:

1. **Always pass `--session <name>`.** Commands share a browser only when they share a session name.
2. **`navigate` first.** Every other command reads or acts on whatever page the session is already on.

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
periscope navigate <url>                 # Go to URL; prints title and final URL
periscope back                           # Back in history
periscope forward                        # Forward in history
periscope reload                         # Reload current page
periscope url                            # Print current URL
periscope history                        # Print back/forward list
```

### Reading the page

```bash
periscope text                           # Page content as markdown (<main>, <article>, or <body>)
periscope text "<selector>"              # One element as markdown
periscope text --raw                     # Plain text, no markdown
periscope html                           # Full page HTML
periscope html "<selector>"              # One element's outer HTML
periscope attr "<selector>" <attribute>  # One attribute value, e.g. href
periscope links                          # All links as a markdown list
periscope table "<selector>"             # A table as markdown
periscope elements "<selector>"          # Matching elements with tag, id, classes, text
```

`text` is the one to reach for by default — it is the most token-efficient view of a page. `extract` is a deprecated alias for it.

Use `elements` when a selector is not matching what you expected; it shows what is actually there.

### Interaction

```bash
periscope click  "<selector>"            # Click
periscope fill   "<selector>" "<value>"  # Set an input (fires input + change)
periscope select "<selector>" "<value>"  # Choose a <select> option
periscope check   "<selector>"           # Check a checkbox
periscope uncheck "<selector>"           # Uncheck a checkbox
periscope submit                         # Submit the first form
periscope submit "<selector>"            # Submit a specific form
periscope hover  "<selector>"            # Hover
periscope scroll down|up|top|bottom      # Scroll the page
periscope scroll "<selector>"            # Scroll an element into view
```

### Asking about the page

```bash
periscope query "<question>"             # Answer a question about the page in prose
periscope find  "<description>"          # Resolve a description to a CSS selector
```

`find "the sign in button"` returns a selector you can hand straight to `click`. Both use on-device Apple Intelligence, so they need it available and cost more than a plain selector — prefer `elements` when you already know roughly what you are looking for.

### Waiting

```bash
periscope wait load                      # Document load
periscope wait fetchquiet                # fetch/XHR settled (500ms quiet)
periscope wait "selector:<css>"          # Until an element exists
periscope wait "time:<ms>"               # Fixed duration
```

Most commands also take `--wait <strategy>` to wait before producing output, which saves a round trip:

```bash
periscope click "#load-more" --wait fetchquiet --session work
```

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
periscope cookie list                    # Cookies for the current page
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
| `--strict` | off | Error if a selector matches more than one element |
| `--verbose` | off | Navigation events on stderr |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Element not found, JS error, screenshot failure |
| 2 | Navigation failure or timeout |
| 3 | Session error |
| 4 | Argument error |

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

Codes: `NAVIGATION_FAILED`, `ELEMENT_NOT_FOUND`, `MULTIPLE_ELEMENTS_FOUND`, `TIMEOUT`, `SESSION_ERROR`, `JAVASCRIPT_ERROR`, `ARGUMENT_ERROR`, `SCREENSHOT_FAILED`.

## Patterns

**Read a page**

```bash
periscope navigate "https://example.com" --session s1
periscope text --session s1
```

**Fill and submit a form**

```bash
periscope navigate "https://example.com/search" --session s1
periscope fill "#query" "search terms" --session s1
periscope click "#submit" --wait fetchquiet --session s1
periscope text ".results" --session s1
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
periscope elements "button" --session s1
periscope html ".container" --session s1
```

## Gotchas

- **Omitting `--session`** puts you in the shared `default` session, alongside anything else that omitted it. Name your sessions.
- **`--no-session` across two commands does not work.** Each gets its own throwaway browser, so the second sees a blank page. Use a named session.
- **`find` and `query` need Apple Intelligence.** They fail with an argument error where it is unavailable.
- **A first command in a cold session is slow** (~400ms plus page load); the rest are milliseconds. Batch work into one session rather than spreading it across many.
