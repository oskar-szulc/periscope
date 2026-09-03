import Foundation

/// Unix-socket plumbing shared by the daemon and its clients.
///
/// Both sides speak the same newline-framed protocol, so the framing lives once.
/// Keeping it in one place is not only about duplication: the two copies had
/// already drifted (only one cleared a dead socket file on a failed connect).
enum SocketIO {
    /// Read in chunks, not a byte at a time. A `read(2)` per byte costs one
    /// syscall per byte -- on a 1.8MB page that made a daemon round trip *slower*
    /// than running the command in-process, inverting the point of the daemon.
    static let chunkSize = 64 * 1024

    static func address(for path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strcpy(dst, src)
                }
            }
        }
        return addr
    }

    /// Connect to a listening socket.
    ///
    /// - Parameter clearIfDead: unlink the socket file when nothing is listening.
    ///   A client wants this (the file is a crashed daemon's leftover); a liveness
    ///   probe does not.
    static func connect(to path: String, clearIfDead: Bool = false) -> Int32? {
        guard FileManager.default.fileExists(atPath: path),
              var addr = address(for: path) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        guard connected == 0 else {
            close(fd)
            if clearIfDead { unlink(path) }
            return nil
        }
        return fd
    }

    /// Read one newline-terminated message. Returns the payload without the
    /// newline, as `Data` -- callers hand it straight to `JSONDecoder`, so no
    /// intermediate `String` (and its full UTF-8 validation pass) is built.
    static func readMessage(fd: Int32, maxBytes: Int) -> Data? {
        var message = Data()
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunkSize) }
            if n <= 0 { break }

            if let newline = chunk[0..<n].firstIndex(of: UInt8(ascii: "\n")) {
                message.append(contentsOf: chunk[0..<newline])
                break
            }
            message.append(contentsOf: chunk[0..<n])
            if message.count > maxBytes { return nil }
        }
        return message.isEmpty ? nil : message
    }

    @discardableResult
    static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    /// Poll a condition on a budget, checking before the first sleep and backing
    /// off from 2ms. A flat sleep-then-check imposed a full interval of latency on
    /// every cold start even when the daemon was already listening.
    static func poll(seconds: Double, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var interval: UInt32 = 2_000
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            usleep(interval)
            interval = min(interval * 2, 50_000)
        }
    }
}
