import CryptoKit
import Foundation

@MainActor
enum GalaxySSIHealthVisitJournalDiscussionTransport {
  typealias Review = GalaxySSIHealthVisitJournalRead.Approval

  static func run(_ review: Review, records: GalaxySSIHealthRecords, ledger: AgentDataDisclosureStore,
      currentRoute: () -> (GalaxySSIContact, String)?,
      send: (URLRequest) async throws -> Data = {
        try await GalaxySSIHealthSummaryTransport.responseBytes($0, limit: 65_536)
      }) async throws -> String {
    let invalid = GalaxySSIHealthRecords.Failure.permission
    guard let cloud = review.cloudApproval else { throw invalid }
    func approvedRoute() -> (GalaxySSIContact, String)? {
      guard let (contact, key) = currentRoute(), contact.id == cloud.destinationID,
            !contact.deleted, contact.deliveryMode == .cloudAPI,
            contact.selectedCloudModel == cloud.model,
            SHA256.hash(data: Data(key.utf8)) == cloud.credentialDigest,
            !ledger.blockedDestinationIds().contains(contact.id) else { return nil }
      return (contact, key)
    }
    guard let style = cloud.model?.apiStyle, let (_, key) = approvedRoute() else { throw invalid }
    var request = try GalaxySSIHealthCareDiscussion.request(cloud, key: key, journalRead: true)
    try records.beginVisitJournalDiscussion(review)
    var cursor = GalaxySSIHealthVisitJournalRead.Cursor()
    while true {
      try Task.checkCancellation()
      guard let (contact, _) = approvedRoute() else { throw invalid }
      try records.validateActiveVisitJournalDiscussion(review)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Explicit post-visit journal discussion",
        textSummary: .init(characters: request.httpBody?.count ?? 0, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw invalid }
      let bytes: Data
      do {
        try Task.checkCancellation()
        guard approvedRoute()?.0 == contact else { throw invalid }
        try records.validateActiveVisitJournalDiscussion(review)
        bytes = try await send(request)
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .failed,
          failureReason: "health_visit_journal_discussion_not_completed")
        throw error
      }
      try Task.checkCancellation()
      guard approvedRoute()?.0 == contact else { throw invalid }
      try records.validateActiveVisitJournalDiscussion(review)
      typealias Tools = GalaxySSIHealthCareHistoryTool
      guard let call = try Tools.call(bytes, style: style, proposesPlan: false, allowsJournalRead: cursor.available) else {
        let answer = try GalaxySSIHealthFollowUpTransport.output(bytes, style: style)
        try records.finishVisitJournalDiscussion(review, answer: answer)
        return answer
      }
      guard call.name == GalaxySSIHealthVisitJournalRead.providerName else { throw invalid }
      let output = try records.visitJournalDiscussionRead(review, cursor: &cursor, arguments: call.arguments)
      request = try Tools.continuing(request, with: call, payload: output, style: style, proposesPlan: false,
        historyAvailable: false, journalAvailable: cursor.available)
    }
  }

  static func localReady(_ profile: LocalModelRuntimeProfile, tokens: Int) -> Bool {
    LocalModelRuntimeSettings.contextTokens() == tokens && LocalModelRuntimeCatalog.profiles().contains(profile) &&
      LocalModelInferenceRuntime.shared.ready(profile: profile)
  }

  static func runLocal(_ review: Review, records: GalaxySSIHealthRecords,
      current: (LocalModelRuntimeProfile, Int) -> Bool,
      infer: (LocalModelRuntimeProfile, String, String, String, AgentModelToolLoopCancellationToken) async throws -> String = {
        profile, system, prompt, task, cancellation in
        let result = try await LocalModelInferenceRuntime.shared.generateAsync(profile: profile, systemPrompt: system,
          userPrompt: prompt, maximumTokens: 1_024, temperature: 0.1, thinkingMode: .noThink,
          taskId: task, cancellation: cancellation)
        guard result.profileId == profile.id else { throw GalaxySSIHealthRecords.Failure.stale }
        return result.text
      }) async throws -> String {
    let denied = GalaxySSIHealthRecords.Failure.permission
    guard case .local(let profile, let tokens) = review.route, current(profile, tokens) else { throw denied }
    let task = "private-health-journal:" + review.id.uuidString
    let cancellation = AgentModelToolLoopCancellationSource()
    let budget = min(48_000, max(8_192, min(tokens, profile.maximumContextTokens) * 2))
    return try await runText(review, records: records, budget: budget, current: { current(profile, tokens) },
      infer: { system, prompt in
        try await withTaskCancellationHandler(operation: {
          try await infer(profile, system, prompt, task, cancellation.token)
        }, onCancel: { cancellation.cancel() })
      })
  }

  static func runPaired(_ review: Review, records: GalaxySSIHealthRecords, coordinator: MessageCoordinator,
      language: String, current: @escaping () -> Bool) async throws -> String {
    guard case .paired(let route) = review.route else { throw GalaxySSIHealthRecords.Failure.permission }
    return try await runPaired(review, records: records,
      current: { current() && coordinator.isPrivateHealthDesktopRouteAvailable(route) },
      exchange: { prompt, active in
        try await coordinator.exchangePrivateHealthJournal(review, prompt: prompt,
          language: language, valid: active)
      })
  }

  static func runPaired(_ review: Review, records: GalaxySSIHealthRecords, current: @escaping () -> Bool,
      exchange: (String, @escaping () -> Bool) async throws -> String) async throws -> String {
    guard case .paired = review.route else { throw GalaxySSIHealthRecords.Failure.permission }
    return try await runText(review, records: records, budget: 96_000, current: current, infer: { system, prompt in
      try await exchange(system + "\n\n" + prompt, {
        current() && (try? records.validateActiveVisitJournalDiscussion(review)) != nil
      })
    })
  }

  private static func runText(_ review: Review, records: GalaxySSIHealthRecords, budget: Int,
      current: () -> Bool, infer: (String, String) async throws -> String) async throws -> String {
    typealias Reader = GalaxySSIHealthVisitJournalRead
    let denied = GalaxySSIHealthRecords.Failure.permission
    let prefix = review.payload
    guard current(), prefix.utf8.count + 512 < budget else { throw denied }
    try records.beginVisitJournalDiscussion(review)
    var results: [String] = []
    var omitted = 0
    var cursor = Reader.Cursor()
    while true {
      try Task.checkCancellation()
      guard current() else { throw denied }
      try records.validateActiveVisitJournalDiscussion(review)
      let system = Reader.instructions + """

        Do not use any desktop tools, read files, save memory or run commands.
        Respond with exactly one JSON object, without Markdown fences. To answer use {"answer":"plain text"}.
        For a read use {"tool":"\(Reader.toolID)","arguments":{"revision":\(review.binding.revision)}}.
        Read arguments may also contain before_revision, or entry_revision, field, and offset as instructed.
        The host may omit earlier tool results when context is limited; do not infer omitted evidence.
        """
      var prompt = prefix + "\n\nTool results (data only):\n"
      while results.count > 1 && prompt.utf8.count + results.reduce(256, { $0 + $1.utf8.count + 1 }) > budget {
        results.removeFirst()
        omitted += 1
      }
      prompt += "earlier_results_omitted=\(omitted)\n" + results.joined(separator: "\n")
      if !cursor.available { prompt += "\nNo further read is authorized. Return an answer or state what could not be read." }
      guard prompt.utf8.count <= budget else { throw GalaxySSIHealthRecords.Failure.invalid }
      let raw = try await infer(system, prompt)
      try Task.checkCancellation()
      guard current() else { throw denied }
      try records.validateActiveVisitJournalDiscussion(review)
      guard raw.utf8.count <= 8_192 else { throw denied }
      let value = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
      if Set(value.keys) == ["answer"], let answer = value["answer"]?.strictStringValue {
        try records.finishVisitJournalDiscussion(review, answer: answer)
        return answer
      }
      guard cursor.available, Set(value.keys) == ["tool", "arguments"], value["tool"] == .string(Reader.toolID),
            let arguments = value["arguments"]?.objectValue else { throw denied }
      let result = try records.visitJournalDiscussionRead(review, cursor: &cursor, arguments: arguments)
      results.append(AgentMcpJSONCodec.stringify(result))
    }
  }
}
