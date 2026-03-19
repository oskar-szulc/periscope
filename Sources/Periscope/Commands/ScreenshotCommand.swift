import ArgumentParser
import Foundation

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Take a screenshot")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Output file path (optional)") var path: String?
    @Flag(name: .long, help: "Full page screenshot") var full: Bool = false

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.waitFor(.fetchquiet)
            let data = try await engine.takeScreenshot(full: full)
            if let path {
                try data.write(to: URL(fileURLWithPath: path))
                return .screenshot(path: path)
            } else {
                return .plain(data.base64EncodedString())
            }
        }
    }
}
