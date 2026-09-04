import Foundation

struct GalaxySSIAgentHomeHeaderPresentation {
  let sessionTitle: String
  let modelStatusLabel: String
  let modelLogoLabel: String

  static func make(
    session: AgentConversation?,
    contact: GalaxySSIContact,
    selection: AgentModelSelection,
    liveExecutionTargetLabel: String?,
    contacts: [GalaxySSIContact],
    language: String
  ) -> GalaxySSIAgentHomeHeaderPresentation {
    let modelLogoLabel = modelLabel(
      session: session,
      contact: contact,
      selection: selection,
      liveExecutionTargetLabel: liveExecutionTargetLabel,
      contacts: contacts,
      language: language
    )
    let automaticLabel = localized(
      "galaxyssi.agent.model_selection.automatic",
      fallback: "Auto",
      language: language
    )
    let modelStatusLabel: String
    if hasManualSelection(selection) {
      // Match Android: a manual choice is already explicit in the selected model name.
      modelStatusLabel = modelLogoLabel
    } else if modelLogoLabel.caseInsensitiveCompare(automaticLabel) == .orderedSame {
      modelStatusLabel = automaticLabel
    } else {
      modelStatusLabel = String(
        format: localized(
          "galaxyssi.agent.header.routing.auto",
          fallback: "Auto · %@",
          language: language
        ),
        modelLogoLabel
      )
    }
    return GalaxySSIAgentHomeHeaderPresentation(
      sessionTitle: sessionTitle(session, language: language),
      modelStatusLabel: modelStatusLabel,
      modelLogoLabel: modelLogoLabel
    )
  }

  private static func hasManualSelection(_ selection: AgentModelSelection) -> Bool {
    selection.mode == .manual &&
      !selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func modelLabel(
    session: AgentConversation?,
    contact: GalaxySSIContact,
    selection: AgentModelSelection,
    liveExecutionTargetLabel: String?,
    contacts: [GalaxySSIContact],
    language: String
  ) -> String {
    guard hasManualSelection(selection) else {
      if let liveExecutionTargetLabel,
         !liveExecutionTargetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return liveExecutionTargetLabel
      }
      let sessionLabel = session?.selectedModelOrAgent
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let automaticLabel = localized(
        "galaxyssi.agent.model_selection.automatic",
        fallback: "Automatic",
        language: language
      )
      guard !sessionLabel.isEmpty,
            sessionLabel.caseInsensitiveCompare("automatic") != .orderedSame,
            sessionLabel.caseInsensitiveCompare(contact.displayName) != .orderedSame else {
        return automaticLabel
      }
      return sessionLabel
    }

    let automaticLabel = localized(
      "galaxyssi.agent.model_selection.automatic",
      fallback: "Automatic",
      language: language
    )
    let targetId = selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackLabel = selection.displayName
      .ifBlank(selection.modelId)
      .ifBlank(targetId)
      .ifBlank(automaticLabel)

    if targetId == "local-llm" {
      let profile = LocalModelRuntimeCatalog.find(selection.modelId)
      return profile.displayName
        .ifBlank(selection.displayName)
        .ifBlank(selection.modelId)
        .ifBlank(fallbackLabel)
    }
    if let target = contacts.first(where: { $0.id == targetId }),
       target.type == "agent" {
      var labels = [selection.displayName.ifBlank(target.displayName).ifBlank(target.id)]
      if !selection.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        labels.append(selection.modelId)
      }
      if selection.reasoningEffort != .automatic {
        labels.append(reasoningEffortLabel(selection.reasoningEffort, language: language))
      }
      return labels.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    if let target = contacts.first(where: { $0.id == targetId }),
       let model = target.selectedCloudModel {
      return model.displayName
        .ifBlank(model.modelId)
        .ifBlank(selection.displayName)
        .ifBlank(fallbackLabel)
    }
    return fallbackLabel
  }

  private static func sessionTitle(_ session: AgentConversation?, language: String) -> String {
    let fallback = localized(
      "galaxyssi.agent.session.new",
      fallback: "New session",
      language: language
    )
    guard let session else { return fallback }
    let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(fallback)
    let sourceTitle = session.createdByAgent
      ? String(
        format: localized(
          "galaxyssi.agent_session.created_by_agent",
          fallback: "GalaxySSI · %@",
          language: language
        ),
        title
      )
      : title
    if !session.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return sourceTitle + " · " + localized(
        "galaxyssi.agent_session.merged",
        fallback: "Merged",
        language: language
      )
    }
    if session.trackingPaused {
      return sourceTitle + " · " + localized(
        "galaxyssi.agent_session.tracking_paused",
        fallback: "Tracking paused",
        language: language
      )
    }
    return sourceTitle
  }

  private static func localized(_ key: String, fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }

  private static func reasoningEffortLabel(
    _ effort: AgentModelReasoningEffort,
    language: String
  ) -> String {
    switch effort {
    case .automatic:
      return localized("galaxyssi.agent.model_selection.reasoning.auto", fallback: "Auto", language: language)
    case .low:
      return localized("galaxyssi.agent.model_selection.reasoning.low", fallback: "Low", language: language)
    case .medium:
      return localized("galaxyssi.agent.model_selection.reasoning.medium", fallback: "Medium", language: language)
    case .high:
      return localized("galaxyssi.agent.model_selection.reasoning.high", fallback: "High", language: language)
    case .xhigh:
      return localized("galaxyssi.agent.model_selection.reasoning.xhigh", fallback: "Extra high", language: language)
    }
  }
}
