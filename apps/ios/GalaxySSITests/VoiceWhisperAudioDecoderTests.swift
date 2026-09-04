import XCTest
@testable import GalaxySSI

final class VoiceWhisperAudioDecoderTests: XCTestCase {
  func testDecoderReadsPcmWaveAndNormalizesToFloat16kMono() throws {
    let snapshot = PcmSnapshot(
      samples: [0, 16_384, -16_384, 32_767],
      sampleRateHz: 16_000,
      speechDetected: true,
      speechStartSample: 0,
      speechEndSampleExclusive: 4,
      captureStartSample: 0,
      captureEndSampleExclusive: 4
    )
    let audio = try VoiceWhisperAudioDecoder().decodePcmWave(PcmWaveFileAdapter.encode(snapshot))

    XCTAssertEqual(audio.sampleRateHz, 16_000)
    XCTAssertEqual(audio.sourceSampleRateHz, 16_000)
    XCTAssertEqual(audio.channelCount, 1)
    XCTAssertEqual(audio.samples.count, 4)
    XCTAssertEqual(audio.durationMs, 0)
    XCTAssertEqual(audio.samples[0], 0, accuracy: 0.0001)
    XCTAssertEqual(audio.samples[1], 0.5, accuracy: 0.0001)
    XCTAssertEqual(audio.samples[2], -0.5, accuracy: 0.0001)
  }

  func testDecoderMixesStereoAndResamplesToTargetRate() throws {
    let wave = stereoWave(sampleRateHz: 8_000, frames: [
      (Int16(16_384), Int16(0)),
      (Int16(-16_384), Int16(0)),
      (Int16(0), Int16(16_384)),
      (Int16(0), Int16(-16_384)),
    ])
    let audio = try VoiceWhisperAudioDecoder(targetSampleRateHz: 16_000).decodePcmWave(wave)

    XCTAssertEqual(audio.sampleRateHz, 16_000)
    XCTAssertEqual(audio.sourceSampleRateHz, 8_000)
    XCTAssertEqual(audio.channelCount, 2)
    XCTAssertEqual(audio.samples.count, 8)
    XCTAssertEqual(audio.samples.first ?? 0, 0.25, accuracy: 0.0001)
  }

  func testDecoderRejectsNonWaveData() {
    XCTAssertThrowsError(try VoiceWhisperAudioDecoder().decodePcmWave(Data("nope".utf8))) { error in
      XCTAssertEqual(error as? VoiceWhisperAudioDecodeError, .invalidWaveHeader)
    }
  }

  private func stereoWave(sampleRateHz: Int, frames: [(Int16, Int16)]) -> Data {
    var data = Data()
    let dataBytes = UInt32(frames.count * 4)
    data.appendAscii("RIFF")
    data.appendLe32(36 + dataBytes)
    data.appendAscii("WAVE")
    data.appendAscii("fmt ")
    data.appendLe32(16)
    data.appendLe16(1)
    data.appendLe16(2)
    data.appendLe32(UInt32(sampleRateHz))
    data.appendLe32(UInt32(sampleRateHz * 4))
    data.appendLe16(4)
    data.appendLe16(16)
    data.appendAscii("data")
    data.appendLe32(dataBytes)
    for frame in frames {
      data.appendLe16(UInt16(bitPattern: frame.0))
      data.appendLe16(UInt16(bitPattern: frame.1))
    }
    return data
  }
}

private extension Data {
  mutating func appendAscii(_ text: String) {
    append(contentsOf: text.utf8)
  }

  mutating func appendLe16(_ value: UInt16) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
  }

  mutating func appendLe32(_ value: UInt32) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
    append(UInt8((value >> 16) & 0xff))
    append(UInt8((value >> 24) & 0xff))
  }
}
