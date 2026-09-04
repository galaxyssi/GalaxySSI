import UIKit

extension AgentHomeView {
  func installComposerInputBridge() {
    AgentIOSComposerInputBridge.shared.install { action in
      applyComposerInputAction(action)
    }
  }

  func applyComposerInputAction(_ action: AgentAction) -> AgentActionResult {
    let metadata = [
      "platform": "ios",
      "surface": "galaxyssi_agent_composer",
      "field": "agent_goal",
      "completion_verified": "true"
    ]
    switch action.kind {
    case .typeText:
      let text = action.parameters["text"] ?? ""
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return AgentActionResult(
          actionId: action.id,
          success: false,
          message: t("galaxyssi.agent.input.text_missing", "No text was provided."),
          metadata: metadata.merging(["completion_verified": "false"]) { _, next in next }
        )
      }
      draft = text
      actionTrayPresented = false
      composerFocusRequest += 1
      refreshAgentScreenContext()
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: t("galaxyssi.agent.input.text_entered", "Text entered in the Agent composer."),
        metadata: metadata
      )

    case .deleteText:
      draft = ""
      actionTrayPresented = false
      composerFocusRequest += 1
      refreshAgentScreenContext()
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: t("galaxyssi.agent.input.text_cleared", "Agent composer text cleared."),
        metadata: metadata
      )

    case .pasteText:
      let text = UIPasteboard.general.string ?? ""
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return AgentActionResult(
          actionId: action.id,
          success: false,
          message: t("galaxyssi.agent.input.clipboard_empty", "Clipboard is empty."),
          metadata: metadata.merging(["completion_verified": "false"]) { _, next in next }
        )
      }
      draft = text
      actionTrayPresented = false
      composerFocusRequest += 1
      refreshAgentScreenContext()
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: t("galaxyssi.agent.input.clipboard_pasted", "Clipboard text pasted in the Agent composer."),
        metadata: metadata
      )

    default:
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t("galaxyssi.agent.input.unsupported", "This action is not supported by the Agent composer."),
        metadata: metadata.merging(["completion_verified": "false"]) { _, next in next }
      )
    }
  }

  func installAgentHomeSwipeBridge() {
    AgentIOSAgentHomeSwipeBridge.shared.install { action in
      applyAgentHomeSwipeAction(action)
    }
  }

  func applyAgentHomeSwipeAction(_ action: AgentAction) -> AgentActionResult {
    guard let direction = AgentIOSAgentSwipeDirection.resolve(parameters: action.parameters) else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "galaxyssi.agent.swipe.invalid_direction",
          "The Agent transcript swipe direction is invalid."
        ),
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_transcript",
          "completion_verified": "false"
        ]
      )
    }
    guard direction == .up || direction == .down else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: t(
          "galaxyssi.agent.swipe.vertical_only",
          "The Agent transcript supports only vertical swipes."
        ),
        metadata: [
          "platform": "ios",
          "surface": "galaxyssi_agent_transcript",
          "direction": direction.rawValue,
          "completion_verified": "false"
        ]
      )
    }

    pendingAgentSwipeDirection = direction.rawValue
    agentSwipeRequest += 1
    return AgentActionResult(
      actionId: action.id,
      success: true,
      message: t(
        "galaxyssi.agent.swipe.completed",
        "Agent transcript moved."
      ),
      metadata: [
        "platform": "ios",
        "surface": "galaxyssi_agent_transcript",
        "direction": direction.rawValue,
        "completion_verified": "true"
      ]
    )
  }
}
