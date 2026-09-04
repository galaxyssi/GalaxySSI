import SwiftUI

struct AgentReplyWaitingIndicatorState: Equatable {
  var messageIDs: Set<UUID>
  var unboundTurnIDs: [String]
}

enum AgentReplyWaitingIndicatorPolicy {
  static let dedupePrefix = "ui-reply-waiting:"

  static func tracksAgentReply(for contact: GalaxySSIContact) -> Bool {
    let id = contact.id.lowercased()
    let type = contact.type.lowercased()
    let kind = contact.agentKind.lowercased()
    return id == "hermes" ||
      type == "agent" ||
      type == "hermes" ||
      type == "device" ||
      kind.contains("agent") ||
      kind.contains("model") ||
      contact.deliveryMode == .cloudAPI
  }

  static func turnKey(for message: ChatMessage) -> String {
    message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(message.id.uuidString)
  }

  static func viewID(for message: ChatMessage) -> String {
    viewID(forTurnID: turnKey(for: message))
  }

  static func viewID(forTurnID turnID: String) -> String {
    "\(dedupePrefix)\(turnID)"
  }

  static func stopsFor(_ phase: AgentPhase) -> Bool {
    switch phase {
    case .waitingConfirmation, .paused, .blocked, .completed, .failed, .cancelled:
      return true
    case .observing, .planning, .executing, .verifying, .waitingResponse:
      return false
    }
  }

  static func state(
    messages: [ChatMessage],
    pendingTurnIds: Set<String>,
    stoppedTurnIds: Set<String> = []
  ) -> AgentReplyWaitingIndicatorState {
    let visiblePendingTurnIds = pendingTurnIds.subtracting(stoppedTurnIds)
    guard !visiblePendingTurnIds.isEmpty else {
      return AgentReplyWaitingIndicatorState(messageIDs: [], unboundTurnIDs: [])
    }
    let assistantTurnIds = Set(
      messages
        .filter { !$0.isMine && !$0.isSystem }
        .map { turnKey(for: $0) }
    )
    let userTurnIds = Set(
      messages
        .filter { $0.isMine && !$0.isSystem }
        .map { turnKey(for: $0) }
    )
    let messageIDs = Set(
      messages
        .filter { message in
          message.isMine &&
            !message.isSystem &&
            visiblePendingTurnIds.contains(turnKey(for: message)) &&
            !assistantTurnIds.contains(turnKey(for: message))
        }
        .map(\.id)
    )
    let unboundTurnIDs = visiblePendingTurnIds
      .filter { !assistantTurnIds.contains($0) && !userTurnIds.contains($0) }
      .sorted()
    return AgentReplyWaitingIndicatorState(
      messageIDs: messageIDs,
      unboundTurnIDs: unboundTurnIDs
    )
  }

  static func waitingMessageIDs(
    messages: [ChatMessage],
    pendingTurnIds: Set<String>,
    stoppedTurnIds: Set<String> = []
  ) -> Set<UUID> {
    state(
      messages: messages,
      pendingTurnIds: pendingTurnIds,
      stoppedTurnIds: stoppedTurnIds
    ).messageIDs
  }

  static func unboundTurnIDs(
    messages: [ChatMessage],
    pendingTurnIds: Set<String>,
    stoppedTurnIds: Set<String> = []
  ) -> [String] {
    state(
      messages: messages,
      pendingTurnIds: pendingTurnIds,
      stoppedTurnIds: stoppedTurnIds
    ).unboundTurnIDs
  }
}

struct AgentReplyWaitingIndicatorView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var isAnimating = false
  var bubbleBackground = true

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.galaxySSITextSecondary)
          .frame(width: 7, height: 7)
          .scaleEffect(isAnimating ? 1 : 0.82)
          .opacity(isAnimating ? 1 : 0.32)
          .animation(
            .easeInOut(duration: 0.45)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.14),
            value: isAnimating
          )
      }
    }
    .padding(.horizontal, bubbleBackground ? 15 : 2)
    .padding(.vertical, bubbleBackground ? 10 : 7)
    .frame(
      minWidth: bubbleBackground ? 96 : 48,
      minHeight: bubbleBackground ? 44 : 32
    )
    .background(bubbleBackground ? Color.galaxySSIIncomingBubble : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(
      GalaxySSILocalization.string(
        "agent_status_waiting_response",
        fallback: "Waiting for Agent response",
        language: interfaceLanguage
      )
    ))
    .onAppear { isAnimating = true }
    .onDisappear { isAnimating = false }
  }
}
