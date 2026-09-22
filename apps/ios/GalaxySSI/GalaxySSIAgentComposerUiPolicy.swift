import Foundation

struct GalaxySSIAgentComposerUiState: Equatable {
  let showPrimaryActionSlot: Bool
  let showMoreButton: Bool
  let showSendButton: Bool
  let showPendingActionButton: Bool
  let showActionTray: Bool
  let showVoiceButton: Bool
}

enum GalaxySSIAgentComposerUiPolicy {
  static func resolve(
    hasInput: Bool,
    hasPendingPrimaryAction: Bool,
    textModeActive: Bool,
    actionTrayRequested: Bool,
    voiceEntryAvailable: Bool = false
  ) -> GalaxySSIAgentComposerUiState {
    let showSend = hasInput
    let showPending = !hasInput && hasPendingPrimaryAction
    let showTray = actionTrayRequested && !showSend && !showPending
    let showMore = !showSend && !showPending && (textModeActive || showTray)
    let showVoice = voiceEntryAvailable && !showSend && !showPending && !showMore
    return GalaxySSIAgentComposerUiState(
      showPrimaryActionSlot: showSend || showPending || showMore || showVoice,
      showMoreButton: showMore,
      showSendButton: showSend,
      showPendingActionButton: showPending,
      showActionTray: showTray,
      showVoiceButton: showVoice
    )
  }
}
