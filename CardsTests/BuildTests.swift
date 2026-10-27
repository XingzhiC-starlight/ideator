import XCTest
@testable import Ideator

final class BuildTests: XCTestCase {
    private let commit = "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"

    private func info(commit: String? = nil, dirty: String? = nil) -> [String: Any] {
        var info: [String: Any] = ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "57"]
        if let commit { info["IdeatorCommit"] = commit }
        if let dirty { info["IdeatorTreeDirty"] = dirty }
        return info
    }

    func testABuildFromACleanTreeReadsItsCommitAndSaysItIsClean() {
        let build = BuildInfo(info: info(commit: commit, dirty: "NO"))

        XCTAssertEqual(build.stamp?.commit, commit)
        XCTAssertEqual(build.stamp?.dirty, false)
        XCTAssertEqual(build.versionLine, "Version 0.9 (57), commit 1a2b3c4")
    }

    func testABuildFromADirtyTreeSaysItHadLocalChanges() {
        let build = BuildInfo(info: info(commit: commit, dirty: "YES"))

        XCTAssertEqual(build.stamp?.dirty, true)
        XCTAssertEqual(build.versionLine, "Version 0.9 (57), commit 1a2b3c4 with local changes")
    }

    func testABuildFromXcodeHasNoStampBecauseTheProjectDefaultsAreNoneAndUnknown() {
        let build = BuildInfo(info: info(commit: "none", dirty: "unknown"))

        XCTAssertNil(build.stamp)
        XCTAssertEqual(build.versionLine, "Version 0.9 (57), a development build")
    }

    func testAPlistWithoutTheStampKeysHasNoStamp() {
        XCTAssertNil(BuildInfo(info: info()).stamp, "an app built before the stamp existed")
        XCTAssertNil(BuildInfo(info: info(commit: commit)).stamp)
        XCTAssertNil(BuildInfo(info: info(dirty: "NO")).stamp)
    }

    func testACommitThatIsNotFortyLowercaseHexDigitsIsNoStamp() {
        let malformed = [
            String(commit.prefix(39)),
            commit + "0",
            String(commit.prefix(7)),
            commit.uppercased(),
            String(commit.dropLast()) + "g",
            commit + "\n",
            " " + String(commit.dropLast()),
            "",
        ]
        for bad in malformed {
            XCTAssertNil(BuildInfo(info: info(commit: bad, dirty: "NO")).stamp, "'\(bad)'")
        }
        XCTAssertNil(BuildInfo(info: ["IdeatorCommit": 12345, "IdeatorTreeDirty": "NO"]).stamp, "not even a string")
    }

    func testAnUnknownTreeStateIsNeverReadAsClean() {
        for state in ["unknown", "", "no", "yes", "true", "false", "clean", "NO "] {
            XCTAssertNil(BuildInfo(info: info(commit: commit, dirty: state)).stamp, "'\(state)'")
        }
    }

    func testTheLabelIsTheVersionAndTheBuildNumber() {
        XCTAssertEqual(BuildInfo(info: info()).label, "0.9 (57)")
    }

    func testTheRunningAppsPlistCarriesBothStampKeysWithTheirBuildSettingsExpanded() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)

        for key in ["IdeatorCommit", "IdeatorTreeDirty"] {
            let value = try XCTUnwrap(plist[key] as? String, key)
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertFalse(value.contains("$("), "\(key) is '\(value)': the build setting was not expanded")
        }
        XCTAssertEqual(BuildInfo.current.version, plist["CFBundleShortVersionString"] as? String)
    }
}
