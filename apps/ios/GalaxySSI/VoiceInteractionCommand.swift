import Foundation

enum VoiceInteractionCommand: Equatable {
  case routeFinalTranscript(
    sessionId: String,
    transcript: TranscriptHypothesis,
    idempotencyKey: String
  )
  case cancelLegacyWork(
    sessionId: String,
    reasonCode: String,
    idempotencyKey: String
  )

  var sessionId: String {
    switch self {
    case let .routeFinalTranscript(sessionId: sessionId, transcript: _, idempotencyKey: _),
         let .cancelLegacyWork(sessionId: sessionId, reasonCode: _, idempotencyKey: _):
      return sessionId
    }
  }

  var idempotencyKey: String {
    switch self {
    case let .routeFinalTranscript(sessionId: _, transcript: _, idempotencyKey: idempotencyKey),
         let .cancelLegacyWork(sessionId: _, reasonCode: _, idempotencyKey: idempotencyKey):
      return idempotencyKey
    }
  }
}

struct VoiceInteractionTransition: Equatable {
  var previous: VoiceInteractionState
  var current: VoiceInteractionState
  var commands: [VoiceInteractionCommand]
  var accepted: Bool

  init(
    previous: VoiceInteractionState,
    current: VoiceInteractionState,
    commands: [VoiceInteractionCommand] = [],
    accepted: Bool = true
  ) {
    self.previous = previous
    self.current = current
    self.commands = commands
    self.accepted = accepted
  }
}
