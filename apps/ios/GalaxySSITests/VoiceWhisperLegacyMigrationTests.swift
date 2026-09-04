import XCTest
@testable import GalaxySSI

final class VoiceWhisperLegacyMigrationTests: XCTestCase {
  func testMigratesVerifiedLegacyFile() throws {
    let env = try Environment()
    let legacy = try env.writeFile(named: "legacy.bin", contents: "legacy-model")
    let profile = try env.profile(for: legacy)

    let result = VoiceWhisperLegacyMigration.migrate(
      profile: profile,
      candidates: [legacy],
      storage: env.storage,
      deleteMigratedSource: true
    )

    XCTAssertEqual(result.state, .migrated)
    XCTAssertEqual(result.sourceURL?.standardizedFileURL, legacy.standardizedFileURL)
    XCTAssertNil(result.failure)
    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
  }

  func testSkipsCorruptCandidateAndMigratesVerifiedFile() throws {
    let env = try Environment()
    let valid = try env.writeFile(named: "legacy-valid.bin", contents: "legacy-model")
    let corrupt = try env.writeFile(named: "legacy-corrupt.bin", contents: String(repeating: "x", count: 12))
    let profile = try env.profile(for: valid)

    let result = VoiceWhisperLegacyMigration.migrate(
      profile: profile,
      candidates: [corrupt, valid],
      storage: env.storage
    )

    XCTAssertEqual(result.state, .migrated)
    XCTAssertEqual(result.sourceURL?.standardizedFileURL, valid.standardizedFileURL)
    XCTAssertTrue(env.storage.verifyForNativeLoad(profile).valid)
  }

  func testAlreadyInstalledAndNotFoundStates() throws {
    let env = try Environment()
    let valid = try env.writeFile(named: "installed.bin", contents: "installed-model")
    let profile = try env.profile(for: valid)
    _ = try env.storage.install(sourceFileURL: valid, profile: profile, sourceLabel: "test")

    XCTAssertEqual(
      VoiceWhisperLegacyMigration.migrate(profile: profile, candidates: [valid], storage: env.storage).state,
      .alreadyInstalled
    )

    let missing = env.root.appendingPathComponent("missing.bin", isDirectory: false)
    XCTAssertEqual(
      VoiceWhisperLegacyMigration.migrate(profile: profile, candidates: [missing], storage: env.storage).state,
      .alreadyInstalled
    )

    let otherProfile = try env.profile(for: valid, id: "not_found")
    XCTAssertEqual(
      VoiceWhisperLegacyMigration.migrate(profile: otherProfile, candidates: [missing], storage: env.storage).state,
      .notFound
    )
  }

  private final class Environment {
    let root: URL
    let storage: VoiceWhisperModelStorage

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      storage = VoiceWhisperModelStorage(rootDirectory: root, catalogVersion: "test")
    }

    func writeFile(named name: String, contents: String) throws -> URL {
      let url = root.appendingPathComponent(name, isDirectory: false)
      try Data(contents.utf8).write(to: url)
      return url
    }

    func profile(for fileURL: URL, id: String = "test_model") throws -> VoiceWhisperModelProfile {
      VoiceWhisperModelProfile(
        id: id,
        displayName: "Test model",
        fileName: "ggml-test.bin",
        sizeLabel: "test",
        expectedSizeBytes: Int64(try Data(contentsOf: fileURL).count),
        sha256: try VoiceWhisperModelVerifier.sha256(fileURL: fileURL)
      )
    }
  }
}
