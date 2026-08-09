import Foundation

struct SignalASIAgentComposerUiState: Equatable {
  let showPrimaryActionSlot: Bool
  let showMoreButton: Bool
  let showSendButton: Bool
  let showActionTray: Bool
}

enum SignalASIAgentComposerUiPolicy {
  static func resolve(
    hasInput: Bool,
    hasPendingPrimaryAction: Bool,
    textModeActive: Bool,
    actionTrayRequested: Bool
  ) -> SignalASIAgentComposerUiState {
    let showSend = hasInput || hasPendingPrimaryAction
    let showTray = actionTrayRequested && !showSend
    let showMore = !showSend && (textModeActive || showTray)
    return SignalASIAgentComposerUiState(
      showPrimaryActionSlot: showSend || showMore,
      showMoreButton: showMore,
      showSendButton: showSend,
      showActionTray: showTray
    )
  }
}
