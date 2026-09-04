import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkAudioLoaderTests: XCTestCase {
  func testLoadDecodesMonoPcm16AndAppendsChecksum() throws {
    let wave = waveData(sampleRate: 16_000, channels: 1, frames: 16_000 * 5) { frame, _ in
      Int16(frame % 1_000)
    }
    let url = try write(wave)
    let sha = VoiceWhisperBenchmarkAudioLoader.sha256(wave)

    let audio = try VoiceWhisperBenchmarkAudioLoader.load(
      fileURL: url,
      version: "test",
      expectedSHA256: sha,
      expectedTokens: ["hello"],
      language: "en"
    )

    XCTAssertEqual(audio.version, "test:\(String(sha.prefix(16)))")
    XCTAssertEqual(audio.pcm16.count, 16_000 * 5)
    XCTAssertEqual(audio.pcm16[7], 7)
    XCTAssertEqual(audio.language, "en")
  }

  func testRejectsChecksumMismatch() throws {
    let wave = waveData(sampleRate: 16_000, channels: 1, frames: 16_000 * 5) { _, _ in 1 }
    let url = try write(wave)

    XCTAssertThrowsError(
      try VoiceWhisperBenchmarkAudioLoader.load(
        fileURL: url,
        version: "test",
        expectedSHA256: String(repeating: "0", count: 64),
        expectedTokens: ["hello"]
      )
    ) { error in
      guard case .checksumMismatch = error as? VoiceWhisperBenchmarkAudioLoaderError else {
        return XCTFail("Expected checksum mismatch")
      }
    }
  }

  func testResamplesStereoWaveToBenchmarkRate() throws {
    let wave = waveData(sampleRate: 8_000, channels: 2, frames: 8_000 * 5) { _, channel in
      channel == 0 ? 1_000 : -1_000
    }
    let pcm = try VoiceWhisperBenchmarkAudioLoader.decodePcmWave(wave)

    XCTAssertEqual(pcm.count, 16_000 * 5)
    XCTAssertEqual(pcm[0], 0)
    XCTAssertEqual(pcm[1_000], 0)
  }

  func testRejectsMissingBundledResource() {
    XCTAssertThrowsError(
      try VoiceWhisperBenchmarkAudioLoader.loadBundled(
        bundle: Bundle(for: Self.self),
        resourceName: "missing_benchmark_audio",
        fileExtension: "wav",
        subdirectory: nil,
        expectedTokens: ["hello"]
      )
    ) { error in
      XCTAssertEqual(
        error as? VoiceWhisperBenchmarkAudioLoaderError,
        .resourceMissing("missing_benchmark_audio.wav")
      )
    }
  }

  private func write(_ data: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("benchmark.wav", isDirectory: false)
    try data.write(to: url)
    return url
  }

  private func waveData(
    sampleRate: Int,
    channels: Int,
    frames: Int,
    sample: (Int, Int) -> Int16
  ) -> Data {
    var pcm = Data()
    for frame in 0..<frames {
      for channel in 0..<channels {
        appendInt16(sample(frame, channel), to: &pcm)
      }
    }

    var data = Data()
    appendASCII("RIFF", to: &data)
    appendUInt32(UInt32(36 + pcm.count), to: &data)
    appendASCII("WAVE", to: &data)
    appendASCII("fmt ", to: &data)
    appendUInt32(16, to: &data)
    appendUInt16(1, to: &data)
    appendUInt16(UInt16(channels), to: &data)
    appendUInt32(UInt32(sampleRate), to: &data)
    appendUInt32(UInt32(sampleRate * channels * 2), to: &data)
    appendUInt16(UInt16(channels * 2), to: &data)
    appendUInt16(16, to: &data)
    appendASCII("data", to: &data)
    appendUInt32(UInt32(pcm.count), to: &data)
    data.append(pcm)
    return data
  }

  private func appendASCII(_ value: String, to data: inout Data) {
    data.append(contentsOf: value.data(using: .ascii) ?? Data())
  }

  private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
  }

  private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
  }

  private func appendInt16(_ value: Int16, to data: inout Data) {
    appendUInt16(UInt16(bitPattern: value), to: &data)
  }
}
