import UIKit

extension GalaxySSIHealthAgentLab {
  static let marker = "local-health-labs:"
  static let stage = "local_health_labs"
  struct Launch: Identifiable {
    let id = UUID()
    let owner: String
    let conversation: String
    let mode: Mode
    let through: Date
    var supplement = ""
    var draftDigest = ""
  }
  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.local_lab." + key, fallback: fallback, language: language)
  }
  static func mode(_ message: ChatMessage) -> Mode? {
    guard !message.isMine, !message.isSystem, message.contactId == "hermes", message.sourceConversationId.isBlank,
      UUID(uuidString: message.turnId) != nil, message.deliveryTrace.first?.stage == stage else { return nil }
    return [Mode.results, .abnormal].first { message.remoteMessageId == marker + $0.rawValue + ":" + message.turnId }
  }
  static func intent(_ raw: String, following: Bool, language: String) -> Mode? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: ".?!")).lowercased()
    guard (2...220).contains(value.count) else { return nil }
    func matches(_ key: String, _ fallback: String) -> Bool {
      let patterns = Set([fallback, text("pattern_" + key, fallback, language), text("pattern_" + key, fallback, LanguagePolicySettings.zhCN)])
      return patterns.contains { value.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    guard !matches("exclude", #"\b(?:my (?:father|mother|child|friend|wife|husband)|their|his|her|someone|example|hypothetical|don't|do not|cancel)\b"#) else { return nil }
    if following {
      if matches("remind", #"\b(?:remind|schedule|plan)\b.*\b(?:recheck|retest|follow.up)\b|\b(?:recheck|retest|follow.up)\b.*\b(?:remind|next week|next month)\b"#) { return .remind }
      if matches("note", #"\b(?:that|this|sample|blood|actually|add|note)\b.*\b(?:fasting|meal|sample|blood draw)\b"#) { return .note }
    }
    guard !matches("general", #"\b(?:what does|what is|why|treat|medicine|template|example|book|cost|write)\b"#) else { return nil }
    if matches("overview", #"^(?:(?:please )?(?:show|open|check|list|view|find)(?: me)? )?(?:my )?(?:(?:latest|last|recent) )?(?:lab|laboratory|blood test|health check)(?: (?:test|report))?(?: (?:results?|records?|report|abnormal results?))?$"#) {
      return matches("abnormal_word", #"\b(?:abnormal|high|low|outside)\b"#) ? .abnormal : .results
    }
    if following && matches("all", #"^(?:(?:show|list|view) )?(?:all (?:the )?)?(?:results|records|report)$"#) { return .results }
    if following && matches("abnormal", #"^(?:(?:show|list|which|any|the) )*(?:abnormal|high|low|out.of.range)(?: (?:results|ones|values))?$"#) { return .abnormal }
    if matches("scope", #"\b(?:lab|laboratory|blood test|health check)\b"#),
      matches("request", #"\b(?:my|show|check|list|open|view|latest|last|recent)\b"#),
      matches("results", #"\b(?:results?|values?|records?|report|abnormal|high|low)\b"#) {
      return matches("abnormal_word", #"\b(?:abnormal|high|low|outside)\b"#) ? .abnormal : .results
    }
    return nil
  }
  static func suggestedDay(_ raw: String, now: Date, calendar: Calendar) -> Date? {
    func matches(_ key: String, _ fallback: String) -> Bool {
      [fallback, text("pattern_" + key, fallback, LanguagePolicySettings.zhCN)].contains {
        raw.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
      }
    }
    if matches("month", #"\bnext month\b"#) { return calendar.date(byAdding: .month, value: 1, to: now) }
    if matches("week", #"\bnext week\b"#) { return calendar.date(byAdding: .day, value: 7, to: now) }
    if matches("tomorrow", #"\btomorrow\b"#) { return calendar.date(byAdding: .day, value: 1, to: now) }
    return nil
  }
}

extension AgentHomeView {
  func offerLocalLabQuery(_ question: String, hasAttachments: Bool) -> Bool {
    let last = transcriptMessages.last { !$0.isSystem }
    let following = last.map { GalaxySSIHealthAgentLab.mode($0) != nil && $0.conversationId == store.activeAgentConversationId } ?? false
    guard let mode = GalaxySSIHealthAgentLab.intent(question, following: following, language: interfaceLanguage) else { return false }
    guard !hasAttachments, homeVisible, scenePhase == .active, store.canReadAgentTranscript,
      UIApplication.shared.isProtectedDataAvailable, screenAssistantRunID == nil, screenAssistantConversationID.isEmpty,
      let session = activeAgentSession, session.status == .active, session.mergedIntoConversationId.isBlank,
      session.globalTopicKey.isBlank else {
      attachmentError = GalaxySSIHealthAgentLab.text("local_only", "Open saved results from an active conversation without attachments.", interfaceLanguage)
      return true
    }
    let follow = mode == .note || mode == .remind
    let launch = GalaxySSIHealthAgentLab.Launch(owner: store.profile.identityFingerprint, conversation: session.id, mode: mode,
      through: follow ? min(last?.createdAt ?? Date(), Date()) : Date(), supplement: follow ? String(question.prefix(500)) : "",
      draftDigest: AgentTurnReceiptEvidence.hash(question))
    if session.collaborationRoster != nil { localLabGroupRequest = launch; return true }
    openLocalLab(launch)
    return true
  }

  func openPrivateLocalLab(_ launch: GalaxySSIHealthAgentLab.Launch) {
    guard homeVisible, scenePhase == .active, store.canReadAgentTranscript,
      UIApplication.shared.isProtectedDataAvailable, launch.owner == store.profile.identityFingerprint,
      launch.conversation == store.activeAgentConversationId,
      AgentTurnReceiptEvidence.hash(draft.trimmingCharacters(in: .whitespacesAndNewlines)) == launch.draftDigest else { return }
    let session = store.createAgentConversation(title: GalaxySSIHealthAgentLab.text("title", "Saved lab results", interfaceLanguage), privateMode: true)
    guard store.switchAgentSession(session.id) else { return }
    localLabGroupRequest = nil
    openLocalLab(.init(owner: launch.owner, conversation: session.id, mode: launch.mode, through: Date()))
  }

  func openLocalLab(_ launch: GalaxySSIHealthAgentLab.Launch) {
    if launch.mode == .results || launch.mode == .abnormal {
      let turn = UUID().uuidString
      let label = GalaxySSIHealthAgentLab.text(launch.mode == .abnormal ? "question_abnormal" : "question_all",
        launch.mode == .abnormal ? "Show my saved abnormal lab results" : "Show my saved lab results", interfaceLanguage)
      _ = store.appendOutgoing(label, to: "hermes", status: .delivered, turnId: turn, readOnlyAnalysis: true,
        conversationOverride: launch.conversation, sourceTrace: GalaxySSIHealthAgentLab.stage)
      _ = store.appendIncoming(GalaxySSIHealthAgentLab.text("open", "Open saved lab results", interfaceLanguage), from: "hermes",
        remoteMessageId: GalaxySSIHealthAgentLab.marker + launch.mode.rawValue + ":" + turn,
        traceStage: GalaxySSIHealthAgentLab.stage, conversationId: launch.conversation, turnId: turn)
    }
    draft = ""; attachmentError = ""; actionTrayPresented = false
    localLabLaunch = launch
  }
}
