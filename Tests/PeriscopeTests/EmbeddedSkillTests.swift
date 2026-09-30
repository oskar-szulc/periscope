import Foundation
import Testing

@testable import Periscope

@Suite("embedded skill")
struct EmbeddedSkillTests {
    /// Fails when skill/ was edited without running scripts/embed-skill.sh.
    @Test func matchesTheSkillFolder() throws {
        let skill = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skill")
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
}
