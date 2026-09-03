# Periscope: Headless Browser CLI

Periscope is a macOS CLI that automates a real WebKit browser (Safari's engine). It runs as a hidden window — no dock icon, no visible UI — and outputs clean text or JSON to stdout. Because it uses the native WebKit engine, it presents a genuine browser fingerprint that bot detection systems (Cloudflare, DataDome, etc.) don't flag.

Binary location: `/opt/homebrew/bin/periscope`

## Key Concepts

**Sessions.** Each CLI invocation is a separate process. Sessions persist cookies, localStorage, and the last URL between invocations. By default, commands use the `default` session. Use `--session <name>` for named sessions, or `--no-session` for stateless one-shots.

**Selectors.** All commands that target elements use CSS selectors (`#id`, `.class`, `tag`, `[attr=value]`, etc.).

**Output.** Plain text/markdown by default (optimized for LLM consumption). Add `--json` for structured output with `{"ok": true/false, ...}`.

## Commands

### Navigation

```bash
periscope navigate <url>                 # Go to URL, prints title + URL
periscope back                           # Go back in history
periscope forward                        # Go forward in history
periscope reload                         # Reload current page
periscope url                            # Print current URL
periscope history                        # Print back/forward list
```

### Content Extraction

```bash
periscope extract                        # Page content as markdown (targets <main>, <article>, or <body>)
periscope extract "<selector>"           # Extract specific element as markdown
periscope extract --raw                  # Raw text, no markdown conversion
periscope html                           # Full page HTML
periscope html "<selector>"              # Specific element's outer HTML
periscope attr "<selector>" <attribute>  # Get an attribute (e.g. href, src)
periscope links                          # All links as markdown list
periscope table "<selector>"             # Extract table as markdown
```

### Interaction

```bash
periscope click "<selector>"             # Click an element
periscope fill "<selector>" "<value>"    # Set input value (dispatches input + change events)
periscope select "<selector>" "<value>"  # Choose a <select> option
periscope check "<selector>"             # Check a checkbox
periscope uncheck "<selector>"           # Uncheck a checkbox
periscope submit                         # Submit first form on page
periscope submit "<selector>"            # Submit specific form
periscope scroll down                    # Scroll down one viewport
periscope scroll up                      # Scroll up one viewport
periscope scroll top                     # Scroll to top
periscope scroll bottom                  # Scroll to bottom
periscope scroll "<selector>"            # Scroll element into view
periscope hover "<selector>"             # Hover over element
```

### JavaScript

```bash
periscope eval "<code>"                  # Execute JS, print return value
periscope eval --file script.js          # Execute JS from file
```

### Screenshots

```bash
periscope screenshot                     # Screenshot to stdout (base64)
periscope screenshot /path/to/file.png   # Screenshot to file
periscope screenshot --full              # Full-page screenshot
```

### Session Management

```bash
periscope session list                   # List saved sessions
periscope session delete <name>          # Delete a session
periscope session export <name> <path>   # Export session to directory
periscope session import <name> <path>   # Import session from directory
```

### Cookies

```bash
periscope cookies                        # List cookies for current page
periscope cookie set <name> <value>      # Set a cookie
periscope cookie set <name> <value> --domain .example.com --secure
periscope cookie delete <name>           # Delete a cookie
```

### Manual Login

```bash
periscope login <url> --session <name>   # Opens visible browser window for manual login
```

Opens a visible browser window at the URL. The user logs in manually. Periscope detects completion (URL change) and saves cookies/storage to the session. Use `--until "selector:.dashboard"` or `--until "url:/home"` for explicit completion detection.

### Waiting

```bash
periscope wait load                      # Wait for document load
periscope wait fetchquiet                # Wait for fetch/XHR to settle (500ms quiet)
periscope wait "selector:<css>"          # Wait until element exists
periscope wait "time:<ms>"               # Wait fixed duration
```

### Inspecting Elements

```bash
periscope elements "<selector>"          # List matching elements with tag, id, classes, text
```

## Global Flags

| Flag | Default | Description |
|---|---|---|
| `--session <name>` | `default` | Named session for persistence |
| `--no-session` | off | Stateless, no persistence |
| `--json` | off | JSON output |
| `--timeout <seconds>` | `30` | Max wait time |
| `--viewport <WxH>` | `1920x1080` | Viewport size |
| `--user-agent <string>` | system | Override UA (increases detection risk) |
| `--wait <strategy>` | varies | Wait condition before output |
| `--strict` | off | Error if selector matches multiple elements |
| `--verbose` | off | Print navigation events to stderr |

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Element not found, JS error, or general error |
| 2 | Navigation error (DNS, timeout, HTTP) |
| 3 | Session error |
| 4 | Argument error |

## Error Output

- **Text mode:** errors go to stderr, exit code > 0
- **JSON mode:** `{"ok": false, "error": "message"}` on stdout, exit code > 0

## Workflow Patterns

### Read a page

```bash
periscope navigate "https://example.com" --session s1
periscope extract --session s1
```

### Fill and submit a form

```bash
periscope navigate "https://example.com/search" --session s1
periscope fill "#query" "search terms" --session s1
periscope click "#submit" --session s1
periscope wait fetchquiet --session s1
periscope extract ".results" --session s1
```

### Authenticated browsing

```bash
# First time: log in manually
periscope login "https://app.example.com/login" --session myapp

# Subsequent runs: session is restored automatically
periscope navigate "https://app.example.com/dashboard" --session myapp
periscope extract ".metrics" --session myapp
```

### Scrape a list of URLs

```bash
for url in "https://example.com/page1" "https://example.com/page2"; do
  periscope navigate "$url" --no-session
  periscope extract --no-session
done
```

Note: `--no-session` won't work for the extract since each invocation is a new process with no page loaded. Use a session instead:

```bash
for url in "https://example.com/page1" "https://example.com/page2"; do
  periscope navigate "$url" --session scrape
  periscope extract --session scrape
done
```

### Get structured data with JS

```bash
periscope navigate "https://example.com" --session s1
periscope eval "JSON.stringify({title: document.title, links: document.querySelectorAll('a').length})" --session s1
```

### Debug selectors

```bash
periscope elements "button" --session s1        # See all buttons
periscope elements "input[type=text]" --session s1  # See all text inputs
```
