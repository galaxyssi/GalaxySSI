import XCTest
@testable import SignalASI

final class SignalASIAttachmentTests: XCTestCase {
  func testAttachmentDescriptorsMatchAndroidWireNames() {
    let attachment = SignalASIDraftAttachment(
      id: "att-1",
      displayName: "note.txt",
      mimeType: "text/plain",
      data: Data("hello".utf8)
    )

    let descriptors = SignalASIAttachmentPayloadBuilder.descriptors(for: [attachment])
    let item = descriptors.first

    XCTAssertEqual(item?["id"] as? String, "att-1")
    XCTAssertEqual(item?["name"] as? String, "note.txt")
    XCTAssertEqual(item?["mime_type"] as? String, "text/plain")
    XCTAssertEqual(item?["size"] as? Int, 5)
    XCTAssertEqual(item?["data_b64"] as? String, Data("hello".utf8).base64EncodedString())
    XCTAssertEqual(item?["transport_size"] as? Int, 5)
    XCTAssertEqual(item?["transport_lossless"] as? Bool, true)
    XCTAssertNotNil(item?["sha256"] as? String)
  }

  func testAttachmentDescriptorsRespectInlineBudget() {
    let large = SignalASIDraftAttachment(
      displayName: "large.bin",
      mimeType: "application/octet-stream",
      data: Data(repeating: 1, count: SignalASIAttachmentPayloadBuilder.maximumInlineBytes + 1)
    )

    let item = SignalASIAttachmentPayloadBuilder.descriptors(for: [large]).first

    XCTAssertNil(item?["data_b64"])
    XCTAssertEqual(item?["inline_status"] as? String, "metadata_only")
  }

  func testRejectsOversizedAndTooManyAttachments() {
    let oversized = SignalASIDraftAttachment(
      displayName: "huge.bin",
      mimeType: "application/octet-stream",
      data: Data(repeating: 0, count: SignalASIAttachmentPayloadBuilder.maximumAttachmentBytes + 1)
    )
    let small = SignalASIDraftAttachment(displayName: "a.txt", mimeType: "text/plain", data: Data("a".utf8))
    let existing = Array(repeating: small, count: SignalASIAttachmentPayloadBuilder.maximumAttachmentCount)

    XCTAssertFalse(SignalASIAttachmentPayloadBuilder.accepted(oversized, existing: []))
    XCTAssertFalse(SignalASIAttachmentPayloadBuilder.accepted(small, existing: existing))
  }

  func testSanitizesUnsafeNames() {
    XCTAssertEqual(SignalASIAttachmentPayloadBuilder.sanitizeName(" ..bad/name?.txt "), "bad_name_.txt")
    XCTAssertEqual(SignalASIAttachmentPayloadBuilder.sanitizeName(""), "attachment")
  }

  func testPhotoAttachmentDetectsPngMimeType() {
    let pngHeader = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
    let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
      data: pngHeader,
      suggestedName: "image.png"
    )

    XCTAssertEqual(attachment.mimeType, "image/png")
    XCTAssertTrue(attachment.isImage)
  }
}
