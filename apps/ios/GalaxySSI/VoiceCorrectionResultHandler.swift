import Foundation

enum VoiceCorrectionHandlingAction: Equatable {
  case noMaterialChange
  case displayOnly
  case updateFutureContext
  case warnUser(reason: String)
  case requireConfirmationBeforeExecution(reason: String)
}

struct VoiceCorrectionHandlingOutcome: Equatable {
  var dispatchedCorrection: Bool
  var persistedCorrection: Bool
  var action: VoiceCorrectionHandlingAction
  var diffSummary: String
}

enum VoiceCorrectionResultHandler {
  static func handle(
    result: VoiceSecondPassResult,
    risk: VoiceCommandRisk,
    conversationId: String = "",
    turnId: String = "",
    executionLedger: VoiceExecutionLedger,
    correctionJournal: VoiceCorrectionJournal,
    coordinator: VoiceInteractionCoordinator? = nil
  ) -> VoiceCorrectionHandlingOutcome {
    let sessionId = result.metadata.sessionId
    let dispatchAccepted = coordinator?.dispatch(
      .transcriptCorrected(
        sessionId: sessionId,
        original: result.metadata.fast,
        corrected: result.accurate
      )
    ).accepted ?? false
    let persisted = persistCorrection(
      result: result,
      risk: risk,
      conversationId: conversationId,
      turnId: turnId,
      executionLedger: executionLedger,
      correctionJournal: correctionJournal
    )
    return VoiceCorrectionHandlingOutcome(
      dispatchedCorrection: dispatchAccepted,
      persistedCorrection: persisted,
      action: action(for: result.decision),
      diffSummary: result.diff.compactSummary()
    )
  }

  private static func persistCorrection(
    result: VoiceSecondPassResult,
    risk: VoiceCommandRisk,
    conversationId: String,
    turnId: String,
    executionLedger: VoiceExecutionLedger,
    correctionJournal: VoiceCorrectionJournal
  ) -> Bool {
    guard result.diff.changed else { return false }
    let executionRecord = executionLedger.snapshot(sessionId: result.metadata.sessionId)
    return correctionJournal.append(VoiceCorrectionContextRecord(
      sessionId: result.metadata.sessionId,
      conversationId: conversationId,
      turnId: turnId,
      fastText: result.diff.fastText,
      accurateText: result.diff.accurateText,
      diffSummary: result.diff.compactSummary(),
      risk: risk,
      revision: result.accurate.revision,
      modelProfileId: result.metadata.accurateProfileId,
      modelSha256: result.metadata.accurateModelSha256,
      executionMode: result.metadata.mode.rawValue,
      userEdited: executionRecord?.userEdited == true,
      completedAtMillis: result.completedAtMillis
    ))
  }

  private static func action(for decision: CorrectionDecision) -> VoiceCorrectionHandlingAction {
    switch decision {
    case .noMaterialChange:
      return .noMaterialChange
    case .displayOnly:
      return .displayOnly
    case .updateFutureContext:
      return .updateFutureContext
    case let .warnUser(_, reason):
      return .warnUser(reason: reason)
    case let .requireConfirmationBeforeExecution(_, reason):
      return .requireConfirmationBeforeExecution(reason: reason)
    }
  }
}
