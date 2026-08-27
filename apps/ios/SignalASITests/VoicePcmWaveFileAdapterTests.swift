import AVFoundation
import XCTest
@testable import SignalASI

final class VoicePcmWaveFileAdapterTests: XCTestCase {
  func testWritesStandardMonoPcmWaveWithoutLeavingPartialFile() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("VoicePcmWaveFileAdapterTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let samples = [-32_768, -1, 0, 1, 32_767].map { Int16($0) }
    let file = try PcmWaveFileAdapter.write(
      snapshot: PcmSnapshot(
        samples: samples,
        sampleRateHz: 16_000,
        speechDetected: true,
        speechStartSample: 0,
        speechEndSampleExclusive: 5,
        captureStartSample: 0,
        captureEndSampleExclusive: 5
      ),
      directory: root,
      stem: "voice:test"
    )
    let bytes = try Data(contentsOf: file)

    XCTAssertEqual(String(data: bytes.subdata(in: 0..<4), encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: bytes.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    XCTAssertEqual(leInt(bytes, offset: 24), 16_000)
    XCTAssertEqual(leInt(bytes, offset: 40), samples.count * 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("voice_test.wav.partial").path))
  }

  func testPeerVoiceMessagesUseDedicatedStereoAACCapture() {
    let settings = SignalASIPeerVoiceMessageAudio.recorderSettings

    XCTAssertTrue(SignalASIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "chat_message",
      isPersonContact: true
    ))
    XCTAssertFalse(SignalASIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "agent_input",
      isPersonContact: true
    ))
    XCTAssertFalse(SignalASIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "chat_message",
      isPersonContact: false
    ))
    XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
    XCTAssertEqual(settings[AVSampleRateKey] as? Int, 48_000)
    XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    XCTAssertEqual(settings[AVEncoderBitRateKey] as? Int, 128_000)
  }

  func testPeerVoicePlaybackUsesGentleSpeechShaping() {
    XCTAssertEqual(SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: 90), -1.0)
    XCTAssertEqual(SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: 400), 1.2)
    XCTAssertEqual(SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: 2_000), 0.4)
    XCTAssertEqual(SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: 6_000), -0.6)
    XCTAssertEqual(SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: 10_000), -1.2)
  }

  private func leInt(_ data: Data, offset: Int) -> Int {
    let bytes = [UInt8](data)
    return Int(bytes[offset]) |
      Int(bytes[offset + 1]) << 8 |
      Int(bytes[offset + 2]) << 16 |
      Int(bytes[offset + 3]) << 24
  }
}
