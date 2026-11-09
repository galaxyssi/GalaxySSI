import CryptoKit
import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareResearchLifecycle: ViewModifier {
  typealias Research = GalaxySSIHealthCareResearch
  @ObservedObject var store: GalaxySSIStore
  let coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var worker: Task<Void, Never>?
  @State private var running: Running?

  private struct Running {
    let authorization: Research.Authorization
    let job: UUID
  }

  private var models: [String: CloudModelConfig] {
    store.contacts.reduce(into: [:]) { models, contact in
      if !contact.deleted, contact.deliveryMode == .cloudAPI { models[contact.id] = contact.selectedCloudModel }
    }
  }

  func body(content: Content) -> some View {
    content
      .onAppear(perform: wake)
      .onDisappear { worker?.cancel() }
      .onChange(of: scene) { if $0 == .active { wake() } else { worker?.cancel() } }
      .onChange(of: store.profile.identityFingerprint) { _ in worker?.cancel(); wake() }
      .onChange(of: models) { _ in wake() }
      .onChange(of: store.serverLinks) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { wake() }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
        worker?.cancel()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in wake() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in wake() }
      .task(id: scene == .active) {
        guard scene == .active else { return }
        while !Task.isCancelled {
          let records = GalaxySSIHealthRecords(owner: store.profile.identityFingerprint, secrets: store.secrets)
          let waiting = (try? records.dispatchedLocalCareDesktopResearch().isEmpty) == false
          do { try await Task.sleep(nanoseconds: waiting ? 5_000_000_000 : 30_000_000_000) }
          catch { return }
          if !Task.isCancelled { wake() }
        }
      }
  }

  private func wake() {
    let owner = store.profile.identityFingerprint
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable else { return }
    let records = GalaxySSIHealthRecords(owner: owner, secrets: store.secrets)
    if let running {
      let job = (try? records.load())?.localCareResearch?.jobs[running.authorization.concern.uuidString]
      if job?.id != running.job || job?.state != .completed {
        let available = running.authorization.pairedDesktop.map(coordinator.isPrivateHealthDesktopRouteAvailable) ??
          (route(running.authorization, owner: owner) != nil)
        if records.currentLocalCareResearchJob(running.authorization, id: running.job) == nil || !available { worker?.cancel() }
      }
    }
    guard worker == nil else { return }
    worker = Task {
      defer { running = nil; worker = nil }
      await Task.yield()
      for _ in 0..<8 {
        guard !Task.isCancelled, owner == store.profile.identityFingerprint, scene == .active,
              UIApplication.shared.isProtectedDataAvailable else { return }
        coordinator.flushPrivateHealthDesktopCancellations()
        for auth in (try? records.load().localCareResearch?.authorizations.values.map { $0 }) ?? [] {
          if let route = auth.pairedDesktop, !coordinator.isPrivateHealthDesktopRouteConfigured(route) {
            try? records.revokeLocalCareResearch(auth.concern)
          }
        }
        let queued = (try? records.reconcileLocalCareResearch()) ?? []
        settleDesktopReplies(records)
        guard let (authorization, job) = queued.first(where: {
          $0.0.pairedDesktop.map(coordinator.isPrivateHealthDesktopRouteAvailable) ?? true
        }) else { return }
        if let paired = authorization.pairedDesktop {
          await runDesktop(authorization, route: paired, queued: job, records: records)
        } else {
          await run(authorization, queued: job, records: records)
        }
      }
    }
  }

  private func route(_ authorization: Research.Authorization, owner: String) -> (GalaxySSIContact, CloudModelConfig, String)? {
    guard scene == .active, UIApplication.shared.isProtectedDataAvailable, store.profile.identityFingerprint == owner,
          let contact = store.contact(id: authorization.contact), !contact.deleted, contact.deliveryMode == .cloudAPI,
          let model = contact.selectedCloudModel, model.modelId == authorization.model,
          let endpoint = authorization.endpoint, GalaxySSIHealthCareDiscussion.endpoint(for: model) == endpoint,
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
          GalaxySSIHealthCareDiscussion.destination(contactID: contact.id, model: model, endpoint: endpoint,
            credential: SHA256.hash(data: Data(key.utf8))) == authorization.destination,
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(contact.id) else { return nil }
    return (contact, model, key)
  }

  private func runDesktop(_ authorization: Research.Authorization, route: GalaxySSIHealthDesktopResearch.Route,
                          queued: Research.Job, records: GalaxySSIHealthRecords) async {
    running = .init(authorization: authorization, job: queued.id)
    defer { running = nil }
    guard let job = try? records.transitionLocalCareResearch(queued, concern: authorization.concern, to: .preparing)
    else { return }
    do {
      let question = GalaxySSILocalization.string("galaxyssi.health.research.request",
        fallback: "Review this concern using the research handoff. State missing context. Do not adopt or schedule anything.",
        language: language)
      var approval = try records.prepareLocalCareDesktopDiscussion(id: authorization.concern, metric: authorization.metric,
        question: question, route: route, research: job)
      if approval.proposesPlan {
        for source in GalaxySSIHealthCareEvidence.PublicSource.allCases where authorization.sources.contains(source) {
          try Task.checkCancellation()
          try records.validateLocalCareDiscussionApproval(approval)
          do {
            approval.evidence.append(try await GalaxySSIHealthCareEvidence.fetch(source, binding: .init(approval)))
          } catch {
            try Task.checkCancellation()
            try records.validateLocalCareDiscussionApproval(approval)
            _ = try records.transitionLocalCareResearch(job, concern: authorization.concern, to: .sourceUnavailable)
            return
          }
        }
      }
      try Task.checkCancellation()
      guard coordinator.isPrivateHealthDesktopRouteAvailable(route) else { throw GalaxySSIHealthRecords.Failure.permission }
      let prompt = try GalaxySSIHealthDesktopResearch.prompt(approval)
      try records.beginLocalCareDiscussionTurn(approval)
      let binding = try records.bindLocalCareDesktopResearch(authorization, job: job.id,
        sender: store.profile.galaxySSIId, reviewedAt: approval.reviewedAt)
      try coordinator.queuePrivateHealthDesktopResearch(binding, prompt: prompt, language: language)
    } catch {
      guard let current = records.currentLocalCareResearchJob(authorization, id: job.id) else { return }
      let state: Research.State = Task.isCancelled && current.state == .preparing ? .queued : .failed
      _ = try? records.transitionLocalCareResearch(current, concern: authorization.concern, to: state)
    }
  }

  private func settleDesktopReplies(_ records: GalaxySSIHealthRecords) {
    for (authorization, job, binding) in ((try? records.dispatchedLocalCareDesktopResearch()) ?? []).prefix(8) {
      guard !Task.isCancelled, coordinator.isPrivateHealthDesktopRouteAvailable(binding.route) else { continue }
      do {
        guard let reply = try coordinator.privateHealthDesktopReply(binding) else { continue }
        let approval = try records.prepareLocalCareDesktopDiscussion(id: authorization.concern,
          metric: authorization.metric, question: "", route: binding.route, research: job, resume: binding)
        try records.validateLocalCareDiscussionTurn(approval)
        if approval.proposesPlan {
          try records.saveLocalCarePlan(approval, arguments: GalaxySSIHealthDesktopResearch.planArguments(reply.content))
        } else {
          try records.finishLocalCareDiscussionTurn(approval, answer: reply.content)
        }
        coordinator.markPrivateHealthDesktopReplyApplied(binding)
      } catch {
        guard let current = records.currentLocalCareResearchJob(authorization, id: job.id) else { continue }
        _ = try? records.transitionLocalCareResearch(current, concern: authorization.concern, to: .failed)
      }
    }
  }

  private func run(_ authorization: Research.Authorization, queued: Research.Job, records: GalaxySSIHealthRecords) async {
    guard let (contact, model, key) = route(authorization, owner: records.owner) else {
      try? records.revokeLocalCareResearch(authorization.concern)
      return
    }
    running = .init(authorization: authorization, job: queued.id)
    defer { running = nil }
    guard let job = try? records.transitionLocalCareResearch(queued, concern: authorization.concern, to: .preparing)
    else { return }
    do {
      let question = GalaxySSILocalization.string("galaxyssi.health.research.request",
        fallback: "Review this concern using the research handoff. State missing context. Do not adopt or schedule anything.",
        language: language)
      var approval = try records.prepareLocalCareDiscussion(id: authorization.concern, metric: authorization.metric,
        question: question, destinationID: contact.id, model: model, credential: key, proposesPlan: true, research: job)
      if approval.proposesPlan {
        for source in GalaxySSIHealthCareEvidence.PublicSource.allCases where authorization.sources.contains(source) {
          try Task.checkCancellation()
          try records.validateLocalCareDiscussionApproval(approval)
          do {
            approval.evidence.append(try await GalaxySSIHealthCareEvidence.fetch(source, binding: .init(approval)))
          } catch {
            try Task.checkCancellation()
            try records.validateLocalCareDiscussionApproval(approval)
            _ = try records.transitionLocalCareResearch(job, concern: authorization.concern, to: .sourceUnavailable)
            return
          }
        }
      }
      try Task.checkCancellation()
      guard route(authorization, owner: records.owner) != nil else { throw GalaxySSIHealthRecords.Failure.permission }
      let payload = try approval.providerPayload()
      let request = try GalaxySSIHealthCareDiscussion.request(approval, key: key)
      let ledger = coordinator.healthDisclosureStore
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Standing authorization for scoped Health research",
        textSummary: .init(characters: payload.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw GalaxySSIHealthRecords.Failure.permission }
      var status: AgentDisclosureStatus = .failed
      defer {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: status,
          failureReason: status == .failed ? "health_research_not_completed" : "")
      }
      try records.beginLocalCareDiscussionTurn(approval)
      try Task.checkCancellation()
      try records.validateLocalCareDiscussionTurn(approval)
      var bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
      status = .sent
      if approval.questionCursor != nil || approval.feedbackCursor != nil {
        bytes = try await GalaxySSIHealthScopedReadTransport.finish(approval, records: records, initial: bytes,
          request: request, style: model.apiStyle, ledger: ledger, currentDestination: {
            route(authorization, owner: records.owner)?.0
          })
      }
      try Task.checkCancellation()
      guard route(authorization, owner: records.owner) != nil else { throw GalaxySSIHealthRecords.Failure.permission }
      try records.validateLocalCareDiscussionTurn(approval)
      if approval.proposesPlan {
        try records.saveLocalCarePlan(approval, arguments: GalaxySSIHealthCarePlan.arguments(bytes, style: model.apiStyle))
      } else {
        try records.finishLocalCareDiscussionTurn(approval,
          answer: GalaxySSIHealthFollowUpTransport.output(bytes, style: model.apiStyle))
      }
    } catch {
      guard let current = records.currentLocalCareResearchJob(authorization, id: job.id) else { return }
      let state: Research.State = Task.isCancelled ? (current.state == .dispatched ? .interrupted : .queued) : .failed
      _ = try? records.transitionLocalCareResearch(current, concern: authorization.concern, to: state)
    }
  }
}
