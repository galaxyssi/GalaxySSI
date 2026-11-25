import CryptoKit
import Foundation
import XCTest

final class AgentRuntimePackInstallerTests: XCTestCase {
  func testInstalledVersionComesOnlyFromReadyManifestWithoutChangingStoredState() throws {
    var manifest = AgentRuntimePackManifest(
      id: "node-js", version: "22.0.0", architecture: "arm64",
      imageFile: "node.img", imageSha256: String(repeating: "0", count: 64),
      capabilities: [], dependencies: [], installedSizeBytes: 1,
      license: "MIT", signatureKeyId: "test", signature: "test"
    )
    let installed = AgentRuntimePackStatus(id: "node-js", state: .ready, manifest: manifest)
    let before = try JSONEncoder().encode(installed)
    XCTAssertEqual(installed.installedVersion, "22.0.0")
    XCTAssertEqual(installed.manifest?.version, "22.0.0")
    let decoded = try JSONDecoder().decode(AgentRuntimePackStatus.self, from: before)
    XCTAssertEqual(decoded, installed)
    XCTAssertEqual(decoded.installedVersion, "22.0.0")
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
    XCTAssertNil(encoded["installedVersion"])
    XCTAssertNil(encoded["installed_version"])
    for state in AgentRuntimePackState.allCases where state != .ready {
      XCTAssertNil(AgentRuntimePackStatus(id: "node-js", state: state, manifest: manifest).installedVersion)
    }
    XCTAssertNil(AgentRuntimePackStatus(id: "node-js", state: .ready).installedVersion)
    manifest.version = " \n "
    XCTAssertNil(AgentRuntimePackStatus(id: "node-js", state: .ready, manifest: manifest).installedVersion)
    manifest.version = " 22.0.0 \n"
    XCTAssertEqual(AgentRuntimePackStatus(id: "node-js", state: .ready, manifest: manifest).installedVersion, "22.0.0")
    XCTAssertEqual(manifest.version, " 22.0.0 \n")
  }

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

    var androidManifest = manifest
    androidManifest.architecture = "arm64-v8a"
    let androidArchive = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: "manifest.json", data: try JSONEncoder().encode(androidManifest)),
      AgentRuntimeProjectArchiveEntry(path: "linux-base.img", data: image)
    ])
    let androidSource = root.appendingPathComponent("android-linux-base.sarpack")
    try androidArchive.write(to: androidSource)
    XCTAssertThrowsError(try installer.install(source: androidSource)) { error in
      XCTAssertTrue(error.localizedDescription.contains("incompatible with this iOS device"))
    }

    XCTAssertTrue(try installer.uninstall(packId: "linux-base"))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: root.appendingPathComponent("packs/linux-base").path
    ))
    XCTAssertFalse(try installer.uninstall(packId: "linux-base"))
  }

  func testRuntimePackArchiveRejectsUnsafePaths() throws {
    let archive = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: [
      AgentRuntimeProjectArchiveEntry(path: "../manifest.json", data: Data("{}".utf8))
    ])
    XCTAssertThrowsError(try AgentRuntimePackArchiveReader.inspect(archive))
  }

  func testCachedRuntimePackStatusSkipsImageDigestUntilExecutionValidation() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-pack-cached-status-tests-\(UUID().uuidString)", isDirectory: true)
    let packDirectory = root.appendingPathComponent("packs/linux-base", isDirectory: true)
    try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let image = Data("runtime-image".utf8)
    let manifest = AgentRuntimePackManifest(
      id: "linux-base",
      version: "1.0.0",
      architecture: AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first ?? "x86_64",
      imageFile: "linux-base.img",
      imageSha256: String(repeating: "0", count: 64),
      capabilities: ["shell.execute"],
      dependencies: [],
      installedSizeBytes: 1_024 * 1_024,
      license: "Apache-2.0",
      signatureKeyId: String(repeating: "0", count: 64),
      signature: "test-signature",
      archiveSizeBytes: 1
    )
    try JSONEncoder().encode(manifest).write(to: packDirectory.appendingPathComponent("manifest.json"))
    try image.write(to: packDirectory.appendingPathComponent("linux-base.img"))

    let installer = AgentIOSRuntimePackInstaller(
      runtimeRootURL: root,
      hostVersionCode: 1,
      signatureVerifier: { _ in true }
    )

    XCTAssertEqual(installer.cachedStatus(packId: "linux-base").state, .ready)
    XCTAssertEqual(installer.status(packId: "linux-base").state, .invalid)
  }

  func testRuntimePackCatalogBuildsDependencyFirstInstallationPlan() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-catalog-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let architecture = AgentRuntimePackCatalogPolicy.defaultSupportedArchitectures.first ?? "x86_64"
    let linux = AgentRuntimePackCatalogEntry(
      packId: "linux-base",
      version: "1.0.0",
      architecture: architecture,
      downloadUrl: "https://example.com/linux-base.sarpack",
      archiveSha256: String(repeating: "a", count: 64),
      archiveSizeBytes: 1,
      installedSizeBytes: 1,
      dependencies: [],
      license: "Apache-2.0",
      minimumHostVersionCode: 1,
      guestApiVersion: 1
    )
    let python = AgentRuntimePackCatalogEntry(
      packId: "python-uv",
      version: "1.0.0",
      architecture: architecture,
      downloadUrl: "https://example.com/python-uv.sarpack",
      archiveSha256: String(repeating: "b", count: 64),
      archiveSizeBytes: 1,
      installedSizeBytes: 1,
      dependencies: ["linux-base"],
      license: "Apache-2.0",
      minimumHostVersionCode: 1,
      guestApiVersion: 1
    )
    let catalog = AgentRuntimePackCatalog(
      catalogVersion: "1.0.0",
      generatedAtMillis: 1_000,
      expiresAtMillis: 10_000,
      entries: [python, linux],
      signatureKeyId: String(repeating: "0", count: 64),
      signature: "test-signature"
    )
    try AgentIOSRuntimePackCatalogStore(runtimeRootURL: root).save(catalog)
    let manager = AgentIOSRuntimePackCatalogManager(
      runtimeRootURL: root,
      hostVersionCode: 1,
      nowMillis: { 5_000 },
      signatureVerifier: { _ in true }
    )

    let plan = try manager.installationPlan(for: python)
    XCTAssertEqual(plan.map(\.packId), ["linux-base", "python-uv"])
  }
}
