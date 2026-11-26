import SwiftUI

struct GalaxySSIAgentModelPickerContent: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let conversationId: String
  let selection: AgentModelSelection
  let localProfiles: [LocalModelRuntimeProfile]
  let agents: [AgentCallableTarget]
  let clouds: [AgentModelPickerCloudChoice]
  let currentDetail: String
  let manualAvailable: Bool
  let remembersNewChats: Bool
  let onAutomatic: () -> Void
  let onLocal: (LocalModelRuntimeProfile) -> Void
  let onCloud: (AgentModelPickerCloudChoice) -> Void
  let onAgent: (AgentCallableTarget, String) -> Void
  let onEffort: (String, AgentModelReasoningEffort) -> Void
  let agentLogo: (AgentCallableTarget) -> String?
  let cloudLogo: (String) -> String?
  let effortLabel: (AgentModelReasoningEffort) -> String
  @State private var source: AgentModelPickerSource?
  @State private var expandedTargetId: String?
  @State private var expandedLegacy = false

  private var automatic: Bool { selection.mode == .automatic || selection.targetId.isEmpty }
  private var sortedAgents: [AgentCallableTarget] {
    AgentModelPickerPolicy.desktopTargets(agents, selectedId: selection.targetId)
  }
  private var cloudContacts: [GalaxySSIContact] {
    var seen: Set<String> = []
    return clouds.map(\.contact).filter { seen.insert($0.id).inserted }
  }
  private var activeSource: AgentModelPickerSource {
    if let source { return source }
    if cloudContacts.contains(where: { $0.id == selection.targetId }) { return .cloud }
    return AgentModelPickerPolicy.initialSource(selection: selection, agents: sortedAgents,
      hasCloud: !clouds.isEmpty, hasLocal: !localProfiles.isEmpty)
  }
  private var expandedId: String {
    let ids = activeSource == .desktop ? sortedAgents.map(\.id) : cloudContacts.map(\.id)
    if let expandedTargetId, expandedTargetId.isEmpty || ids.contains(expandedTargetId) { return expandedTargetId }
    return ids.contains(selection.targetId) ? selection.targetId : ids.first ?? ""
  }
  private var currentAgent: AgentCallableTarget? {
    guard !automatic else { return nil }
    return sortedAgents.first { $0.id == selection.targetId }
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          summary
          choice(title: t("galaxyssi.agent.model_selection.automatic", "Automatic"),
            detail: t("agent_model_picker.auto_detail", "Choose by task"), icon: "arrow.triangle.branch",
            selected: automatic, action: onAutomatic)
          Picker(t("agent_model_picker.source", "Model source"), selection: Binding(
            get: { activeSource }, set: { source = $0; expandedTargetId = nil; expandedLegacy = false }
          )) {
            Text(t("agent_model_picker.desktop", "Desktop")).tag(AgentModelPickerSource.desktop)
            Text(t("agent_model_picker.cloud", "Cloud")).tag(AgentModelPickerSource.cloud)
            Text(t("agent_model_picker.local", "On-device")).tag(AgentModelPickerSource.local)
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("ios.agent.model-picker.sources")
          sourceContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      }
      footer
    }
    .onChange(of: expandedId) { _ in expandedLegacy = false }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(t("agent_model_picker.current", "Current conversation"))
        .font(.system(size: 11, weight: .semibold)).foregroundColor(.galaxySSIAccent)
      Text(currentTitle).font(.system(size: 18, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary).fixedSize(horizontal: false, vertical: true)
      Text(currentDetail).font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if !automatic && !manualAvailable {
        Label(t("galaxyssi.agent.model_selection.unavailable", "Unavailable"), systemImage: "exclamationmark.triangle")
          .font(.system(size: 12)).foregroundColor(.orange)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(11)
    .background(Color.galaxySSIAccent.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .accessibilityIdentifier("ios.agent.model-picker.summary")
  }

  private var currentTitle: String {
    if automatic { return t("galaxyssi.agent.model_selection.automatic", "Automatic") }
    if selection.targetId == "local-llm", let local = localProfiles.first(where: { $0.id == selection.modelId }) { return local.displayName }
    if let cloud = clouds.first(where: isChosenCloud) {
      return cloud.model.displayName.ifBlank(cloud.model.modelId)
    }
    if let agent = currentAgent {
      let id = agent.invocationProfile.normalizedModelId(selection.modelId)
      if let model = agent.invocationProfile.models.first(where: { $0.id == id }) { return modelTitle(model) }
    }
    return selection.modelId.isEmpty ? selection.displayName.ifBlank(selection.targetId) : AgentModelPickerPolicy.modelLabel(selection.modelId)
  }

  @ViewBuilder private var sourceContent: some View {
    switch activeSource {
    case .desktop:
      if sortedAgents.isEmpty { empty(t("agent_model_picker.no_desktop", "No desktop agents available")) }
      ForEach(sortedAgents) { target in
        Divider()
        let label = AgentModelPickerPolicy.desktopLabel(target.title)
        provider(title: label.name, detail: label.device, asset: agentLogo(target), id: target.id,
          selectable: target.invocationProfile.models.isEmpty) { onAgent(target, "") }
        if expandedId == target.id { models(target) }
      }
      GalaxySSISecurityNavigationRow(title: t("galaxyssi.agent.model_selection.scan_agent", "Scan or paste Agent QR"),
        subtitle: "", systemImage: "qrcode.viewfinder", tint: .galaxySSIAccent, badge: "") { AddContactView(autoOpenScanner: true) }
    case .cloud:
      if cloudContacts.isEmpty { empty(t("agent_model_picker.no_cloud", "No cloud models configured")) }
      ForEach(cloudContacts) { contact in
        Divider()
        provider(title: contact.displayName, detail: t("agent_model_picker.direct", "Direct from phone"),
          asset: cloudLogo(contact.cloudProvider), id: contact.id, selectable: false) {}
        if expandedId == contact.id {
          ForEach(clouds.filter { $0.contact.id == contact.id && !RetiredAgentModelPolicy.isRetired($0.model.modelId) }) { item in
            choice(title: item.model.displayName.ifBlank(item.model.modelId), detail: item.model.modelId,
              selected: isChosenCloud(item)) { onCloud(item) }
          }
        }
      }
      GalaxySSISecurityNavigationRow(title: t("galaxyssi.discover.add_cloud_model", "Add Cloud Model"),
        subtitle: "", systemImage: "cloud", tint: .galaxySSIAccent, badge: "") { CloudModelProviderSelectionView() }
    case .local:
      if localProfiles.isEmpty { empty(t("agent_model_picker.no_local", "No on-device models enabled")) }
      ForEach(localProfiles) { profile in
        choice(title: profile.displayName, detail: t("galaxyssi.agent.model_selection.local_subtitle", "Installed and ready on this iPhone"),
          icon: "iphone", selected: !automatic && selection.targetId == "local-llm" && selection.modelId == profile.id) { onLocal(profile) }
      }
      GalaxySSISecurityNavigationRow(title: t("galaxyssi.settings.local_model", "Local Model Settings"),
        subtitle: "", systemImage: "arrow.down.circle", tint: .galaxySSIAccent, badge: "") { GalaxySSILocalModelLabView() }
    }
  }

  private func provider(title: String, detail: String, asset: String?, id: String, selectable: Bool,
                        action: @escaping () -> Void) -> some View {
    Button {
      if selectable { action() }
      else { expandedTargetId = expandedId == id ? "" : id; expandedLegacy = false }
    } label: {
      HStack(spacing: 10) {
        if let asset { Image(asset).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true) }
        else { Image(systemName: "cpu").frame(width: 36, height: 36).foregroundColor(.galaxySSIAccent) }
        Text(title).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
        if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary).frame(maxWidth: 110).lineLimit(2) }
        Image(systemName: selectable ? (selection.targetId == id && !automatic ? "checkmark.circle.fill" : "circle") :
          (expandedId == id ? "chevron.up" : "chevron.down")).frame(width: 20)
      }
      .foregroundColor(.galaxySSITextPrimary).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityIdentifier("ios.agent.model-picker.provider." + id)
  }

  @ViewBuilder private func models(_ target: AgentCallableTarget) -> some View {
    let selectedId = !automatic && selection.targetId == target.id ? target.invocationProfile.normalizedModelId(selection.modelId) : ""
    let groups = AgentModelPickerPolicy.modelGroups(target, selectedModelId: selectedId)
    ForEach(groups.visible) { model in modelChoice(model, target: target, selected: model.id == selectedId) }
    if !groups.folded.isEmpty {
      Button { expandedLegacy.toggle() } label: {
        HStack {
          Text(t("agent_model_picker.older", "Older models"))
          Spacer()
          Image(systemName: expandedLegacy ? "chevron.up" : "chevron.down")
        }.font(.system(size: 13)).foregroundColor(.galaxySSITextSecondary).frame(minHeight: 44)
      }.buttonStyle(.plain).accessibilityIdentifier("ios.agent.model-picker.older")
      if expandedLegacy { ForEach(groups.folded) { model in modelChoice(model, target: target, selected: false) } }
    }
  }

  private func modelChoice(_ model: AgentModelOption, target: AgentCallableTarget, selected: Bool) -> some View {
    choice(title: modelTitle(model), detail: modelDetail(model), selected: selected) { onAgent(target, model.id) }
      .accessibilityIdentifier("ios.agent.model-picker.option." + target.id + "." + model.id)
  }

  private func modelTitle(_ model: AgentModelOption) -> String {
    model.displayName == model.id ? AgentModelPickerPolicy.modelLabel(model.id) : model.displayName
  }

  private func isChosenCloud(_ item: AgentModelPickerCloudChoice) -> Bool {
    !automatic && selection.targetId == item.contact.id &&
      (selection.modelId == item.model.modelId ||
        (selection.modelId.isEmpty && item.contact.selectedCloudModel?.modelId == item.model.modelId))
  }

  private func modelDetail(_ model: AgentModelOption) -> String {
    switch model.id {
    case "gpt-6.2-astra": return t("agent_model_picker.astra", "Complex analysis and development")
    case "gpt-6.2-sol": return t("agent_model_picker.sol", "Everyday chat and coding")
    case "gpt-6.1-terra": return t("agent_model_picker.terra", "Visual reasoning")
    case "gpt-6-luna": return t("agent_model_picker.luna", "Quick, focused tasks")
    default: return model.description
    }
  }

  private func choice(title: String, detail: String, icon: String? = nil, selected: Bool,
                      action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if let icon { Image(systemName: icon).frame(width: 32).foregroundColor(.galaxySSIAccent) }
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(.galaxySSITextPrimary)
          if !detail.isEmpty && detail.caseInsensitiveCompare(title) != .orderedSame {
            Text(detail).font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundColor(selected ? .galaxySSIAccent : .galaxySSITextSecondary).frame(width: 20)
      }
      .padding(.horizontal, 9).padding(.vertical, 5).frame(minHeight: 44)
      .background(selected ? Color.galaxySSIAccent.opacity(0.10) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      if let target = currentAgent, !target.invocationProfile.reasoningEfforts.isEmpty {
        Text(t("galaxyssi.agent.model_selection.reasoning_effort", "Reasoning effort"))
          .font(.system(size: 12, weight: .semibold)).foregroundColor(.galaxySSITextPrimary)
        Picker(t("galaxyssi.agent.model_selection.reasoning_effort", "Reasoning effort"), selection: Binding(
          get: { selection.reasoningEffort },
          set: { onEffort(target.invocationProfile.normalizedModelId(selection.modelId), $0) }
        )) {
          ForEach(target.invocationProfile.reasoningEfforts) { effort in Text(effortLabel(effort)).tag(effort) }
        }.pickerStyle(.segmented).accessibilityIdentifier("ios.agent.model-picker.effort")
      }
      Label(remembersNewChats ? t("agent_model_picker.remember", "New chats use your last selection") :
        t("agent_model_picker.saved", "Saved for this conversation"), systemImage: "bookmark")
        .font(.system(size: 11)).foregroundColor(.galaxySSITextSecondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 16).padding(.bottom, 8).background(Color.galaxySSISurface)
  }

  private func empty(_ title: String) -> some View {
    Text(title).font(.system(size: 13)).foregroundColor(.galaxySSITextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
