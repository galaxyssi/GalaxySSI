import Foundation

enum VoiceInteractionEvent: Equatable {
  case capturePrepared(sessionId: String)
  case audioLevel(sessionId: String, rms: Float)
  case speechStarted(sessionId: String, atElapsedNs: Int64)
  case speechEnded(sessionId: String, atElapsedNs: Int64)
  case finalizationStarted(sessionId: String)
  case transcriptPartial(sessionId: String, value: TranscriptHypothesis)
  case transcriptStable(sessionId: String, value: TranscriptHypothesis)
  case transcriptFinal(sessionId: String, value: TranscriptHypothesis)
  case transcriptCorrected(sessionId: String, original: TranscriptHypothesis, corrected: TranscriptHypothesis)
  case routeSelected(sessionId: String, decision: VoiceRouteDecision)
  case localActionCompleted(sessionId: String)
  case modelDelta(sessionId: String, text: String)
  case agentAccepted(sessionId: String, runId: String)
  case agentProgress(sessionId: String, runId: String)
  case playbackStarted(sessionId: String, utteranceId: String)
  case completed(sessionId: String)
  case cancelled(sessionId: String, reasonCode: String)
  case failed(sessionId: String, failure: VoiceFailure)

  var sessionId: String {
    switch self {
    case let .capturePrepared(sessionId: sessionId),
         let .audioLevel(sessionId: sessionId, rms: _),
         let .speechStarted(sessionId: sessionId, atElapsedNs: _),
         let .speechEnded(sessionId: sessionId, atElapsedNs: _),
         let .finalizationStarted(sessionId: sessionId),
         let .transcriptPartial(sessionId: sessionId, value: _),
         let .transcriptStable(sessionId: sessionId, value: _),
         let .transcriptFinal(sessionId: sessionId, value: _),
         let .transcriptCorrected(sessionId: sessionId, original: _, corrected: _),
         let .routeSelected(sessionId: sessionId, decision: _),
         let .localActionCompleted(sessionId: sessionId),
         let .modelDelta(sessionId: sessionId, text: _),
         let .agentAccepted(sessionId: sessionId, runId: _),
         let .agentProgress(sessionId: sessionId, runId: _),
         let .playbackStarted(sessionId: sessionId, utteranceId: _),
         let .completed(sessionId: sessionId),
         let .cancelled(sessionId: sessionId, reasonCode: _),
         let .failed(sessionId: sessionId, failure: _):
      return sessionId
    }
  }

  var isTranscriptCorrection: Bool {
    if case .transcriptCorrected(sessionId: _, original: _, corrected: _) = self {
      return true
    }
    return false
  }
}
