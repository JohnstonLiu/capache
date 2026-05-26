import XCTest
@testable import Capache

final class StandardSyncEncryptionTests: XCTestCase {
    func testNoteContentRoundTripsWithoutPlaintextInPayload() throws {
        let keyData = StandardSyncEncryption.generateKeyData()
        let content = StandardSyncEncryption.NoteContent(
            title: "Private title",
            rtfDataBase64: Data("Private rich text".utf8).base64EncodedString(),
            plainText: "Private body"
        )

        let encrypted = try StandardSyncEncryption.encryptNoteContent(content, keyData: keyData)
        XCTAssertFalse(encrypted.contains("Private title"))
        XCTAssertFalse(encrypted.contains("Private body"))

        let decrypted = try StandardSyncEncryption.decryptNoteContent(encrypted, keyData: keyData)
        XCTAssertEqual(decrypted, content)
    }

    func testHistoryContentRoundTrips() throws {
        let keyData = StandardSyncEncryption.generateKeyData()
        let content = StandardSyncEncryption.HistoryContent(
            rtfDataBase64: Data("Previous rich text".utf8).base64EncodedString(),
            plainText: "Previous body"
        )

        let encrypted = try StandardSyncEncryption.encryptHistoryContent(content, keyData: keyData)
        let decrypted = try StandardSyncEncryption.decryptHistoryContent(encrypted, keyData: keyData)

        XCTAssertEqual(decrypted, content)
    }

    func testInvalidKeyIsRejected() throws {
        let content = StandardSyncEncryption.NoteContent(
            title: "Private title",
            rtfDataBase64: "",
            plainText: "Private body"
        )

        XCTAssertThrowsError(
            try StandardSyncEncryption.encryptNoteContent(content, keyData: Data("short".utf8))
        )
    }
}
