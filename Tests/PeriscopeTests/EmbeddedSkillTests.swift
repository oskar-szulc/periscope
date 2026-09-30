import Foundation
import Testing

@testable import Periscope

@Suite("embedded skill")
struct EmbeddedSkillTests {
    /// Fails when skills/periscope/ was edited without running scripts/embed-skill.sh.
    @Test func matchesTheSkillFolder() throws {
        let skill = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills/periscope")
        let onDisk = try FileManager.default.subpathsOfDirectory(atPath: skill.path)
            .filter { !$0.hasSuffix(".DS_Store") }
            .filter {
                var dir: ObjCBool = false;
                FileManager.default.fileExists(atPath: skill.appendingPathComponent($0).path, isDirectory: &dir);
                return !dir.boolValue
            }
        #expect(Set(onDisk) == Set(EmbeddedSkill.files.map(\.path)), "run scripts/embed-skill.sh")
        for file in EmbeddedSkill.files {
            let actual = try String(contentsOf: skill.appendingPathComponent(file.path), encoding: .utf8)
            #expect(actual == file.contents + "\n", "\(file.path) drifted: run scripts/embed-skill.sh")
        }
    }

    @Test func referenceMatchesPeriscopeMD() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let actual = try String(contentsOf: root.appendingPathComponent("PERISCOPE.md"), encoding: .utf8)
        #expect(actual == EmbeddedSkill.reference + "\n", "PERISCOPE.md drifted: run scripts/embed-skill.sh")
    }
}
