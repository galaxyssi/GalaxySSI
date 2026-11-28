import Foundation

enum AgentPinnedDesktopTeam {
  static let pinKey = "_galaxyssi_pinned_desktop_team"
  static let personKey = "_galaxyssi_pinned_desktop_person"

  struct Route: Codable, Equatable {
    let target: String
    let desktop: String
    let fingerprint: String
    let clientRoute: String
    let name: String
    let model: String
    let effort: AgentModelReasoningEffort
    var digest: String {
      AgentBlobProtocol.sha256(Data([target, desktop, fingerprint, clientRoute, model, effort.rawValue]
        .joined(separator: "\u{001f}").utf8))
    }
  }

  struct Binding: Codable, Equatable {
    let owner: String
    let conversation: String
    let turn: String
    let objective: String
    let route: Route
    let coordinator: UUID
    let researcher: UUID
    var teamID: String { conversation + ":desktop-team" }

    func matches(_ roster: AgentCollaborationRoster) -> Bool {
      roster.workflow == .research && roster.coordinatorId == coordinator && coordinator != researcher &&
        roster.members.count == 2 && Set(roster.members.map(\.id)) == [coordinator, researcher] &&
        roster.members.allSatisfy {
          $0.resourceId == route.target && $0.modelId == route.model && !$0.mentionOnly &&
            $0.reasoningEffort == (route.effort == .automatic ? nil : route.effort.rawValue)
        }
    }
  }

  @MainActor final class Review {
    let launch: UUID
    let route: Route
    private var consumed = false
    init(launch: UUID, route: Route) { self.launch = launch; self.route = route }
    func claim(launch: UUID, current: Route?) -> Bool {
      guard !consumed else { return false }
      consumed = true
      return self.launch == launch && route == current
    }
  }

  static func manualCodex(_ selection: AgentModelSelection) -> Bool {
    selection.mode == .manual && (selection.targetId == "codex" || selection.targetId.hasSuffix(":codex"))
  }

  static func eligibleObjective(_ objective: String, language: String) -> Bool {
    let clinical = #"(?i)(?:\b(?:MRN|patient (?:id|name)|medical record number)|\x{60A3}\x{8005}\x{59D3}\x{540D}|\x{75C5}\x{5386}\x{53F7}|\x{75C5}\x{6B77}\x{865F}|\x{4F4F}\x{9662}\x{53F7}|\x{4F4F}\x{9662}\x{865F})\s*[:\x{FF1A}=#]\s*\S"#
    return AgentConversationalTeamCommand.allowsModelReview(objective, language: language) &&
      !AgentTaskRequirementAnalyzer.analyze(objective).localOnly &&
      objective.range(of: clinical, options: .regularExpression) == nil
  }

  @MainActor static func inspect(store: GalaxySSIStore, conversation: String, blocked: Set<String>) -> Route? {
    let selection = AgentModelSelectionSettings.selection(for: conversation, defaults: store.defaults)
    guard manualCodex(selection), !selection.modelId.isBlank, !RetiredAgentModelPolicy.isRetired(selection.modelId),
      store.agentTaskBudget.profile != .privateMode, store.agentSafetySettings.connectorCallsAllowed,
      !store.agentSafetySettings.executionPaused else { return nil }
    let candidates = store.visibleContacts.filter {
      $0.connectorAgentId == "codex" && $0.deliveryMode == .pcConnector &&
        (selection.targetId == "codex" || $0.id == selection.targetId)
    }
    guard candidates.count == 1, let contact = candidates.first, contact.isCommunicable,
      contact.pinned_team_codex_v1 == true, !blocked.contains(contact.id),
      !contact.desktopId.isBlank, !contact.identityFingerprint.isBlank,
      let link = store.serverLinks.first(where: { $0.desktopId == contact.desktopId && $0.paired }),
      contact.identityFingerprint.caseInsensitiveCompare(link.desktopFingerprint) == .orderedSame,
      !link.routes.clientRouteId.isBlank,
      let target = AgentCallableTargetCatalog.build(contacts: store.visibleContacts, apiKey: { store.apiKey(for: $0) })
        .first(where: { $0.id == contact.id && $0.kind == .agent && $0.status == .available }),
      target.invocationProfile.models.contains(where: { $0.id == selection.modelId }),
      selection.reasoningEffort == .automatic || target.invocationProfile.reasoningEfforts.contains(selection.reasoningEffort),
      contact.connectorAdapterName == "codex-app-server-or-cli" else { return nil }
    return Route(target: contact.id, desktop: link.desktopId, fingerprint: link.desktopFingerprint,
      clientRoute: link.routes.clientRouteId, name: link.desktopName.ifBlank(link.desktopId),
      model: selection.modelId, effort: selection.reasoningEffort)
  }

  @MainActor static func current(_ binding: Binding, store: GalaxySSIStore, blocked: Set<String>) -> Bool {
    guard store.canReadAgentTranscript, binding.owner == store.profile.identityFingerprint, UUID(uuidString: binding.turn) != nil,
      let session = store.agentSession(id: binding.conversation), session.id == binding.conversation,
      session.status == .active, !session.privateMode, !session.trackingPaused,
      session.globalTopicKey.isBlank, session.parentConversationId.isBlank, session.mergedIntoConversationId.isBlank,
      let roster = session.collaborationRoster, roster.pinnedDesktop == binding, binding.matches(roster),
      eligibleObjective(binding.objective, language: store.languagePolicy.interfaceLanguage),
      inspect(store: store, conversation: binding.conversation, blocked: blocked) == binding.route else { return false }
    return true
  }

  static func owns(_ context: AgentOutboundTeamContext, binding: Binding, roster: AgentCollaborationRoster) -> Bool {
    binding.matches(roster) && context.isManagedCollaboration && context.teamId == binding.teamID &&
      context.supervisorRunId == AgentTeamDispatchIds.supervisorRunId(teamId: binding.teamID) &&
      context.primaryInstanceId == binding.coordinator.uuidString.lowercased() &&
      context.member.agentId == binding.route.target &&
      context.member.context[pinKey] == binding.route.digest &&
      context.member.context[personKey] == context.member.memberId &&
      context.member.context["_galaxyssi_member_model_id"] == binding.route.model &&
      AgentTeamPlanCompiler.rosterMember(for: context.member, in: roster) != nil
  }

  static func owns(_ spec: AgentTeamDispatchSpec, binding: Binding, roster: AgentCollaborationRoster) -> Bool {
    guard binding.matches(roster), spec.definition.teamId == binding.teamID,
      spec.supervisorRunId == AgentTeamDispatchIds.supervisorRunId(teamId: binding.teamID),
      spec.definition.primaryMemberId == binding.coordinator.uuidString.lowercased(),
      spec.definition.members.count == 2,
      Set(spec.definition.members.map(\.memberId)) == Set(roster.members.map { $0.id.uuidString.lowercased() }) else { return false }
    return spec.definition.members.allSatisfy { member in
      let primary = member.memberId == binding.coordinator.uuidString.lowercased()
      return member.agentId == binding.route.target &&
        member.deliveryMode == (primary ? .respond : .observe) &&
        member.context["_galaxyssi_research_stage"] == (primary ? "DELIVER" : "EXPLORE") &&
        member.dependsOnAgentIds == (primary ? [binding.researcher.uuidString.lowercased()] : []) &&
        owns(AgentOutboundTeamContext(teamId: binding.teamID, supervisorRunId: spec.supervisorRunId,
          primaryInstanceId: spec.definition.primaryMemberId, member: member, sourceMessageId: "",
          isManagedCollaboration: true), binding: binding, roster: roster)
    }
  }
}
