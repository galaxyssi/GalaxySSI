import AVFoundation
import XCTest
@testable import GalaxySSI

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

  func testPeerVoiceMessagesUseAndroidCompatibleOpusProfile() {
    XCTAssertTrue(GalaxySSIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "chat_message",
      isPersonContact: true
    ))
    XCTAssertFalse(GalaxySSIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "agent_input",
      isPersonContact: true
    ))
    XCTAssertFalse(GalaxySSIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
      purpose: "chat_message",
      isPersonContact: false
    ))
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.sampleRateHz, 48_000)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.channelCount, 1)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.opusBitRateBPS, 48_000)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.highPassHz, 75)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.targetLUFS, -18)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.peakDBFS, -1)
    XCTAssertEqual(GalaxySSIPeerVoiceMessageAudio.maximumDuration, 60)
  }

  func testPeerVoiceDSPNormalizesSpeechAndLimitsPeak() {
    let rate = GalaxySSIPeerVoiceMessageAudio.sampleRateHz
    var samples = (0..<rate).map { index in
      Float(sin(2 * Double.pi * 1_000 * Double(index) / Double(rate)) * 0.04)
    }

    let result = GalaxySSIPeerVoiceDSP.process(&samples)
    let outputLUFS = GalaxySSIPeerVoiceDSP.integratedLUFS(samples)

    XCTAssertNotNil(result.measuredLUFS)
    XCTAssertEqual(try XCTUnwrap(outputLUFS), -18, accuracy: 1.25)
    XCTAssertLessThanOrEqual(result.outputPeakDBFS, -0.95)
  }

  func testPeerVoiceHighPassAttenuatesSubSpeechRumble() {
    let rate = GalaxySSIPeerVoiceMessageAudio.sampleRateHz
    func tone(_ frequency: Double) -> [Float] {
      (0..<rate).map { index in
        Float(sin(2 * Double.pi * frequency * Double(index) / Double(rate)))
      }
    }
    var rumble = tone(30)
    var speech = tone(1_000)
    GalaxySSIPeerVoiceDSP.applyHighPass(&rumble, cutoffHz: 75)
    GalaxySSIPeerVoiceDSP.applyHighPass(&speech, cutoffHz: 75)

    XCTAssertLessThan(rms(rumble), rms(speech) * 0.45)
  }

  func testOggOpusContainerRoundTripsPacketBoundaries() throws {
    let packets = [Data(repeating: 0x11, count: 37), Data(repeating: 0x22, count: 510)]
    let container = try GalaxySSIOggOpus.write(packets: packets, inputSampleCount: 1_920)

    XCTAssertEqual(String(data: container.prefix(4), encoding: .ascii), "OggS")
    XCTAssertNotNil(container.range(of: Data("OpusHead".utf8)))
    XCTAssertNotNil(container.range(of: Data("OpusTags".utf8)))
    XCTAssertEqual(try GalaxySSIOggOpus.audioPackets(from: container), packets)
  }

  private func rms(_ samples: [Float]) -> Double {
    sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1)))
  }

  private func leInt(_ data: Data, offset: Int) -> Int {
    let bytes = [UInt8](data)
    return Int(bytes[offset]) |
      Int(bytes[offset + 1]) << 8 |
      Int(bytes[offset + 2]) << 16 |
      Int(bytes[offset + 3]) << 24
  }
}
