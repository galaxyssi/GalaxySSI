import XCTest
@testable import GalaxySSI

final class VoiceWhisperModelStorageTests: XCTestCase {
  func testVerifiedFileIsInstalledWithMetadata() throws {
    let env = try Environment()
    let source = try env.writeFile(named: "source.bin", contents: "verified-model")
    let profile = try env.profile(for: source)

    let metadata = try env.storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test")
    let snapshot = env.storage.inspect(profile)

    XCTAssertTrue(snapshot.installed)
    XCTAssertEqual(snapshot.state, .installedUncertified)
    XCTAssertEqual(metadata.sha256, profile.sha256)
    XCTAssertEqual(try Data(contentsOf: env.storage.finalFileURL(for: profile)), try Data(contentsOf: source))
    XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.stagingFileURL(for: profile).path))
    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)
  }

  func testTruncatedAndCorruptFilesNeverReplaceVerifiedInstall() throws {
    let env = try Environment()
    let valid = try env.writeFile(named: "valid.bin", contents: "trusted-model")
    let profile = try env.profile(for: valid)
    _ = try env.storage.install(sourceFileURL: valid, profile: profile, sourceLabel: "valid")

    let truncated = try env.writeFile(named: "truncated.bin", contents: "bad")
    XCTAssertThrowsError(try env.storage.install(sourceFileURL: truncated, profile: profile, sourceLabel: "truncated")) { error in
      XCTAssertEqual((error as? VoiceWhisperModelInstallError)?.failure, .sizeMismatch)
    }
    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)

    let corrupt = try env.writeFile(named: "corrupt.bin", contents: String(repeating: "x", count: "trusted-model".count))
    XCTAssertThrowsError(try env.storage.install(sourceFileURL: corrupt, profile: profile, sourceLabel: "corrupt")) { error in
      XCTAssertEqual((error as? VoiceWhisperModelInstallError)?.failure, .sha256Mismatch)
    }
    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)
  }

  func testCancellationBeforeCommitPreservesVerifiedInstall() throws {
    let env = try Environment()
    let original = try env.writeFile(named: "original.bin", contents: "trusted-model")
    let replacement = try env.writeFile(named: "replacement.bin", contents: "trusted-model")
    let profile = try env.profile(for: original)
    _ = try env.storage.install(sourceFileURL: original, profile: profile, sourceLabel: "original")

    XCTAssertThrowsError(
      try env.storage.install(
        sourceFileURL: replacement,
        profile: profile,
        sourceLabel: "replacement",
        beforeCommit: { throw CancellationError() }
      )
    )

    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)
    XCTAssertEqual(env.storage.inspect(profile).metadata?.source, "original")
    XCTAssertFalse(FileManager.default.fileExists(atPath: env.storage.stagingFileURL(for: profile).path))
  }

  func testTamperingAfterInstallBlocksNativeLoad() throws {
    let env = try Environment()
    let source = try env.writeFile(named: "model.bin", contents: "original-data")
    let profile = try env.profile(for: source)
    _ = try env.storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test")

    let installed = env.storage.finalFileURL(for: profile)
    let priorModified = try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date
    try Data("modified-data".utf8).write(to: installed)
    if let priorModified {
      try FileManager.default.setAttributes(
        [.modificationDate: priorModified.addingTimeInterval(2)],
        ofItemAtPath: installed.path
      )
    }

    XCTAssertFalse(env.storage.inspect(profile).installed)
    XCTAssertFalse(env.storage.verifyForNativeLoad(profile).valid)
  }

  func testInsufficientSpaceDeleteProtectionAndStalePartials() throws {
    var now: Int64 = 20_000
    let env = try Environment(clock: { now })
    let source = try env.writeFile(named: "space.bin", contents: "12345678")
    let profile = try env.profile(for: source, reserve: 20)

    XCTAssertThrowsError(
      try env.storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test", availableBytes: 27)
    ) { error in
      XCTAssertEqual((error as? VoiceWhisperModelInstallError)?.failure, .insufficientSpace)
    }

    _ = try env.storage.install(sourceFileURL: source, profile: profile, sourceLabel: "test", availableBytes: 100)
    XCTAssertThrowsError(try env.storage.delete(profile, active: true)) { error in
      XCTAssertEqual((error as? VoiceWhisperModelInstallError)?.failure, .modelInUse)
    }

    let partial = env.storage.stagingFileURL(for: profile)
    try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("partial".utf8).write(to: partial)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)],
      ofItemAtPath: partial.path
    )
    now = 30_000

    XCTAssertEqual(env.storage.cleanupStalePartials(maxAgeMillis: 10_000), 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
  }

  private final class Environment {
    let root: URL
    let storage: VoiceWhisperModelStorage

    init(clock: @escaping () -> Int64 = { 10_000 }) throws {
      let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      root = rootURL
      try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: rootURL, catalogVersion: "test", clockMillis: clock)
    }

    func writeFile(named name: String, contents: String) throws -> URL {
      let url = root.appendingPathComponent(name, isDirectory: false)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func profile(for fileURL: URL, reserve: Int64 = 0) throws -> VoiceWhisperModelProfile {
      VoiceWhisperModelProfile(
        id: "test_model",
        displayName: "Test model",
        fileName: "ggml-test.bin",
        sizeLabel: "test",
        expectedSizeBytes: Int64(try Data(contentsOf: fileURL).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: fileURL),
        minFreeStorageBytes: reserve
      )
    }
  }
}
