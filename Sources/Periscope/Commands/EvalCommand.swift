import ArgumentParser
import Foundation

struct Eval: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "eval", abstract: "Execute JavaScript and print the result")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "JavaScript code") var code: String?
    @Option(name: .long, help: "Execute JS from a file") var file: String?

    func validate() throws {
        guard code != nil || file != nil else {
            throw PeriscopeError.argumentError(reason: "Provide JS code or use --file")
        }
    }

    func run() throws {
        // Read here, not inside the block: the block runs later on the MainActor,
        // after the daemon's interception context -- which knows the client's
        // directory -- has been torn down.
        let script =
            try file.map {
                try String(
                    contentsOf: URL(fileURLWithPath: CommandRunner.resolvePath($0)),
                    encoding: .utf8)
            } ?? code!

        CommandRunner.run(globals: globals) { engine in
            // callJavaScript treats the script as a function body, so user
            // scripts that are simple expressions work with auto-prepended return.
            // For multi-statement scripts, wrap in eval() so the last expression
            // value is returned. This is safe here since the eval command's entire
            // purpose is to execute arbitrary user-provided JavaScript.
            let result: Any?
            if script.contains(";") || script.contains("\n") {
                result = try await engine.runJavaScript("eval(\(ElementResolver.jsString(script)))")
            } else {
                result = try await engine.runJavaScript(script)
            }
            let str: String?
            if let result {
                if let s = result as? String {
                    str = s
                } else if let n = result as? NSNumber {
                    str = n.stringValue
                } else if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]),
                    let json = String(data: data, encoding: .utf8)
                {
                    str = json
                } else {
                    str = String(describing: result)
                }
            } else {
                str = nil
            }
            return .jsResult(value: str)
        }
    }
}
