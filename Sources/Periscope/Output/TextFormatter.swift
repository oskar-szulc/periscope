import Foundation

struct TextFormatter: OutputFormatting {
    func format(_ result: CommandResult) -> String {
        switch result {
        case .navigate(let title, let url):
            return "Navigated to: \(title ?? "(untitled)")\nURL: \(url)"
        case .extract(let content):
            return content
        case .html(let content):
            return content
        case .links(let items):
            return items.map { "- [\($0.text)](\($0.url))" }.joined(separator: "\n")
        case .elements(let items):
            return items.map { item in
                var desc = "\(item.index). <\(item.tag)"
                if let id = item.id { desc += " id=\"\(id)\"" }
                if !item.classes.isEmpty { desc += " class=\"\(item.classes.joined(separator: " "))\"" }
                desc += "> \"\(item.text)\""
                return desc
            }.joined(separator: "\n")
        case .jsResult(let value):
            return value ?? "(undefined)"
        case .screenshot(let path):
            return "Screenshot saved to \(path)"
        case .cookies(let items):
            return items.map { "\($0.name)=\($0.value) (domain: \($0.domain))" }.joined(separator: "\n")
        case .sessionList(let names):
            return names.isEmpty ? "No sessions found." : names.joined(separator: "\n")
        case .history(let items):
            return items.map { item in
                let marker = item.isCurrent ? " <- current" : ""
                return "- [\(item.title ?? "(untitled)")](\(item.url))\(marker)"
            }.joined(separator: "\n")
        case .state(let state):
            return Self.renderState(state)
        case .plain(let text):
            return text
        case .error(let message):
            return "Error: \(message)"
        }
    }

    func formatError(_ payload: ErrorPayload) -> String {
        "Error: " + payload.message
    }

    /// Laid out so an agent can read a selector off the left edge and use it
    /// verbatim in the next command.
    private static func renderState(_ state: PageStateData) -> String {
        var lines: [String] = ["URL: \(state.url)"]
        if !state.title.isEmpty { lines.append("Title: \(state.title)") }

        if !state.headings.isEmpty {
            lines.append("")
            lines.append("Headings:")
            for heading in state.headings {
                lines.append("  " + String(repeating: "  ", count: max(heading.level - 1, 0))
                    + heading.text)
            }
        }

        if !state.text.isEmpty {
            lines.append("")
            lines.append("Content:" + (state.truncated ? " (truncated)" : ""))
            lines.append(state.text)
        }

        lines.append("")
        if state.elements.isEmpty {
            lines.append("Actions: none found")
            return lines.joined(separator: "\n")
        }

        lines.append("Actions (\(state.elements.count)):")
        let width = state.elements.map(\.selector.count).max() ?? 0
        for element in state.elements {
            var descriptor = element.tag
            if let type = element.type, element.tag == "input" { descriptor += "[\(type)]" }

            var notes: [String] = []
            if let label = element.label { notes.append("label=\"\(label)\"") }
            if let text = element.text, !text.isEmpty, text != element.label {
                notes.append("\"\(text)\"")
            }
            if let href = element.href { notes.append("-> \(href)") }
            if let checked = element.checked { notes.append(checked ? "checked" : "unchecked") }
            if element.disabled == true { notes.append("DISABLED") }

            let padded = element.selector.padding(
                toLength: max(width, element.selector.count), withPad: " ", startingAt: 0)
            lines.append("  \(padded)  \(descriptor)"
                + (notes.isEmpty ? "" : "  " + notes.joined(separator: " ")))
        }
        return lines.joined(separator: "\n")
    }
}
