import Foundation

// Not `PeriscopeRoot.main()`: ArgumentParser exits 1 for any error it does not
// know, so a PeriscopeError thrown before a command starts (an invalid URL or
// --until) lost its documented exit code, 4 for an argument error.
do {
    var command = try PeriscopeRoot.parseAsRoot()
    try command.run()
} catch let error as PeriscopeError {
    FileHandle.standardError.write(Data((TextFormatter().formatError(ErrorPayload(error)) + "\n").utf8))
    exit(error.exitCode)
} catch {
    PeriscopeRoot.exit(withError: error)
}
