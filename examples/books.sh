#!/bin/sh
# Scrape every page of a paginated list with extract, following "next".
#
#   ./examples/books.sh            # the first 3 pages of books.toscrape.com
#   ./examples/books.sh 50         # all 50
#
# Prints one JSON object per page: that page's repeated items (the book cards),
# found by structure alone, with no selectors written for this site.
set -eu
PAGES=${1:-3}
url="https://books.toscrape.com/"
for _ in $(seq "$PAGES"); do
    periscope navigate "$url" --session books --resource-mode lean >/dev/null
    periscope extract --session books --json --fields items
    url=$(periscope extract --session books --json --fields next | sed -n 's/.*"next":"\([^"]*\)".*/\1/p')
    [ -n "$url" ] || break
done
