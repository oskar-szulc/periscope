import Foundation
import Testing

@testable import Periscope

@Suite("SessionManager")
struct SessionManagerTests {
    @Test func saveAndLoadState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com")
        try manager.write(state, "state.json", session: "test")
        let loaded = try manager.read(SessionState.self, "state.json", session: "test")
        #expect(loaded?.url == "https://example.com")
    }

    /// Snapshots written before the unread fields were dropped still load.
    @Test func loadsAnOlderStateFile() throws {
        let manager = SessionManager(baseDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try manager.write(
            ["url": "https://example.com", "title": "Example", "viewport": "1920x1080"], "state.json", session: "old")
        #expect(try manager.read(SessionState.self, "state.json", session: "old")?.url == "https://example.com")
    }

    @Test func listSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com")
        try manager.write(state, "state.json", session: "alpha")
        try manager.write(state, "state.json", session: "beta")
        let sessions = try manager.listSessions()
        #expect(sessions.sorted() == ["alpha", "beta"])
    }

    @Test func deleteSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com")
        try manager.write(state, "state.json", session: "deleteme")
        try manager.deleteSession("deleteme")
        let sessions = try manager.listSessions()
        #expect(!sessions.contains("deleteme"))
    }

    @Test func loadNonexistentSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = try manager.read(SessionState.self, "state.json", session: "nope")
        #expect(state == nil)
    }
}
