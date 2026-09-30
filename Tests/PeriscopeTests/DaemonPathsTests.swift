import Foundation
import Testing

@testable import Periscope

/// Serialized: both tests set PERISCOPE_DIR, which is process-wide.
@Suite("daemon paths", .serialized)
struct DaemonPathsTests {
    @Test func shortDirKeepsItsSocketInside() {
        setenv("PERISCOPE_DIR", "/tmp/p", 1); defer { unsetenv("PERISCOPE_DIR") }
        #expect(DaemonPaths.socket.path == "/tmp/p/run/sock")
        #expect(SessionManager().baseDir.path == "/tmp/p/sessions")
    }

    /// sun_path holds 104 bytes; a deep project dir must still get a daemon.
    @Test func deepDirMovesItsSocketToAStableShortPath() {
        let deep = "/tmp/" + String(repeating: "nested-directory/", count: 8)
        setenv("PERISCOPE_DIR", deep, 1); defer { unsetenv("PERISCOPE_DIR") }
        let socket = DaemonPaths.socket.path
        #expect(socket.utf8.count < 104)
        #expect(socket.hasPrefix("/tmp/periscope-\(getuid())/"))
        #expect(DaemonPaths.socket.path == socket)  // stable across calls
    }
}
