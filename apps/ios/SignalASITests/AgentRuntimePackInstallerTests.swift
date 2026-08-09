import CryptoKit
import Foundation
import XCTest

final class AgentRuntimePackInstallerTests: XCTestCase {
  func testRuntimePackInstallerActivatesSignedPackAndReplacesExistingPack() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-pack-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let image = Data("runtime-image".utf8)
    let manifest = AgentRuntimePackManifest(
      id: "linux-base",
      version: "1.0.0",
      architecture: AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first ?? "x86_64",
      imageFile: "linux-base.img",
      imageSha256: SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined(),
      capabilities: ["shell.execute"],
      dependencies: [],
      installedSizeBytes: 1_024 * 1_024,
      license: "Apache-2.0",
      signatureKeyId: String(repeating: "0", count: 64),
      signature: "test-signature",
      archiveSizeBytes: 1
    )
    let manifestData = try JSONEncoder().encode(manifest)
    let archiveData = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: "manifest.json", data: manifestData),
      AgentRuntimeProjectArchiveEntry(path: "linux-base.img", data: image)
    ])
    let source = root.appendingPathComponent("linux-base.sarpack")
    try archiveData.write(to: source)

    let installer = AgentIOSRuntimePackInstaller(
      runtimeRootURL: root,
      hostVersionCode: 1,
      signatureVerifier: { _ in true }
    )
    let first = try installer.install(source: source)
    XCTAssertEqual(first.packId, "linux-base")
    XCTAssertFalse(first.replacedExisting)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: root.appendingPathComponent("packs/linux-base/linux-base.img").path
    ))

    let second = try installer.install(source: source)
    XCTAssertTrue(second.replacedExisting)
  }

  func testRuntimePackArchiveRejectsUnsafePaths() throws {
    let archive = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: "../manifest.json", data: Data("{}".utf8))
    ])
    XCTAssertThrowsError(try AgentRuntimePackArchiveReader.inspect(archive))
  }
}
