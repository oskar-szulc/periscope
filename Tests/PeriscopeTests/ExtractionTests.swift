import Foundation
import Testing

@testable import Periscope

@Suite("Extraction helpers")
struct ExtractionTests {
    @Test func fieldListSplitsTrimsAndDropsEmpties() {
        #expect(Extraction.fieldList("title, location , apply_url") == ["title", "location", "apply_url"])
        #expect(Extraction.fieldList(" a ,, b ,") == ["a", "b"])
        #expect(Extraction.fieldList("   ").isEmpty)
    }

    @Test func chunksReturnsWholeTextUnderBudget() {
        #expect(Extraction.chunks("short text", budget: 100) == ["short text"])
        #expect(Extraction.chunks("   ", budget: 100).isEmpty)
    }

    @Test func chunksPacksLinesUpToBudget() {
        let text = "aaaa\nbbbb\ncccc\ndddd"  // 4 lines of 4 chars
        let chunks = Extraction.chunks(text, budget: 10)  // ~2 lines per chunk
        #expect(chunks.count == 2)
        #expect(chunks[0] == "aaaa\nbbbb")
        #expect(chunks[1] == "cccc\ndddd")
        // Every original line survives exactly once.
        #expect(chunks.joined(separator: "\n") == text)
    }

    @Test func chunksHardSplitsAnOversizeLine() {
        let chunks = Extraction.chunks("abcdefghij", budget: 4)
        #expect(chunks == ["abcd", "efgh", "ij"])
    }

    @Test func mergeItemsConcatenatesAndDedupes() {
        let a: [Any] = [["t": "x"], ["t": "y"]]
        let b: [Any] = [["t": "y"], ["t": "z"]]  // "y" repeats across chunks
        let merged = Extraction.mergeItems([a, b])
        #expect(merged.count == 3)
        let titles = merged.compactMap { ($0 as? [String: String])?["t"] }
        #expect(titles == ["x", "y", "z"])
    }

    @Test func itemsFromResultUnwrapsTheEnvelope() {
        let json = #"{"items":[{"title":"A"},{"title":"B"}]}"#
        let items = Extraction.itemsFromResult(json)
        #expect(items.count == 2)
        #expect((items[0] as? [String: String])?["title"] == "A")
    }

    @Test func itemsFromResultToleratesGarbage() {
        #expect(Extraction.itemsFromResult("not json").isEmpty)
        #expect(Extraction.itemsFromResult(#"{"other":1}"#).isEmpty)
    }

    @Test func rowsSchemaBuildsForAFieldList() throws {
        _ = try Extraction.rowsSchema(fields: ["title", "location", "apply_url"])
    }
}

@Suite("extract free-form JSON coercion")
struct ExtractAsJSONTests {
    @Test func passesThroughValidJSON() {
        #expect(ExtractData.asJSON(#"{"a":1}"#) == #"{"a":1}"#)
        #expect(ExtractData.asJSON(#"[1,2,3]"#) == #"[1,2,3]"#)
    }

    @Test func stripsCodeFences() {
        let fenced = "```json\n{\"a\":1}\n```"
        #expect(ExtractData.asJSON(fenced) == #"{"a":1}"#)
    }

    @Test func wrapsNonJSONAsText() {
        let out = ExtractData.asJSON("just prose")
        let obj = try! JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        #expect(obj["text"] as? String == "just prose")
    }
}
