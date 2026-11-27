import Foundation

extension MessageCoordinator {
  func executeVoiceMessageDraft(
    _ invocation: AgentNativeToolInvocation, anchor: VoiceAppCaptureAnchor, store: GalaxySSIStore, legacy: Bool = false
  ) -> AgentNativeToolExecutionResult {
    let context = invocation.context
    guard let session = anchor.draftSession, let speech = voiceAppContexts.spoken(anchor),
      let key = store.turnReceiptKey(conversation: context.conversationId, turn: context.turnId),
      store.turnReceiptStore.read(key)?.voiceInput == true else {
      return .failure(code: "voice_origin_required", message: "A current captured speech turn with verified input origin is required.")
    }
    let speaker = VoiceMessageDraft.Speaker(owner: store.profile.identityFingerprint, session: session,
      conversation: context.conversationId, turn: context.turnId)
    let draft = voiceAppContexts.messageDraft
    let input = invocation.input
    let command = legacy ? "prepare" : input["operation"]?.stringValue ?? ""
    let revision = input["revision"]?.stringValue ?? ""
    let contactID = input["contact_id"]?.stringValue ?? ""
    switch command {
    case "status": return .success(output: draft.status(speaker))
    case "cancel": return draft.cancel(speaker, revision: revision)
    case "choose": return draft.choose(speaker, revision: revision, id: contactID, spokenOption: speech.choice)
    case "prepare", "change_recipient":
      let query = (input["query"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard query.utf16.count <= 256, contactID.utf16.count <= 256,
        !query.isEmpty || voiceAppContexts.hasObservedContact(contactID, anchor: anchor) else {
        return .failure(code: "recipient_required", message: "Use an exact name or a contact ID observed in this utterance.")
      }
      let exact = store.visibleContacts.first { $0.id == contactID }
      let name = query.isEmpty ? exact?.displayName ?? "" : query
      guard !name.isBlank, query.isEmpty || contactID.isEmpty || exact?.displayName.caseInsensitiveCompare(query) == .orderedSame else {
        return .failure(code: "recipient_conflict", message: "The supplied name and contact ID do not identify the same recipient.")
      }
      let candidates = store.visibleContacts.filter { contact in
        contact.displayName.caseInsensitiveCompare(name) == .orderedSame && contact.isCommunicable &&
          ((contact.type.caseInsensitiveCompare("person") == .orderedSame && contact.opaquePhoneRoutes != nil && contact.desktopId.isBlank) ||
            (contact.isDesktopDeviceContact && store.serverLinks.contains { $0.paired && $0.desktopId == contact.desktopId }))
      }
      guard candidates.count <= 64 else {
        return .failure(code: "recipient_scope_too_large", message: "Narrow the recipient name before continuing.")
      }
      let people = candidates.compactMap { contact -> VoiceMessageDraft.Person? in
        guard let route = voiceMessageRecipientBinding(contact, store: store) else { return nil }
        return .init(id: contact.id, name: contact.displayName, route: route)
      }
      voiceAppContexts.recordObservedContacts(people.map(\.id), anchor: anchor)
      if command == "change_recipient" { return draft.change(speaker, revision: revision, people: people) }
      return draft.begin(speaker, text: input["text"]?.stringValue ?? "", people: people)
    case "confirm":
      do { try invocation.checkpoint() } catch {
        return .failure(code: "voice_request_cancelled", message: "The request ended before sending.")
      }
      guard let claim = draft.claim(speaker, revision: revision, confirmed: speech.confirmed) else {
        return .failure(code: "spoken_confirmation_required", message: "Read back the current recipient and body, then wait for a new explicit spoken confirmation. No new message was sent.")
      }
      // Claim precedes every possible transport path; errors consume the draft rather than retry it.
      guard let contact = store.visibleContacts.first(where: { $0.id == claim.recipient.id }),
        contact.isCommunicable, voiceMessageRecipientBinding(contact, store: store) == claim.recipient.route else {
        return draft.finish(claim, result: .failure(code: "recipient_changed", message: "Recipient authority changed. Do not automatically resend."))
      }
      return draft.finish(claim, result: enqueueConfirmedVoiceRecipient(claim.text, contactID: contact.id, context: context))
    default: return .failure(code: "invalid_voice_message_operation", message: "Choose a supported draft operation.")
    }
  }

  private func voiceMessageRecipientBinding(_ contact: GalaxySSIContact, store: GalaxySSIStore) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var parts = [contact.id, contact.galaxySSIId, contact.displayName, contact.type, contact.agentKind,
      contact.connectorAgentId, contact.desktopId, contact.identityFingerprint, contact.deliveryMode.rawValue,
      contact.mqttTopic ?? "", contact.mqttInboxTopic ?? "", contact.linkClientRouteId ?? "",
      contact.linkLocalFingerprint ?? "", contact.signalBundleRef ?? ""]
    if contact.isDesktopDeviceContact {
      guard let link = store.serverLinks.first(where: { $0.paired && $0.desktopId == contact.desktopId }),
        let bytes = try? encoder.encode(link.routes), let route = String(data: bytes, encoding: .utf8) else { return nil }
      parts += [link.desktopFingerprint, link.signalName, route, link.accessProfile, link.accessScopes.sorted().joined(separator: ",")]
    } else {
      guard contact.opaquePhoneRoutes != nil else { return nil }
    }
    return AgentTurnReceiptEvidence.hash(parts.map { "\($0.utf8.count):\($0)" }.joined())
  }
}
