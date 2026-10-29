import XCTest

final class TestDefaultsTests: XCTestCase {
    private let preferencesFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences")

    private func suiteToken(_ name: String) -> String {
        name.split(separator: "/").map(String.init).first { $0.hasPrefix("IdeatorTests-") } ?? name
    }

    private func preferencesFiles(containing token: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: preferencesFolder.path)) ?? []
        return files.filter { $0.contains(token) }
    }

    func testTearingDownLeavesNoPlistForTheSuite() throws {
        let suites = TestDefaults()
        let defaults = suites.make()
        defaults.set("kept", forKey: "probe")
        XCTAssertEqual(defaults.string(forKey: "probe"), "kept", "the suite works until it is torn down")
        let name = try XCTUnwrap(suites.names.first)
        let token = suiteToken(name)

        suites.removeAll()

        XCTAssertEqual(preferencesFiles(containing: token), [], "no plist for this suite in ~/Library/Preferences")
        XCTAssertFalse(FileManager.default.fileExists(atPath: name + ".plist"), "no plist at the suite's own path")
    }

    func testTwoSuitesDoNotShareValues() {
        let suites = TestDefaults()
        defer { suites.removeAll() }
        let first = suites.make()
        let second = suites.make()

        first.set("only here", forKey: "probe")

        XCTAssertNil(second.string(forKey: "probe"))
    }
}
