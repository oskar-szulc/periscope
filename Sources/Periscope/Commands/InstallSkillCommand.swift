import ArgumentParser
import Foundation

/// Writes the embedded skill (skill/ at build time) where an agent finds it,
/// so a Homebrew or release install needs no clone of this repo.
struct InstallSkill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-skill",
        abstract: "Install the periscope agent skill into this project, or --global")
    @Flag(name: .long, help: "Claude Code: .claude/skills/periscope (the default)") var claude = false
    @Flag(name: .long, help: "Codex and other agents: .agents/skills/periscope") var codex = false
    @Flag(name: .long, help: "Both") var all = false
    @Flag(name: .long, help: "Under your home directory instead of the current one") var global = false

    func run() throws {
        let base = global ? FileManager.default.homeDirectoryForCurrentUser
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var roots: [String] = []
        if claude || all || !codex { roots.append(".claude/skills") }
        if codex || all { roots.append(".agents/skills") }

        for root in roots {
            let dir = base.appendingPathComponent(root).appendingPathComponent("periscope")
            // A symlinked skill (a checkout's skill/ linked in) is its own
            // source of truth; writing through it would edit that checkout.
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: dir.path) {
                print("skipped \(dir.path): a symlink to \(target)")
                continue
            }
            for file in EmbeddedSkill.files {
                let url = dir.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (file.contents + "\n").write(to: url, atomically: true, encoding: .utf8)
                if file.executable {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
            print("installed \(dir.path)")
        }
    }
}
