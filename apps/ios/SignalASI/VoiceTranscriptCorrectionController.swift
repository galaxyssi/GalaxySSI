import Foundation

struct DefaultTranscriptCorrectionController: TranscriptCorrectionController {
  private let entityChecker: EntityConsistencyChecking

  init(entityChecker: EntityConsistencyChecking = DefaultEntityConsistencyChecker()) {
    self.entityChecker = entityChecker
  }

  func compare(
    fast: TranscriptHypothesis,
    accurate: TranscriptHypothesis,
    executionRecord: VoiceExecutionRecord
  ) -> CorrectionDecision {
    if accurate.revision <= executionRecord.highestCorrectionRevision {
      return .noMaterialChange
    }
    let consistency = entityChecker.compare(fastText: fast.text, accurateText: accurate.text)
    let diff = TranscriptDiff(
      fastText: fast.text.trimmingCharacters(in: .whitespacesAndNewlines),
      accurateText: accurate.text.trimmingCharacters(in: .whitespacesAndNewlines),
      normalizedFastText: fast.text.voiceNormalizedTranscript(),
      normalizedAccurateText: accurate.text.voiceNormalizedTranscript(),
      entityDifferences: consistency.differences
    )
    if !diff.changed {
      return .noMaterialChange
    }
    if executionRecord.userEdited {
      return .updateFutureContext(diff)
    }
    if diff.hasCriticalEntityChange {
      if executionRecord.executionStarted {
        return .warnUser(diff, reason: "A protected entity changed after execution started")
      }
      if executionRecord.risk >= .high {
        return .requireConfirmationBeforeExecution(
          corrected: accurate,
          reason: "Protected entities differ between fast and accurate transcription"
        )
      }
      return .warnUser(diff, reason: "A command entity changed during the accuracy pass")
    }
    return executionRecord.executionStarted ? .updateFutureContext(diff) : .displayOnly(diff)
  }
}
