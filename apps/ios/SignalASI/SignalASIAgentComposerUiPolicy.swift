import Foundation

struct SignalASIAgentComposerUiState: Equatable {
  let showPrimaryActionSlot: Bool
  let showMoreButton: Bool
  let showSendButton: Bool
  let showPendingActionButton: Bool
  let showActionTray: Bool
}

enum SignalASIAgentComposerUiPolicy {
  static func resolve(
    hasInput: Bool,
    hasPendingPrimaryAction: Bool,
    textModeActive: Bool,
    actionTrayRequested: Bool
  ) -> SignalASIAgentComposerUiState {
    let showSend = hasInput
    let showPending = !hasInput && hasPendingPrimaryAction
    let showTray = actionTrayRequested && !showSend && !showPending
    let showMore = !showSend && !showPending && (textModeActive || showTray)
    return SignalASIAgentComposerUiState(
      showPrimaryActionSlot: showSend || showPending || showMore,
      showMoreButton: showMore,
      showSendButton: showSend,
      showPendingActionButton: showPending,
      showActionTray: showTray
    )
  }
}
