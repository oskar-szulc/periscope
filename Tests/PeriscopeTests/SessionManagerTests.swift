import Testing
import Foundation
@testable import Periscope

@Suite("SessionManager")
struct SessionManagerTests {
    @Test func saveAndLoadState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com", title: "Example", viewport: "1920x1080")
        try manager.saveState(state, session: "test")
        let loaded = try manager.loadState(session: "test")
        #expect(loaded?.url == "https://example.com")
        #expect(loaded?.title == "Example")
    }

    @Test func listSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com", title: "Test", viewport: "1920x1080")
        try manager.saveState(state, session: "alpha")
        try manager.saveState(state, session: "beta")
        let sessions = try manager.listSessions()
        #expect(sessions.sorted() == ["alpha", "beta"])
    }

    @Test func deleteSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = SessionState(url: "https://example.com", title: "Test", viewport: "1920x1080")
        try manager.saveState(state, session: "deleteme")
        try manager.deleteSession("deleteme")
        let sessions = try manager.listSessions()
        #expect(!sessions.contains("deleteme"))
    }

    @Test func loadNonexistentSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SessionManager(baseDir: tempDir)
        let state = try manager.loadState(session: "nope")
        #expect(state == nil)
    }
}
