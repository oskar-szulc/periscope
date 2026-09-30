import Foundation

/// Bumped whenever `Request`, `Response`, or `CommandResult` change shape.
/// A client and daemon that disagree cannot safely talk, so the daemon shuts
/// down on mismatch and the client respawns it — see `DaemonClient`.
let periscopeProtocolVersion = 7

enum DaemonPaths {
    /// Everything periscope keeps: `~/.periscope`, or `PERISCOPE_DIR` to keep a
    /// project's sessions (and its own daemon) apart from the rest.
    static var base: URL {
        if let dir = ProcessInfo.processInfo.environment["PERISCOPE_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".periscope")
    }

    /// Runtime state lives beside the sessions it serves.
    static var runDirectory: URL { base.appendingPathComponent("run") }

    /// A unix socket path must fit sun_path (104 bytes on macOS). A deep
    /// PERISCOPE_DIR would not, and the daemon silently never started; such a
    /// socket goes in a per-user 0700 directory under /tmp, named by the
    /// directory's hash (FNV-1a: Swift's hashValue changes per process).
    static var socket: URL {
        let local = runDirectory.appendingPathComponent("sock")
        guard local.path.utf8.count >= 100 else { return local }
        let hash = runDirectory.path.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        return socketFallbackDirectory.appendingPathComponent(String(hash, radix: 16) + ".sock")
    }
    private static var socketFallbackDirectory: URL {
        URL(fileURLWithPath: "/tmp/periscope-\(getuid())", isDirectory: true)
    }
    static var log: URL { runDirectory.appendingPathComponent("daemon.log") }
    static var lock: URL { runDirectory.appendingPathComponent("lock") }

    /// The socket is the authentication boundary: 0700 on the directory means
    /// only the owning uid can reach it.
    static func ensureRunDirectory() throws {
        for dir in [runDirectory, socket.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // /tmp is shared: a directory someone else created first must not
            // hold our socket, or they could impersonate the daemon.
            var info = stat()
            guard lstat(dir.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
                throw PeriscopeError.sessionError(reason: "\(dir.path) is not a private directory owned by you")
            }
        }
    }
}

// MARK: - Wire types

struct GlobalOptionsPayload: Codable, Sendable {
    var session: String
    var noSession: Bool
    var json: Bool
    var timeout: Int
    var viewport: String
    var verbose: Bool

    // Interaction flags (--wait, --first/--strict) are not carried here: the
    // daemon re-parses the argument vector, so it reads them from argv, and a
    // duplicate on the wire could only drift out of sync with no consumer.
    init(_ g: GlobalOptions) {
        session = g.session
        noSession = g.noSession
        json = g.json
        timeout = g.timeout
        viewport = g.viewport
        verbose = g.verbose
    }

    /// Shares the parser's implementation so the two cannot drift on the
    /// fallback or the accepted spelling.
    var viewportSize: (width: Int, height: Int) { parseViewport(viewport) }
}

enum ControlVerb: String, Codable, Sendable {
    case status
    case stop
    /// Drop the live session named in `arguments[0]`, unsaved (`session delete`).
    case close
}

struct SessionInfoPayload: Codable, Sendable {
    var name: String
    var idleSeconds: Int
}

struct DaemonStatusPayload: Codable, Sendable {
    var pid: Int32
    var uptimeSeconds: Int
    var protocolVersion: Int
    var sessions: [SessionInfoPayload]
}

struct Request: Codable, Sendable {
    var protocolVersion: Int = periscopeProtocolVersion
    /// Lifecycle request rather than a browser command. Set by `daemon status|stop`.
    var control: ControlVerb?
    /// The full argument vector as the user typed it, minus argv[0].
    /// The daemon re-parses it with ArgumentParser so the client and daemon
    /// cannot drift on how a command is interpreted.
    var arguments: [String]
    /// The client's working directory. Without it, a relative path in a command
    /// (`screenshot shot.png`) resolves against the daemon's cwd -- silently
    /// writing to the wrong directory while reporting success.
    var workingDirectory: String?
    /// Absent for control requests, which are not commands and have no options.
    var options: GlobalOptionsPayload?
}

struct ErrorPayload: Codable, Sendable {
    var code: String
    var message: String
    var exitCode: Int32
    var url: String?
    /// For MULTIPLE_ELEMENTS_FOUND: unique selectors the caller can retry with.
    var candidates: [String]?

    init(code: String, message: String, exitCode: Int32, url: String? = nil) {
        self.code = code
        self.message = message
        self.exitCode = exitCode
        self.url = url
    }

    init(_ error: PeriscopeError) {
        self.init(code: error.wireCode, message: error.description, exitCode: error.exitCode)
        switch error {
        case .navigationFailed(let url, _) where !url.isEmpty, .blocked(_, let url):
            self.url = url
        case .multipleElementsFound(_, _, let candidates):
            self.candidates = candidates
        default:
            break
        }
    }
}

struct Response: Codable, Sendable {
    var result: CommandResult?
    var error: ErrorPayload?
    var status: DaemonStatusPayload?
    /// Emitted on the *client's* stderr. The daemon's own stderr is not the
    /// user's terminal, so degradation notices have to travel back over the wire.
    var warnings: [String] = []

    static func ok(_ result: CommandResult, warnings: [String] = []) -> Response {
        Response(result: result, error: nil, status: nil, warnings: warnings)
    }

    static func failure(_ error: ErrorPayload, warnings: [String] = []) -> Response {
        Response(result: nil, error: error, status: nil, warnings: warnings)
    }

    static func status(_ payload: DaemonStatusPayload) -> Response {
        Response(result: nil, error: nil, status: payload, warnings: [])
    }
}

extension PeriscopeError {
    /// Stable, machine-readable counterpart to `description`, so scripts can
    /// branch on failure without regex-matching English.
    var wireCode: String {
        switch self {
        case .elementNotFound: return "ELEMENT_NOT_FOUND"
        case .multipleElementsFound: return "MULTIPLE_ELEMENTS_FOUND"
        case .notActionable: return "ELEMENT_NOT_ACTIONABLE"
        case .navigationFailed: return "NAVIGATION_FAILED"
        case .timeout: return "TIMEOUT"
        case .sessionError: return "SESSION_ERROR"
        case .javaScriptError: return "JAVASCRIPT_ERROR"
        case .argumentError: return "ARGUMENT_ERROR"
        case .screenshotFailed: return "SCREENSHOT_FAILED"
        case .blocked: return "BLOCKED"
        }
    }
}
