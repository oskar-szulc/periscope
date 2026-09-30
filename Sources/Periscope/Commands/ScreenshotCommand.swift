import ArgumentParser
import Foundation

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Take a screenshot")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Output file path (optional)") var path: String?
    @Flag(name: .long, help: "Full page screenshot") var full: Bool = false

    func run() throws {
        // Resolved here, not inside the block: the block runs later on the
        // MainActor, by which time the daemon's interception context -- which is
        // what knows the client's directory -- has been torn down.
        let destination = path.map(CommandRunner.resolvePath)

        CommandRunner.run(globals: globals) { engine in
            try await engine.waitFor(.fetchquiet(maxMs: nil))
            try await engine.settleForCapture()
            let data = try await engine.takeScreenshot(full: full)
            if let destination, let path {
                try data.write(to: URL(fileURLWithPath: destination))
                return .screenshot(path: path)
            } else {
                return .plain(data.base64EncodedString())
            }
        }
    }
}
