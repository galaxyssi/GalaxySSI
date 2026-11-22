import XCTest
@testable import GalaxySSI

final class AgentPeerAttachmentPreviewTests: XCTestCase {
  func testCanonicalPDFMimeMatchesAndroidWithoutOverridingSpecificTypes() {
    for declared in ["", "application/octet-stream", "binary/octet-stream", "*/*"] {
      XCTAssertEqual(AgentPeerAttachmentPreview.mimeType(name: "REPORT.PDF", declared: declared), "application/pdf")
    }
    XCTAssertEqual(AgentPeerAttachmentPreview.mimeType(name: "report.bin", declared: " Application/X-PDF; version=1.7 "), "application/pdf")
    XCTAssertEqual(AgentPeerAttachmentPreview.mimeType(name: "report.pdf", declared: "image/png"), "image/png")
    XCTAssertEqual(AgentPeerAttachmentPreview.mimeType(name: "blob", declared: "*/*"), "application/octet-stream")
    XCTAssertEqual(AgentPeerAttachmentPreview.previewName(name: "report.bin", declared: "application/x-pdf"), "report.pdf")
    XCTAssertEqual(AgentPeerAttachmentPreview.previewName(name: "../../report", declared: "application/pdf"), "report.pdf")
    XCTAssertEqual(AgentPeerAttachmentPreview.previewName(name: "..", declared: "application/pdf"), "GalaxySSI-attachment.pdf")
  }

  func testPreviewUsesTemporaryReadOnlyCopyAndCleanupPreservesOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("private-original.bin")
    let bytes = Data("synthetic-pdf-fixture".utf8)
    try bytes.write(to: source)
    let lease = try AgentPeerAttachmentPreview.prepare(source: source, name: "report.bin", declared: "application/x-pdf",
      temporaryDirectory: root)
    XCTAssertNotEqual(lease.file, source)
    XCTAssertEqual(lease.file.lastPathComponent, "report.pdf")
    XCTAssertEqual(try Data(contentsOf: lease.file), bytes)
    let permissions = try FileManager.default.attributesOfItem(atPath: lease.file.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o400)
    AgentPeerAttachmentPreview.release(lease)
    AgentPeerAttachmentPreview.release(lease)
    XCTAssertFalse(FileManager.default.fileExists(atPath: lease.directory.path))
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testUnreadableRemoteDirectoryAndSymlinkSourcesAreRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.pdf")
    try Data("fixture".utf8).write(to: source)
    let symlink = root.appendingPathComponent("alias.pdf")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
    for url in [root, symlink, root.appendingPathComponent("missing.pdf"), URL(string: "https://example.test/report.pdf")!] {
      XCTAssertThrowsError(try AgentPeerAttachmentPreview.prepare(source: url, name: "report.pdf", declared: "application/pdf",
        temporaryDirectory: root)) { error in
        XCTAssertEqual(error as? AgentPeerAttachmentPreview.Failure, .unreadable)
      }
    }
  }

  func testCleanupDoesNotDeleteAnOriginalOutsideAPreviewLease() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("original.pdf")
    try Data("fixture".utf8).write(to: source)
    AgentPeerAttachmentPreview.release(.init(file: source, directory: root))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }
}
