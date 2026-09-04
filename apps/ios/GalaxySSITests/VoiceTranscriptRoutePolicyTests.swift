import XCTest
@testable import GalaxySSI

final class VoiceTranscriptRoutePolicyTests: XCTestCase {
  func testNativeAgentRoutingTargetsHermesRemoteAgent() {
    let plan = VoiceTranscriptRoutePolicy.plan(
      command: routeCommand(text: " Help me plan "),
      settings: settings(routingMode: .nativeAgent, targetContactId: "cloud"),
      contacts: [
        contact("cloud", deliveryMode: .cloudAPI),
        contact("hermes", deliveryMode: .link),
      ]
    )

    XCTAssertEqual(plan?.text, "Help me plan")
    XCTAssertEqual(plan?.contact.id, "hermes")
    XCTAssertEqual(plan?.routeDecision.kind, .remoteAgent)
    XCTAssertEqual(plan?.routeDecision.targetId, "hermes")
    XCTAssertEqual(plan?.routeDecision.reasonCode, "voice_auto_send")
    XCTAssertEqual(plan?.shouldSend, true)
  }

  func testContactRoutingUsesSelectedCloudModelContact() {
    let plan = VoiceTranscriptRoutePolicy.plan(
      command: routeCommand(text: "Summarize this"),
      settings: settings(routingMode: .contact, targetContactId: "cloud"),
      contacts: [
        contact("hermes", deliveryMode: .link),
        contact("cloud", deliveryMode: .cloudAPI),
      ]
    )

    XCTAssertEqual(plan?.contact.id, "cloud")
    XCTAssertEqual(plan?.routeDecision.kind, .cloudModel)
  }

  func testLocalContactMapsToLocalActionRouteKind() {
    let plan = VoiceTranscriptRoutePolicy.plan(
      command: routeCommand(text: "show settings"),
      settings: settings(routingMode: .contact, targetContactId: "system"),
      contacts: [
        contact("system", deliveryMode: .local),
      ]
    )

    XCTAssertEqual(plan?.contact.id, "system")
    XCTAssertEqual(plan?.routeDecision.kind, .localAction)
  }

  func testAutoSendDisabledKeepsTranscriptReadyWithoutSend() {
    let plan = VoiceTranscriptRoutePolicy.plan(
      command: routeCommand(text: "draft only"),
      settings: settings(autoSendTranscripts: false, routingMode: .contact, targetContactId: "cloud"),
      contacts: [contact("cloud", deliveryMode: .cloudAPI)]
    )

    XCTAssertEqual(plan?.shouldSend, false)
    XCTAssertEqual(plan?.routeDecision.reasonCode, "voice_transcript_ready")
  }

  func testNonRoutingCommandAndEmptyTranscriptAreIgnored() {
    let emptyPlan = VoiceTranscriptRoutePolicy.plan(
      command: routeCommand(text: "   "),
      settings: settings(),
      contacts: [contact("hermes", deliveryMode: .link)]
    )
    let cancelPlan = VoiceTranscriptRoutePolicy.plan(
      command: .cancelLegacyWork(
        sessionId: "voice-1",
        reasonCode: "empty_transcript",
        idempotencyKey: "voice-1:cancel"
      ),
      settings: settings(),
      contacts: [contact("hermes", deliveryMode: .link)]
    )

    XCTAssertNil(emptyPlan)
    XCTAssertNil(cancelPlan)
  }

  private func routeCommand(text: String) -> VoiceInteractionCommand {
    .routeFinalTranscript(
      sessionId: "voice-1",
      transcript: TranscriptHypothesis(text: text, revision: 1, provider: iosSpeechProviderId),
      idempotencyKey: "voice-1:route:1"
    )
  }

  private func settings(
    autoSendTranscripts: Bool = true,
    routingMode: VoiceRoutingMode = .nativeAgent,
    targetContactId: String = "hermes"
  ) -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: autoSendTranscripts,
      preferredLocaleIdentifier: "en-US",
      targetContactId: targetContactId,
      routingMode: routingMode
    )
  }

  private func contact(
    _ id: String,
    deliveryMode: GalaxySSIDeliveryMode
  ) -> GalaxySSIContact {
    var contact = id == "hermes" ? GalaxySSIContact.hermes() : GalaxySSIContact.system()
    contact.id = id
    contact.galaxySSIId = id
    contact.name = id
    contact.displayName = id
    contact.deliveryMode = deliveryMode
    contact.trustState = .verified
    contact.deleted = false
    return contact
  }
}
