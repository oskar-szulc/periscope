# Periscope

A headless browser CLI for AI agents, built on WebKit (Safari's engine).

Unlike Playwright/Puppeteer which use Chromium, Periscope uses the native macOS WebKit engine. This means it presents a genuine Safari browser fingerprint that bot detection systems (Cloudflare, DataDome, PerimeterX) don't flag.

## Requirements

- macOS 26+
- Xcode 26+ (for building)
- Apple silicon with Apple Intelligence enabled, for `extract`, `query`, and `find` only. Every other command runs anywhere macOS 26 does.

## Build

```bash
cd periscope
swift build -c release --disable-sandbox
```

The binary is at `.build/release/Periscope`.

## Install

```bash
rm -f /opt/homebrew/bin/periscope
cp .build/release/Periscope /opt/homebrew/bin/periscope
```

Or wherever you keep local binaries that's on your PATH.

**Reinstalling, two things that bite:**

- **`rm` first, don't `cp` over the existing file.** macOS caches a binary's code signature per inode; overwriting in place makes the next launch die with exit 137. Removing then copying gives a fresh inode.
- **Restart the daemon:** `periscope daemon stop`. A running daemon keeps serving the old binary until the wire protocol version changes; stopping it forces the next command to spawn the rebuilt one.

## Quick Start

```bash
# Navigate and read content
periscope navigate "https://example.com" --session demo
periscope text --session demo

# Take a screenshot
periscope screenshot /tmp/page.png --session demo

# Execute JavaScript
periscope eval "document.title" --session demo

# Fill a form (targets can be CSS or semantic: text:/label:/placeholder:/role:)
periscope fill "label:Search" "query" --session demo --submit

# Pull structured data out as JSON (on-device model)
periscope extract "title, price, url" --session demo

# Manual login (opens visible browser window)
periscope login "https://app.example.com/login" --session myapp
```

## How It Works

A background daemon holds a live `WebPage` per named session. The CLI is a thin
client that sends one command over a unix socket at `~/.periscope/run/sock` and
prints the reply, so commands after the first in a session reuse a browser that
is genuinely still open — no page reload, and JS state, SPA route and scroll
position all survive. The daemon starts on demand; you never launch it yourself.

Sessions are also flushed to `~/.periscope/sessions/<name>/` (cookies,
localStorage, last URL) when evicted or on shutdown, so they survive a reboot
and cold-start from there.

`--no-daemon` runs everything in-process instead: correct, but it rebuilds the
page from that snapshot on every command. It is the automatic fallback whenever
the daemon cannot be reached, so periscope never hard-fails on daemon trouble.

## Agent Integration

See [PERISCOPE.md](PERISCOPE.md) for the full command reference designed for AI agents.

To make periscope available to agents, point them to PERISCOPE.md or add it to their context. For Claude Code, add to your CLAUDE.md:

```
For web browsing, use the `periscope` CLI. Reference: /path/to/periscope/PERISCOPE.md
```

**Running under a sandbox (e.g. Claude Code):** the daemon is reached over a unix
socket at `~/.periscope/run/sock`. If the agent's shell sandbox blocks that socket,
every command hangs silently instead of erroring. Run periscope commands with the
sandbox disabled for that tool. As a canary, `periscope daemon status` returns
instantly when the socket is reachable and hangs when it is not.

## All Commands

```
navigate <url>        Go to URL
back / forward        History navigation
reload                Reload page
url                   Print current URL
history               Print history

state                 URL, content and every actionable selector (--match, --all, --out)
text [selector]       Content as markdown
html [selector]       Raw HTML
attr <sel> <attr>     Get attribute value
links [--match re]    List all links (absolute URLs)
table <selector>      Extract table
extract <fields>      Structured data as JSON via the on-device model (--from, --prompt)

click <target>        Click element (CSS or text:/label:/placeholder:/role:)
fill <target> <value> Set input value (--submit to press Enter)
select <sel> <value>  Choose <select> option
check / uncheck       Toggle checkbox
submit [target]       Submit form
scroll <target>       Scroll (up/down/top/bottom/selector)
hover <target>        Hover element

screenshot [path]     Take screenshot
eval <code>           Execute JavaScript

requests [--match|--unresolved|--settle]   Fetch/XHR the page made, with status
console [--level]     console.* output and uncaught errors

session list/delete/export/import
cookie list/set/delete
login <url>           Manual login with visible browser
wait <strategy>       Wait for condition
elements <selector>   Inspect matching elements

query <question>      Ask about the page (Apple Intelligence)
find <description>    Description -> CSS selector

daemon status/stop    Inspect or stop the session daemon
serve                 Run the daemon in the foreground
```

Targets for interaction and `--from` accept a CSS selector or a semantic prefix
(`text:`, `label:`, `placeholder:`, `role:<role> name=<text>`); an ambiguous target
errors with the candidate selectors listed. Navigation and interaction print an
HTTP status and text-size line, and fail with exit 5 (`BLOCKED`) on a bot challenge.
See [PERISCOPE.md](PERISCOPE.md) for flags and behavior.

## License

Private.
