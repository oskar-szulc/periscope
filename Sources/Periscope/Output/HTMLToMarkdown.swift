import Foundation

struct HTMLToMarkdown: Sendable {

    func convert(_ html: String) -> String {
        var text = html

        // 1. Strip content-bearing tags (script, style, nav, footer, iframe, noscript)
        let stripTags = ["script", "style", "nav", "footer", "iframe", "noscript"]
        for tag in stripTags {
            text = stripTag(tag, from: text)
        }

        // 2. Convert tables (before inline processing)
        text = convertTables(in: text)

        // 3. Convert code blocks (pre+code) — must come before inline code
        text = text.replacingOccurrences(
            of: #"<pre[^>]*>\s*<code[^>]*>([\s\S]*?)</code>\s*</pre>"#,
            with: "```\n$1\n```",
            options: .regularExpression
        )

        // 4. Convert inline code (standalone <code> not inside <pre>)
        text = text.replacingOccurrences(
            of: #"<code[^>]*>(.*?)</code>"#,
            with: "`$1`",
            options: .regularExpression
        )

        // 5. Convert headings h1–h6
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            text = text.replacingOccurrences(
                of: "<h\(level)[^>]*>(.*?)</h\(level)>",
                with: "\(hashes) $1",
                options: .regularExpression
            )
        }

        // 6. Convert bold (strong, b)
        text = text.replacingOccurrences(
            of: #"<strong[^>]*>(.*?)</strong>"#,
            with: "**$1**",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<b[^>]*>(.*?)</b>"#,
            with: "**$1**",
            options: .regularExpression
        )

        // 7. Convert italic (em, i)
        text = text.replacingOccurrences(
            of: #"<em[^>]*>(.*?)</em>"#,
            with: "*$1*",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<i[^>]*>(.*?)</i>"#,
            with: "*$1*",
            options: .regularExpression
        )

        // 8. Convert links (a href)
        text = text.replacingOccurrences(
            of: #"<a[^>]*\shref="([^"]*)"[^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )
        // Also handle single-quoted href
        text = text.replacingOccurrences(
            of: #"<a[^>]*\shref='([^']*)'[^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )

        // 9. Convert images (img src alt)
        text = text.replacingOccurrences(
            of: #"<img[^>]*\salt="([^"]*)"[^>]*\ssrc="([^"]*)"[^>]*/?>"#,
            with: "![$1]($2)",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<img[^>]*\ssrc="([^"]*)"[^>]*\salt="([^"]*)"[^>]*/?>"#,
            with: "![$2]($1)",
            options: .regularExpression
        )

        // 10. Convert line breaks (br)
        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )

        // 11. Convert unordered lists (ul/li)
        text = convertUnorderedLists(in: text)

        // 12. Convert ordered lists (ol/li)
        text = convertOrderedLists(in: text)

        // 13. Convert paragraphs (p -> double newline separated content)
        text = text.replacingOccurrences(
            of: #"<p[^>]*>(.*?)</p>"#,
            with: "$1\n\n",
            options: .regularExpression
        )

        // 14. Strip remaining HTML tags
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        // 15. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 16. Collapse whitespace (spaces/tabs within lines, but preserve newlines)
        text = collapseWhitespace(text)

        // 17. Trim
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    /// Strips a tag and all its content (e.g. script, nav).
    private func stripTag(_ tag: String, from html: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            with: "",
            options: .regularExpression
        )
    }

    /// Converts <table> blocks to markdown table syntax.
    private func convertTables(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<table[^>]*>([\s\S]*?)</table>"#,
            options: .caseInsensitive
        ) else { return html }

        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        let matches = regex.matches(in: html, range: range)

        // Iterate in reverse order to safely replace without invalidating ranges
        var result = html
        for match in matches.reversed() {
            let matchRange = Range(match.range, in: result)!
            let tableHtml = String(result[matchRange])
            let markdown = tableToMarkdown(tableHtml)
            result.replaceSubrange(matchRange, with: markdown)
        }
        return result
    }

    /// Converts a single <table>...</table> block to markdown.
    private func tableToMarkdown(_ tableHtml: String) -> String {
        // Extract rows
        guard let rowRegex = try? NSRegularExpression(
            pattern: #"<tr[^>]*>([\s\S]*?)</tr>"#,
            options: .caseInsensitive
        ) else { return tableHtml }

        let nsTable = tableHtml as NSString
        let rowRange = NSRange(location: 0, length: nsTable.length)
        let rowMatches = rowRegex.matches(in: tableHtml, range: rowRange)

        var rows: [[String]] = []
        var hasHeader = false

        for (rowIndex, rowMatch) in rowMatches.enumerated() {
            let rowContent = nsTable.substring(with: rowMatch.range(at: 1))
            var cells: [String] = []

            // Extract th cells
            let thMatches = extractCells(tag: "th", from: rowContent)
            let tdMatches = extractCells(tag: "td", from: rowContent)

            if !thMatches.isEmpty {
                cells = thMatches
                if rowIndex == 0 { hasHeader = true }
            } else {
                cells = tdMatches
            }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        guard !rows.isEmpty else { return tableHtml }

        var lines: [String] = []
        for (rowIndex, row) in rows.enumerated() {
            let line = "| " + row.joined(separator: " | ") + " |"
            lines.append(line)
            // Insert separator after first row if we have a header
            if rowIndex == 0 && hasHeader {
                let separator = "| " + row.map { _ in "---" }.joined(separator: " | ") + " |"
                lines.append(separator)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Extracts cell contents for the given tag (th or td) from a row string.
    private func extractCells(tag: String, from rowHtml: String) -> [String] {
        guard let cellRegex = try? NSRegularExpression(
            pattern: "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>",
            options: .caseInsensitive
        ) else { return [] }

        let nsRow = rowHtml as NSString
        let range = NSRange(location: 0, length: nsRow.length)
        let matches = cellRegex.matches(in: rowHtml, range: range)

        return matches.map { match in
            let cellContent = nsRow.substring(with: match.range(at: 1))
            // Strip any inner tags and trim
            let stripped = cellContent.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Converts <ul>...</ul> blocks to markdown unordered lists.
    private func convertUnorderedLists(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<ul[^>]*>([\s\S]*?)</ul>"#,
            options: .caseInsensitive
        ) else { return html }

        return replaceListMatches(regex: regex, in: html, ordered: false)
    }

    /// Converts <ol>...</ol> blocks to markdown ordered lists.
    private func convertOrderedLists(in html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<ol[^>]*>([\s\S]*?)</ol>"#,
            options: .caseInsensitive
        ) else { return html }

        return replaceListMatches(regex: regex, in: html, ordered: true)
    }

    private func replaceListMatches(regex: NSRegularExpression, in html: String, ordered: Bool) -> String {
        guard let liRegex = try? NSRegularExpression(
            pattern: #"<li[^>]*>([\s\S]*?)</li>"#,
            options: .caseInsensitive
        ) else { return html }

        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        let matches = regex.matches(in: html, range: range)

        var result = html
        for match in matches.reversed() {
            let matchRange = Range(match.range, in: result)!
            let listHtml = String(result[matchRange])

            // Extract li items from the list content
            let nsListHtml = listHtml as NSString
            let liRange = NSRange(location: 0, length: nsListHtml.length)
            let liMatches = liRegex.matches(in: listHtml, range: liRange)

            var items: [String] = []
            for (index, liMatch) in liMatches.enumerated() {
                var itemContent = nsListHtml.substring(with: liMatch.range(at: 1))
                // Strip inner tags and trim
                itemContent = itemContent.replacingOccurrences(
                    of: #"<[^>]+>"#,
                    with: "",
                    options: .regularExpression
                )
                itemContent = itemContent.trimmingCharacters(in: .whitespacesAndNewlines)

                if ordered {
                    items.append("\(index + 1). \(itemContent)")
                } else {
                    items.append("- \(itemContent)")
                }
            }

            let markdown = items.joined(separator: "\n")
            result.replaceSubrange(matchRange, with: markdown)
        }
        return result
    }

    /// Decodes common HTML entities.
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Decode numeric entities (decimal)
        result = result.replacingOccurrences(
            of: #"&#(\d+);"#,
            with: { (match: String) -> String in
                // Extract the number from the match
                let inner = match.dropFirst(2).dropLast(1) // remove &# and ;
                if let codePoint = UInt32(inner), let scalar = Unicode.Scalar(codePoint) {
                    return String(scalar)
                }
                return match
            }
        )
        return result
    }

    /// Collapses multiple spaces/tabs within lines, preserving newlines.
    private func collapseWhitespace(_ text: String) -> String {
        // Collapse runs of spaces/tabs to a single space within each line
        let lines = text.components(separatedBy: "\n")
        let collapsed = lines.map { line -> String in
            // Replace multiple whitespace chars (space, tab) with single space
            line.replacingOccurrences(
                of: #"[ \t]+"#,
                with: " ",
                options: .regularExpression
            ).trimmingCharacters(in: .init(charactersIn: " \t"))
        }
        // Rejoin and collapse multiple consecutive blank lines to at most two newlines
        var result = collapsed.joined(separator: "\n")
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return result
    }
}

// MARK: - String extension helper for numeric entity replacement

private extension String {
    /// Applies a closure to replace matches of a regex pattern.
    func replacingOccurrences(of pattern: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let nsStr = self as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        let matches = regex.matches(in: self, range: fullRange)

        var result = self
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matchStr = String(result[range])
            let replacement = transform(matchStr)
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
