import XCTest
@testable import Ideator

final class BuildTests: XCTestCase {
    private let commit = "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d"
    private let production = "https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml"
    private let releaseKey = "aU79Ryz97RGp9XiQfDRmXkV4198Z8g6cp+8nhrIpaJ4="
    private let localFeed = "http://localhost:8765/appcast.xml"

    private func info(commit: String? = nil, dirty: String? = nil, feed: String? = nil, key: String? = nil,
                      updateTest: Any? = nil) -> [String: Any] {
        var info: [String: Any] = ["CFBundleShortVersionString": "0.9", "CFBundleVersion": "57"]
        if let commit { info["IdeatorCommit"] = commit }
        if let dirty { info["IdeatorTreeDirty"] = dirty }
        if let feed { info["SUFeedURL"] = feed }
        if let key { info["SUPublicEDKey"] = key }
        if let updateTest { info["IdeatorUpdateTest"] = updateTest }
        return info
    }

    private func release(feed: String? = nil, updateTest: Any? = nil) -> [String: Any] {
        info(commit: commit, dirty: "NO", feed: feed ?? production, key: releaseKey, updateTest: updateTest)
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

    func testAnHttpsFeedWithAnEd25519PublicKeyIsTheFeed() throws {
        let feed = try XCTUnwrap(BuildInfo(info: release()).feed)

        XCTAssertEqual(feed.url.absoluteString, production)
    }

    func testAFeedWithoutAURLOrAUsableKeyIsNoFeed() {
        XCTAssertNil(BuildInfo(info: info(key: releaseKey)).feed, "no SUFeedURL")
        let keys = [nil, "", "not a key", String(releaseKey.dropLast(4)), releaseKey + "AAAA",
                    Data(repeating: 7, count: 31).base64EncodedString(), Data(repeating: 7, count: 33).base64EncodedString()]
        for key in keys {
            XCTAssertNil(BuildInfo(info: info(feed: production, key: key)).feed, "key '\(key ?? "nil")'")
        }
    }

    func testPlainHttpIsRefusedOutsideAnUpdateTestBuild() {
        for url in [localFeed, "http://127.0.0.1:8765/appcast.xml", "http://github.com/appcast.xml"] {
            XCTAssertNil(BuildInfo(info: release(feed: url)).feed, url)
            XCTAssertNil(BuildInfo(info: release(feed: url, updateTest: "NO")).feed, url)
        }
    }

    func testAnUpdateTestBuildTakesPlainHttpOnlyFromThisMac() {
        for url in [localFeed, "http://127.0.0.1:8765/appcast.xml", production] {
            XCTAssertEqual(BuildInfo(info: release(feed: url, updateTest: "YES")).feed?.url.absoluteString, url)
        }
        let elsewhere = ["http://example.com/appcast.xml", "http://localhost.example.com/appcast.xml",
                         "http://127.0.0.1@example.com/appcast.xml", "file:///tmp/appcast.xml", "ftp://localhost/appcast.xml",
                         "HTTP://localhost/appcast.xml", "localhost/appcast.xml", ""]
        for url in elsewhere {
            XCTAssertNil(BuildInfo(info: release(feed: url, updateTest: "YES")).feed, url)
        }
    }

    func testOnlyTheStringYESMakesAnUpdateTestBuild() {
        XCTAssertTrue(BuildInfo(info: release(updateTest: "YES")).isUpdateTest)
        for value: Any in ["NO", "yes", "true", "", true, 1] {
            XCTAssertFalse(BuildInfo(info: release(updateTest: value)).isUpdateTest, "\(value)")
        }
        XCTAssertFalse(BuildInfo(info: release()).isUpdateTest, "no key at all")
    }

    func testAReleaseBuildChecksItsFeed() throws {
        let build = BuildInfo(info: release())

        XCTAssertEqual(build.plan(isScratch: false), .check(try XCTUnwrap(build.feed)))
    }

    func testABuildThatPackageShDidNotStampNeverChecks() {
        let xcode = BuildInfo(info: info(commit: "none", dirty: "unknown", feed: production, key: releaseKey))
        XCTAssertEqual(xcode.plan(isScratch: false), .off(.notPackaged))
        XCTAssertEqual(xcode.plan(isScratch: true), .off(.notPackaged))

        let testCopy = BuildInfo(info: info(commit: "none", dirty: "unknown", feed: localFeed, key: releaseKey,
                                            updateTest: "YES"))
        XCTAssertEqual(testCopy.plan(isScratch: true), .off(.notPackaged), "the test exception is for scratch runs, not stamps")
    }

    func testAStampedBuildWithoutAFeedItMayUseNeverChecks() {
        XCTAssertEqual(BuildInfo(info: info(commit: commit, dirty: "NO")).plan(isScratch: false), .off(.notPackaged))
        XCTAssertEqual(BuildInfo(info: release(feed: localFeed)).plan(isScratch: false), .off(.notPackaged))
    }

    func testAScratchRunOfTheRealAppNeverChecksBecauseSparkleWouldWriteToTheOwnersDefaults() {
        XCTAssertEqual(BuildInfo(info: release()).plan(isScratch: true), .off(.scratchRun))
    }

    func testAScratchRunOfAnUpdateTestCopyChecksItsOwnFeed() throws {
        let build = BuildInfo(info: release(feed: localFeed, updateTest: "YES"))
        let feed = try XCTUnwrap(build.feed)

        XCTAssertEqual(build.plan(isScratch: true), .check(feed))
        XCTAssertEqual(feed.url.absoluteString, localFeed)
    }

    func testTheShippedPlistChecksTheProductionFeedWithTheReleaseKeyAndIsNoUpdateTest() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)
        let feed = try XCTUnwrap(BuildInfo.current.feed, "the plist's SUFeedURL and SUPublicEDKey parse")

        XCTAssertEqual(feed.url.absoluteString, production)
        XCTAssertEqual(plist["SUPublicEDKey"] as? String, releaseKey)
        XCTAssertNil(plist["IdeatorUpdateTest"])
        XCTAssertFalse(BuildInfo.current.isUpdateTest)
    }

    func testTheShippedCheckIntervalIsTheOnceADayThatSettingsAndTheWelcomeCardSay() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(plist["SUScheduledCheckInterval"] as? Int, 86400)
        XCTAssertTrue(SettingsCopy.Privacy.page(for: nil).allText.contains("Once a day"))
        let welcome = WelcomeCopy().disclosures.map(\.text).joined()
        XCTAssertTrue(welcome.contains("Once a day"))
    }

    func testTheShippedPlistNeverProfilesTheMacOrInstallsWithoutAsking() throws {
        let plist = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(plist["SUEnableSystemProfiling"] as? Bool, false, "PRIVACY.md: no system profile")
        XCTAssertEqual(plist["SUAllowsAutomaticUpdates"] as? Bool, false, "Ideator asks before it installs")
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true, "on, without Sparkle's second-launch prompt")
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true)
        XCTAssertNil(plist["NSAppTransportSecurity"], "https only; this Mac's loopback needs no exception")
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
