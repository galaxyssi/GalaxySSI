import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkStoreTests: XCTestCase {
  func testSaveFindLatestAndReplaceByStableKey() throws {
    let env = try Environment()
    let first = record(profileId: "tiny", modelSha: String(repeating: "a", count: 64), createdAt: 100, rtf: 0.4)
    let updated = record(profileId: "tiny", modelSha: String(repeating: "a", count: 64), createdAt: 200, rtf: 0.3)
    let other = record(profileId: "base", modelSha: String(repeating: "b", count: 64), createdAt: 150, rtf: 0.6)

    try env.store.save(first)
    try env.store.save(other)
    try env.store.save(updated)

    XCTAssertEqual(env.store.find(first.certification.key)?.certification.createdAtEpochMillis, 200)
    XCTAssertEqual(env.store.latestForProfile("tiny")?.certification.warmRtfP95, 0.3)
    XCTAssertEqual(env.store.latestForProfile("base")?.certification.warmRtfP95, 0.6)
    XCTAssertFalse(FileManager.default.fileExists(atPath: env.partialURL.path))
  }

  func testBoundsRecordsAndRemovesProfile() throws {
    let env = try Environment()
    for index in 0..<70 {
      try env.store.save(
        record(
          profileId: "profile_\(index)",
          modelSha: String(format: "%064x", index + 1),
          createdAt: Int64(index + 1),
          rtf: Double(index)
        )
      )
    }

    XCTAssertNil(env.store.latestForProfile("profile_0"))
    XCTAssertNotNil(env.store.latestForProfile("profile_69"))

    try env.store.removeForProfile("profile_69")
    XCTAssertNil(env.store.latestForProfile("profile_69"))
  }

  func testWrongSchemaCorruptionAndClearAreSafe() throws {
    let env = try Environment()
    try Data(#"{"schemaVersion":99,"records":[]}"#.utf8).write(to: env.fileURL)
    XCTAssertNil(env.store.latestForProfile("tiny"))

    try Data("not-json".utf8).write(to: env.fileURL)
    XCTAssertNil(env.store.latestForProfile("tiny"))

    try Data("partial".utf8).write(to: env.partialURL)
    env.store.clear()
    XCTAssertFalse(FileManager.default.fileExists(atPath: env.fileURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: env.partialURL.path))
  }

  private func record(
    profileId: String,
    modelSha: String,
    createdAt: Int64,
    rtf: Double
  ) -> VoiceWhisperBenchmarkRecord {
    let key = VoiceWhisperBenchmarkKey(
      manufacturer: "Apple",
      device: "iPhone",
      soc: "A17",
      osVersion: "17.0",
      appVersionCode: 1,
      whisperNativeVersion: "test",
      nativeBuildFingerprint: "test",
      modelProfileId: profileId,
      modelSha256: modelSha,
      benchmarkAudioVersion: "test"
    )
    let certification = VoiceWhisperCertification(
      key: key,
      level: .realtime,
      recommendedMode: .realtimePartial,
      recommendedThreadCount: 4,
      recommendedPartialIntervalMillis: 750,
      warmRtfP50: rtf / 2,
      warmRtfP95: rtf,
      createdAtEpochMillis: createdAt
    )
    return VoiceWhisperBenchmarkRecord(certification: certification)
  }

  private final class Environment {
    let root: URL
    let fileURL: URL
    let partialURL: URL
    let store: VoiceWhisperBenchmarkStore

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      fileURL = root.appendingPathComponent("benchmarks.json", isDirectory: false)
      partialURL = root.appendingPathComponent("benchmarks.json.partial", isDirectory: false)
      store = VoiceWhisperBenchmarkStore(fileURL: fileURL)
    }
  }
}
