import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthInstructionProposalView: View {
  typealias Assist = GalaxySSIHealthInstructionProposal
  typealias Instruction = GalaxySSIHealthInstruction
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  let records: GalaxySSIHealthRecords
  let history: Instruction.History
  @State private var selected = ""
  @State private var review: Assist.Approval?
  @State private var pending: Assist.Proposal?
  @State private var task: Task<Void, Never>?
  @State private var active: UUID?
  @State private var failed = false
  @State private var noProposal = false
  @State private var applying = false

  var body: some View {
    NavigationView {
      List {
        if canRead {
          GalaxySSIHealthInstructionQuote(source: history.item.entry.source, language: language)
          if let pending {
            proposal(pending)
          } else if let review {
            Section(t("assist_scope", "Only the selected quotation, page and recognition method will be sent.")) {
              Text(review.model.modelId)
              Text(review.endpoint.absoluteString).font(.footnote).textSelection(.enabled)
              Button(t("assist_send", "Send selected quotation")) { send(review) }.disabled(task != nil)
              Button(t("cancel", "Cancel"), role: .cancel) { self.review = nil }
            }
          } else {
            Picker(t("assist_provider", "Model provider"), selection: $selected) {
              Text(t("assist_choose", "Select a model")).tag("")
              ForEach(contacts) { contact in
                Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ?? "")).tag(contact.id)
              }
            }.disabled(task != nil)
            Button(t("assist_preview", "Review before sending"), action: prepare)
              .disabled(selected.isEmpty || task != nil)
          }
          if task != nil { ProgressView() }
          if failed { Text(t("assist_failed", "No proposal was saved. Check access or select a clearer quotation.")) }
          if noProposal { Text(t("assist_none", "No single instruction was identified in this quotation.")) }
        }
      }
      .navigationTitle(t("assist_title", "Suggest fields from original"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("done", "Done")) { close() } } }
    }
    .navigationViewStyle(.stack)
    .task {
      do { if canRead { pending = try records.pendingVisitInstructionProposal(history) } }
      catch { failed = true }
    }
    .task(id: history.expires) {
      let remaining = max(0, min(Instruction.readingLifetime, history.expires.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
      if !Task.isCancelled { close() }
    }
    .onChange(of: scene) { if $0 != .active { close() } }
    .onChange(of: store.profile.identityFingerprint) { _ in close() }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in close() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in close() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { update in
      if !applying, update.object as? String == records.owner { close() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { update in
      if update.object as? String == records.owner { close() }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && Date() < history.expires &&
      store.profile.identityFingerprint == records.owner
  }
  private var contacts: [GalaxySSIContact] {
    store.visibleContacts.filter { route($0.id) != nil }
  }
  private func route(_ id: String) -> (GalaxySSIContact, CloudModelConfig, String)? {
    guard let contact = store.contact(id: id), !contact.deleted, contact.deliveryMode == .cloudAPI,
          let model = contact.selectedCloudModel, GalaxySSIHealthCareDiscussion.endpoint(for: model) != nil,
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(id) else { return nil }
    return (contact, model, key)
  }
  private func prepare() {
    guard canRead, task == nil, let (_, model, key) = route(selected) else { return }
    do {
      review = try records.prepareVisitInstructionProposal(history, contactID: selected, model: model, key: key)
      failed = false; noProposal = false
    } catch { failed = true }
  }
  private func send(_ approval: Assist.Approval) {
    guard canRead, task == nil, review?.id == approval.id,
          let (contact, model, key) = route(approval.contactID),
          approval.matches(contactID: contact.id, model: model, key: key) else { return }
    review = nil
    failed = false; noProposal = false
    do {
      try records.validateVisitInstructionProposal(approval, history: history)
      let request = try Assist.request(approval, key: key)
      let ledger = coordinator.healthDisclosureStore
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Explicit Health source transcription",
        textSummary: .init(characters: request.httpBody?.count ?? 0, kinds: [.messageText, .systemInstructions]))
      guard ticket.allowed else { failed = true; return }
      active = approval.id
      task = Task {
        var status: AgentDisclosureStatus = .failed
        defer {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: status,
            failureReason: status == .failed ? "health_instruction_proposal_not_completed" : "")
          if active == approval.id { active = nil; task = nil }
        }
        do {
          try Task.checkCancellation()
          guard active == approval.id, canRead, let (before, current, credential) = route(approval.contactID),
                approval.matches(contactID: before.id, model: current, key: credential) else { return }
          try records.validateVisitInstructionProposal(approval, history: history)
          let bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
          status = .sent
          try Task.checkCancellation()
          guard active == approval.id, canRead, let (after, nextModel, nextKey) = route(approval.contactID),
                approval.matches(contactID: after.id, model: nextModel, key: nextKey) else { return }
          try records.validateVisitInstructionProposal(approval, history: history)
          guard let arguments = try? GalaxySSIHealthCarePlan.arguments(bytes, style: model.apiStyle, toolName: Assist.tool)
          else {
            _ = try GalaxySSIHealthFollowUpTransport.output(bytes, style: model.apiStyle)
            noProposal = true
            return
          }
          pending = try records.stageVisitInstructionProposal(arguments, approval: approval, history: history)
        } catch { if !Task.isCancelled, active == approval.id { failed = true } }
      }
    } catch { failed = true }
  }

  @ViewBuilder private func proposal(_ proposal: Assist.Proposal) -> some View {
    Section(Instruction.kindTitle(proposal.kind, language)) {
      Text(t("assist_unreviewed", "Model suggestions are unreviewed. Verify each field against the original."))
        .font(.footnote).foregroundColor(.secondary)
      ForEach(proposal.kind.fields) { field in
        if let value = proposal.fields[field] {
          VStack(alignment: .leading, spacing: 3) {
            Text(Instruction.fieldTitle(field, language)).font(.headline)
            if !value.quote.isEmpty { Text(value.quote).textSelection(.enabled) }
            Text(certainty(value.certainty)).font(.footnote).foregroundColor(.secondary)
          }
        }
      }
    }
    Button(t("assist_apply", "Apply as unreviewed draft")) { resolve(proposal, apply: true) }
    Button(t("assist_discard", "Discard suggestion"), role: .destructive) { resolve(proposal, apply: false) }
  }
  private func resolve(_ proposal: Assist.Proposal, apply: Bool) {
    guard canRead, pending?.id == proposal.id, task == nil else { return }
    applying = true
    defer { applying = false }
    do {
      if apply {
        try records.applyVisitInstructionProposal(proposal, history: history)
        close()
      } else {
        try records.dismissVisitInstructionProposal(proposal, history: history)
        pending = nil
      }
    } catch { failed = true }
  }
  private func certainty(_ value: Assist.Certainty) -> String {
    switch value {
    case .quoted: return t("assist_quoted", "Quoted from source")
    case .uncertain: return t("assist_uncertain", "Uncertain")
    case .notFound: return t("assist_not_found", "Not found")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String { Instruction.text(key, fallback, language) }
  private func close() { clear(); dismiss() }
  private func clear() {
    task?.cancel(); task = nil; active = nil; review = nil; pending = nil; selected = ""
    failed = false; noProposal = false
  }
}
