import Foundation
import FoundationModels

/// The model-facing pieces of `extract`, kept separate from the command so the
/// pure parts (field parsing, chunking, dedup) are unit-testable without Apple
/// Intelligence.
enum Extraction {
    /// Characters of page text per model call. The on-device model has a small
    /// context window (the reason `query` caps its summary), so long pages are
    /// split into several calls and their rows merged.
    static let chunkBudget = 6000

    /// How much raw content the no-model fallback prints.
    static let fallbackCap = 12000

    /// "title, location, apply_url" -> ["title", "location", "apply_url"].
    static func fieldList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Split text into chunks under `budget` characters, breaking on line
    /// boundaries so an item's text is not severed mid-value. A single line over
    /// budget is hard-split as a last resort.
    static func chunks(_ text: String, budget: Int = chunkBudget) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= budget { return [trimmed] }

        var chunks: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { chunks.append(current); current = "" }
        }
        for line in trimmed.components(separatedBy: "\n") {
            let piece = line.trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { continue }
            if piece.count > budget {
                flush()
                var idx = piece.startIndex
                while idx < piece.endIndex {
                    let end = piece.index(idx, offsetBy: budget, limitedBy: piece.endIndex) ?? piece.endIndex
                    chunks.append(String(piece[idx..<end]))
                    idx = end
                }
                continue
            }
            if !current.isEmpty && current.count + piece.count + 1 > budget { flush() }
            current += current.isEmpty ? piece : "\n" + piece
        }
        flush()
        return chunks
    }

    /// Concatenate the per-chunk item arrays, dropping objects that are identical
    /// across chunks (the same row seen in overlapping content).
    static func mergeItems(_ arrays: [[Any]]) -> [Any] {
        var seen = Set<String>()
        var out: [Any] = []
        for array in arrays {
            for item in array {
                let key: String
                if JSONSerialization.isValidJSONObject(item),
                    let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
                    let s = String(data: data, encoding: .utf8)
                {
                    key = s
                } else {
                    key = String(describing: item)
                }
                if seen.insert(key).inserted { out.append(item) }
            }
        }
        return out
    }

    /// A schema describing `{ "items": [ { field: string, ... } ] }` for the
    /// caller's field list, built at runtime so the fields need not be known at
    /// compile time.
    static func rowsSchema(fields: [String]) throws -> GenerationSchema {
        let string = DynamicGenerationSchema(type: String.self)
        let properties = fields.map {
            DynamicGenerationSchema.Property(name: $0, schema: string, isOptional: true)
        }
        let row = DynamicGenerationSchema(name: "Item", properties: properties)
        let items = DynamicGenerationSchema.Property(
            name: "items", schema: DynamicGenerationSchema(arrayOf: row), isOptional: false)
        let root = DynamicGenerationSchema(name: "Result", properties: [items])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Pull the `items` array out of the model's `{"items":[...]}` JSON.
    static func itemsFromResult(_ jsonString: String) -> [Any] {
        (try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any])?["items"] as? [Any] ?? []
    }
}
