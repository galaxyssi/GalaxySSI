import Foundation
import XCTest
@testable import GalaxySSI

final class VoiceMicrosoftEdgeTTSWireTests: XCTestCase {
  func testBuildsEdgeEndpointAndProtocolMessages() throws {
    let request = try VoiceMicrosoftEdgeTTSWire.request(
      text: " hello & <world> \" ",
      voiceName: "zh-CN-XiaoxiaoNeural",
      requestId: "abc123",
      connectionId: "connection123",
      muid: "ABC123",
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertEqual(request.text, "hello & <world> \"")
    XCTAssertEqual(request.endpointURL.scheme, "wss")
    XCTAssertEqual(request.endpointURL.host, "speech.platform.bing.com")
    XCTAssertTrue(request.endpointURL.absoluteString.contains("TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4"))
    XCTAssertTrue(request.endpointURL.absoluteString.contains("ConnectionId=connection123"))
    XCTAssertTrue(request.endpointURL.absoluteString.contains("Sec-MS-GEC=42301B335578FEFDAE2637DED1ABD614505D432559EC08032B82048483726AFF"))
    XCTAssertTrue(request.endpointURL.absoluteString.contains("Sec-MS-GEC-Version=1-143.0.3650.75"))

    let headers = VoiceMicrosoftEdgeTTSWire.requestHeaders(muid: request.muid)
    XCTAssertTrue(headers["User-Agent"]?.contains("Edg/143.0.0.0") == true)
    XCTAssertEqual(headers["Cookie"], "muid=ABC123;")

    let speechConfig = VoiceMicrosoftEdgeTTSWire.speechConfigMessage(
      request: request,
      timestamp: "Fri Jul 31 2026 00:00:00 GMT+0000"
    )
    XCTAssertTrue(speechConfig.contains("Path:speech.config"))
    XCTAssertTrue(speechConfig.contains("audio-24khz-48kbitrate-mono-mp3"))

    let ssml = VoiceMicrosoftEdgeTTSWire.ssmlMessage(
      request: request,
      timestamp: "Fri Jul 31 2026 00:00:00 GMT+0000",
      language: "zh-CN"
    )
    XCTAssertTrue(ssml.contains("Path:ssml"))
    XCTAssertTrue(ssml.contains("<voice name='zh-CN-XiaoxiaoNeural'>"))
    XCTAssertTrue(ssml.contains("<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"))
    XCTAssertTrue(ssml.contains("hello &amp; &lt;world&gt; &quot;</prosody>"))
  }

  func testSanitizesForbiddenControlCharacters() throws {
    let request = try VoiceMicrosoftEdgeTTSWire.request(
      text: "hello\u{0001}world",
      voiceName: "en-US-JennyNeural",
      requestId: "request",
      connectionId: "connection",
      muid: "MUID",
      date: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertEqual(request.text, "hello world")
    XCTAssertFalse(VoiceMicrosoftEdgeTTSWire.ssmlMessage(request: request).contains("\u{0001}"))
  }

  func testExtractsAudioPayloadAfterHeaders() {
    let raw = Data("Path:audio\r\nX-Test:1\r\n\r\nMP3DATA".utf8)
    XCTAssertEqual(VoiceMicrosoftEdgeTTSWire.audioPayload(from: raw), Data("MP3DATA".utf8))
    XCTAssertEqual(VoiceMicrosoftEdgeTTSWire.audioPayload(from: Data("MP3DATA".utf8)), Data("MP3DATA".utf8))
  }

  func testThrowsForBlankText() {
    XCTAssertThrowsError(try VoiceMicrosoftEdgeTTSWire.request(text: "   ", voiceName: "en-US-JennyNeural")) { error in
      XCTAssertEqual(error as? VoiceMicrosoftEdgeTTSError, .blankText)
    }
  }
}

final class VoiceMicrosoftEdgeTTSTests: XCTestCase {
  func testMicrosoftVoiceMatchesAndroidFallbacks() {
    XCTAssertEqual(
      LanguagePolicySettings.microsoftVoice(languageTag: "zh-HK", configuredVoice: ""),
      "zh-HK-HiuMaanNeural"
    )
    XCTAssertEqual(
      LanguagePolicySettings.microsoftVoice(languageTag: "zh-TW", configuredVoice: ""),
      "zh-TW-HsiaoChenNeural"
    )
    XCTAssertEqual(
      LanguagePolicySettings.microsoftVoice(languageTag: "zh-CN", configuredVoice: "zh-CN-YunxiNeural"),
      "zh-CN-YunxiNeural"
    )
    XCTAssertEqual(
      LanguagePolicySettings.microsoftVoice(languageTag: "en-US", configuredVoice: "zh-CN-XiaoxiaoNeural"),
      "en-US-JennyNeural"
    )
  }

  func testSynthesizesPlaybackRequestThroughInjectedRuntime() async throws {
    let fake = FakeMicrosoftEdgeTTSSynthesizer(audio: Data([0x01, 0x02, 0x03]))
    let edge = VoiceMicrosoftEdgeTTS(synthesizer: fake)
    let request = VoiceReplyPlaybackRequest(
      sessionId: "voice-1",
      utteranceId: "galaxyssi_voice_1234",
      text: "hello",
      language: "en-US",
      providerId: VoiceTTSProvider.microsoftEdge.rawValue,
      runtimeChannel: .microsoftEdgeTTS,
      voiceName: "en-US-JennyNeural"
    )

    let result = try await edge.synthesize(request)

    XCTAssertEqual(result.audioData, Data([0x01, 0x02, 0x03]))
    XCTAssertEqual(fake.requests.first?.voiceName, "en-US-JennyNeural")
    XCTAssertEqual(fake.events.first?.event, VoiceTraceEvents.ttsConnected)
  }
}

private final class FakeMicrosoftEdgeTTSSynthesizer: VoiceMicrosoftEdgeTTSSynthesizing {
  private let audio: Data
  private(set) var requests: [VoiceMicrosoftEdgeTTSRequest] = []
  private(set) var events: [(event: String, attributes: [String: String], once: Bool)] = []

  init(audio: Data) {
    self.audio = audio
  }

  func synthesize(
    _ request: VoiceMicrosoftEdgeTTSRequest,
    trace: @escaping VoiceMicrosoftEdgeTTSTraceRecorder
  ) async throws -> Data {
    requests.append(request)
    let event: (event: String, attributes: [String: String], once: Bool) = (
      VoiceTraceEvents.ttsConnected,
      ["tts_provider": VoiceTTSProvider.microsoftEdge.rawValue],
      true
    )
    events.append(event)
    trace(event.event, event.attributes, event.once)
    return audio
  }
}
