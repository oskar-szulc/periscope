import ArgumentParser
import Foundation
import FoundationModels

/// `extract` turns a page into structured data using the on-device model.
///
///   periscope extract "title, location, apply_url"      # rows, one per item
///   periscope extract --prompt "the pricing tiers and prices"   # free-form JSON
///   periscope extract "title, url" --from "#results"    # scope to a subtree
///
/// The raw HTML never reaches the caller: the model runs locally and returns
/// the fields, so the agent reads data, not DOM.
struct ExtractData: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract structured data from the page using the on-device model")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Comma-separated fields (default), or a description with --prompt")
    var query: String

    @Option(name: .long, help: "Scope extraction to this CSS selector's content")
    var from: String?

    @Flag(name: .long, help: "Treat the argument as a natural-language description; return free-form JSON")
    var prompt: Bool = false

    func run() throws {
        let query = query
        let from = from
        let promptMode = prompt

        CommandRunner.run(globals: globals) { engine in
            let content = try await engine.readableContent(from: from)

            guard SystemLanguageModel.default.isAvailable else {
                // Fallback: hand back the raw content (capped) so the agent can
                // parse it in-context. Output is plain text, not JSON, here.
                FileHandle.standardError.write(Data(
                    "Apple Intelligence unavailable; returning raw content instead of extracted fields.\n".utf8))
                return .plain(String(content.prefix(Extraction.fallbackCap)))
            }
            if content.isEmpty {
                return .rawJSON(promptMode ? "{}" : "[]")
            }

            return promptMode
                ? try await extractFreeform(content: content, description: query)
                : try await extractRows(content: content, fields: Extraction.fieldList(query))
        }
    }

    /// Field list -> array of objects, one model call per chunk, rows merged.
    private func extractRows(content: String, fields: [String]) async throws -> CommandResult {
        guard !fields.isEmpty else {
            throw PeriscopeError.argumentError(reason: "No fields given; e.g. \"title, url\" or use --prompt")
        }
        let schema = try Extraction.rowsSchema(fields: fields)
        var arrays: [[Any]] = []
        for chunk in Extraction.chunks(content) {
            let session = LanguageModelSession(instructions: """
                You extract structured records from web page text. Return every \
                distinct item you find as a row. Fill each requested field from the \
                text; leave a field empty if the text does not contain it. Never \
                invent values.
                """)
            let response = try await session.respond(
                to: """
                Page content:
                \(chunk)

                Extract every item, each with these fields: \(fields.joined(separator: ", ")).
                """,
                schema: schema)
            arrays.append(Extraction.itemsFromResult(response.content.jsonString))
        }
        let merged = Extraction.mergeItems(arrays)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted])
        return .rawJSON(String(data: data, encoding: .utf8) ?? "[]")
    }

    /// Natural-language description -> free-form JSON. Free JSON cannot be merged
    /// across chunks, so this uses the first chunk and warns when content spilled.
    private func extractFreeform(content: String, description: String) async throws -> CommandResult {
        let allChunks = Extraction.chunks(content)
        let chunk = allChunks.first ?? content
        if allChunks.count > 1 {
            FileHandle.standardError.write(Data(
                "Content exceeded one model window; extracted from the first \(chunk.count) chars.\n".utf8))
        }
        let session = LanguageModelSession(instructions: """
            You extract data from web page text as JSON. Return only a JSON value \
            (object or array) matching the request, with no prose or code fences. \
            Base every value on the text; omit anything the text does not contain.
            """)
        let response = try await session.respond(to: """
            Page content:
            \(chunk)

            Extract as JSON: \(description)
            """)
        return .rawJSON(Self.asJSON(response.content))
    }

    /// The model is asked for bare JSON, but wrap defensively: strip code fences,
    /// and if it still is not valid JSON, return it as a `{"text": ...}` object.
    static func asJSON(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = s.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return s
        }
        let wrapped = try? JSONSerialization.data(withJSONObject: ["text": raw], options: [])
        return wrapped.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
