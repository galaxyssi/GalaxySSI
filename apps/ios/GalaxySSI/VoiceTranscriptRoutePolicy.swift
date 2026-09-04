import Foundation

struct VoiceTranscriptRoutePlan: Equatable {
  var sessionId: String
  var text: String
  var contact: GalaxySSIContact
  var routeDecision: VoiceRouteDecision
  var shouldSend: Bool
}

enum VoiceTranscriptRoutePolicy {
  static func plan(
    command: VoiceInteractionCommand,
    settings: VoiceSettings,
    contacts: [GalaxySSIContact]
  ) -> VoiceTranscriptRoutePlan? {
    guard case let .routeFinalTranscript(
      sessionId: sessionId,
      transcript: transcript,
      idempotencyKey: _
    ) = command else {
      return nil
    }
    let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.isEmpty else {
      return nil
    }
    let normalized = settings.normalized
    let contact = resolveContact(settings: normalized, contacts: contacts)
    let decision = VoiceRouteDecision(
      kind: routeKind(for: contact.deliveryMode),
      targetId: contact.id,
      reasonCode: normalized.autoSendTranscripts ? "voice_auto_send" : "voice_transcript_ready"
    )
    return VoiceTranscriptRoutePlan(
      sessionId: sessionId,
      text: text,
      contact: contact,
      routeDecision: decision,
      shouldSend: normalized.autoSendTranscripts
    )
  }

  private static func resolveContact(
    settings: VoiceSettings,
    contacts: [GalaxySSIContact]
  ) -> GalaxySSIContact {
    let preferredId = settings.routingMode == .nativeAgent ? "hermes" : settings.targetContactId
    return contacts.first { $0.id == preferredId } ??
      contacts.first { $0.id == settings.targetContactId } ??
      contacts.first { $0.id == "hermes" } ??
      GalaxySSIContact.hermes()
  }

  private static func routeKind(for deliveryMode: GalaxySSIDeliveryMode) -> VoiceRouteKind {
    switch deliveryMode {
    case .local:
      return .localAction
    case .cloudAPI:
      return .cloudModel
    case .link, .pcConnector:
      return .remoteAgent
    }
  }
}
