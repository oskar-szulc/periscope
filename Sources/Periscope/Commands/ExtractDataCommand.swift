import ArgumentParser
import Foundation
import FoundationModels

/// `extract` turns a page into structured data.
///
///   periscope extract                                   # the page's own records, no model
///   periscope extract "title, location, apply_url"      # rows, one per item, via the model
///   periscope extract --prompt "the pricing tiers and prices"   # free-form JSON
///   periscope extract "title, url" --from "#results"    # scope to a subtree
///   periscope extract --items "li.result"               # name the records yourself
///
/// Without fields it is deterministic (see `PageRecords`): structured data,
/// repeated records, the next-page link. With fields, the on-device model reads
/// those records rather than the raw page and maps them to the fields; when the
/// model is unavailable or does not answer in time, the records come back
/// instead. Either way the raw HTML never reaches the caller.
struct ExtractData: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract structured data from the page (fields via the on-device model)")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Comma-separated fields, or a description with --prompt. Omit for the page's own records, no model")
    var query: String?

    @Option(name: .long, help: "Scope extraction to this CSS selector's content")
    var from: String?

    @Option(name: .long, help: "CSS selector for the records, instead of detecting them")
    var items: String?

    @Flag(name: .long, help: "Treat the argument as a natural-language description; return free-form JSON")
    var prompt: Bool = false

    func validate() throws {
        if prompt && query == nil {
            throw ValidationError("--prompt needs a description, e.g. --prompt \"the pricing tiers\"")
        }
    }

    func run() throws {
        let query = query
        let from = from
        let items = items
        let promptMode = prompt
        // Leave the command's own deadline room to print the fallback.
        let modelSeconds = max(globals.timeout * 2 / 3, 5)

        CommandRunner.run(globals: globals) { engine in
            let records = try await engine.pageRecords(from: from, items: items)
            let recordsResult = CommandResult.rawJSON(Self.json(records))
            guard let query else { return recordsResult }

            guard SystemLanguageModel.default.isAvailable else {
                FileHandle.standardError.write(Data(
                    "Apple Intelligence unavailable; returning the page's records instead of extracted fields.\n".utf8))
                return recordsResult
            }
            let content = PageRecords.modelInput(records)
            if content.isEmpty {
                return .rawJSON(promptMode ? "{}" : "[]")
            }
            do {
                return try await withTimeout(seconds: modelSeconds) {
                    promptMode
                        ? try await Self.extractFreeform(content: content, description: query)
                        : try await Self.extractRows(content: content, fields: Extraction.fieldList(query))
                }
            } catch PeriscopeError.timeout {
                FileHandle.standardError.write(Data(
                    "The on-device model did not answer within \(modelSeconds)s; returning the page's records instead.\n".utf8))
                return recordsResult
            }
        }
    }

    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Field list -> array of objects, one model call per chunk, rows merged.
    private static func extractRows(content: String, fields: [String]) async throws -> CommandResult {
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
        return .rawJSON(Self.json(merged))
    }

    /// Natural-language description -> free-form JSON. Free JSON cannot be merged
    /// across chunks, so this uses the first chunk and warns when content spilled.
    private static func extractFreeform(content: String, description: String) async throws -> CommandResult {
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
        return json(["text": raw])
    }
}
