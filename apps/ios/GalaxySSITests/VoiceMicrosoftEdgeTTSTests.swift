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
    let query = URLComponents(url: request.endpointURL, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.first { $0.name == "Sec-MS-GEC" }?.value,
                   VoiceMicrosoftEdgeTTSWire.secMSGEC(epochSeconds: 1_700_000_000))
    XCTAssertEqual(query?.first { $0.name == "Sec-MS-GEC-Version" }?.value, "2-143.0.3650.75")

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

  func testV2MatchesReferenceVectorsAcrossWindowAndFutureEpochs() {
    let first = "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6"
    let vectors: [(Int64, String)] = [
      (0, first),
      (299, first),
      (300, "F7535A20A262E331-28675BF85C7106BBF20035A78FCB0B6890813EAD5C3B983EF3424931B720BABB"),
      (1_792_908_000, "660D8AEBD2921C83-67437D45B7AF09FC11030ACE27D06F3ABCF5E3EFB594EA48EF592E80D2904420"),
      (2_147_483_647, "96AE288915A09C99-EB52B45DB68387A1383783E40D42BBBD69D4DCCDF2540629BD4E7FB2E3287822"),
      (4_102_444_800, "DD230DB44FEE2FD7-DA0D4FA797866E36C992FABB81DD2F9DB37EB74D675D63228277003DCD3F9F8C"),
    ]
    for (epoch, expected) in vectors {
      XCTAssertEqual(VoiceMicrosoftEdgeTTSWire.secMSGEC(epochSeconds: epoch), expected, "epoch=\(epoch)")
    }
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
