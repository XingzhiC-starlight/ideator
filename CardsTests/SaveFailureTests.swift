import XCTest
@testable import Ideator

final class SaveFailureTests: XCTestCase {
    private let documents = URL(filePath: "/Users/someone/Documents", directoryHint: .isDirectory)

    func testAFolderInDocumentsTellsWhereToAllowAccessAgain() {
        let text = DeskController.saveFailureText(folder: documents.appending(path: "Ideator"), documents: documents)

        XCTAssertTrue(text.contains("couldn't write to /Users/someone/Documents/Ideator"))
        XCTAssertTrue(text.contains("System Settings › Privacy & Security › Files & Folders"))
    }

    func testAFolderElsewhereDoesNotMentionTheDocumentsPrompt() {
        let text = DeskController.saveFailureText(folder: URL(filePath: "/Volumes/Notes/Ideator"), documents: documents)

        XCTAssertTrue(text.contains("couldn't write to /Volumes/Notes/Ideator"))
        XCTAssertFalse(text.contains("Files & Folders"))
    }

    func testADocumentsLookalikeIsNotInsideDocuments() {
        let text = DeskController.saveFailureText(folder: URL(filePath: "/Users/someone/Documents-old/Ideator"),
                                                  documents: documents)

        XCTAssertFalse(text.contains("Files & Folders"))
    }
}
