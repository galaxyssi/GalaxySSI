import BackgroundTasks
import Combine
import CryptoKit
import Foundation
import UIKit

@MainActor
final class AgentIOSOriginalPageArchiveRuntime {
  private let store: GalaxySSIStore
  private var bound = true
  private var work: Task<Bool, Never>?
  private var runningJob: AgentIOSOriginalPageArchiveStore.Job?
  private var observation: AnyCancellable?
  private var notifications: [NSObjectProtocol] = []

  init(store: GalaxySSIStore) {
    self.store = store
    observation = store.objectWillChange.sink { [weak self] in
      Task { @MainActor in self?.contextChanged() }
    }
    notifications = [UIApplication.willResignActiveNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification, .galaxySSIRuntimePlaintextWillClear].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.work?.cancel() }
      }
    }
    AgentIOSOriginalPageArchiveBackground.bind(self)
  }

  deinit { notifications.forEach { NotificationCenter.default.removeObserver($0) } }

  func enqueue(_ preparation: AgentIOSPhonePublicHTMLPreparation, conversation: String, turn: String, expectedProfile: String) async {
    guard let name = preparation.originalSourceArchiveName,
          name.range(of: #"^original-page-[a-f0-9]{64}\.html\.txt$"#, options: .regularExpression) != nil else { return }
    let profile = expectedProfile
    let owner = AgentIOSOriginalPageArchiveStore.Job(id: "", profile: profile, conversation: conversation,
      turn: turn, url: preparation.sourceURL, name: preparation.attachment.displayName,
      language: store.languagePolicy.interfaceLanguage, source: Data())
    guard allows(owner) else { return }
    let queue = makeQueue(profile)
    let source = GalaxySSIPrivateChatFiles.directory("OriginalWebSources").appendingPathComponent(name)
    let saved = await Task.detached(priority: .utility) {
      do {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= AgentIOSOriginalPageDocument.maximumSourceBytes else { return false }
        let bytes = try Data(contentsOf: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard name == "original-page-\(hash).html.txt" else { return false }
        try queue.enqueue(source: bytes, url: owner.url, name: owner.name,
          language: owner.language, conversation: owner.conversation, turn: owner.turn)
        return true
      } catch { return false }
    }.value
    if saved { AgentIOSOriginalPageArchiveBackground.schedule(pending: true); wake() }
  }

  func wake() {
    guard bound, work == nil, UIApplication.shared.applicationState == .active else { return }
    start(limit: 4)
  }

  func backgroundSlice() async -> Bool {
    guard work == nil else { return false }
    start(limit: 1)
    guard let work else { return false }
    return await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
  }

  private func start(limit: Int) {
    guard bound, UIApplication.shared.isProtectedDataAvailable, store.canReadAgentTranscript else { return }
    work = Task { @MainActor [weak self] in
      guard let self else { return false }
      defer { self.work = nil; self.runningJob = nil }
      let profile = self.store.profile.identityFingerprint
      let queue = self.makeQueue(profile)
      var skipped = Set<String>(), completed = true
      for _ in 0..<limit {
        guard !Task.isCancelled, profile == self.store.profile.identityFingerprint else { completed = false; break }
        var candidate: AgentIOSOriginalPageArchiveStore.Job?
        while let next = await Self.next(queue, now: Self.now(), excluding: skipped) {
          guard !Task.isCancelled, self.bound, profile == self.store.profile.identityFingerprint else { break }
          if self.allows(next) { candidate = next; break }
          skipped.insert(next.id)
        }
        guard let job = candidate else { break }
        self.runningJob = job
        let worker = Task.detached(priority: .utility) { () throws -> Data in
          try Task.checkCancellation()
          if let staged = try queue.staged(job.id) { return staged }
          let provider = AgentIOSURLSessionWebMediaToolProvider()
          guard let definition = AgentIOSWebIntelligenceNativeToolCatalog.definitions().first(where: {
            $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch
          }) else { throw CocoaError(.featureUnsupported) }
          let started = Self.now()
          let invocation = AgentNativeToolInvocation(descriptor: definition.descriptor,
            input: ["url": .string(job.url)], context: .init(sessionId: job.conversation, turnId: job.turn,
              callerId: "galaxyssi.original-page-archive",
              grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
              grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]),
            startedAtEpochMillis: started, deadlineEpochMillis: started + 120_000,
            hardDeadlineEpochMillis: started + 120_000, nowMillis: Self.now,
            cancellationRequested: { Task.isCancelled }, progressReporter: { _, _ in })
          let document = try AgentIOSOriginalPageDocument.build(source: job.source, url: job.url, language: job.language) { address, limit in
            guard !Task.isCancelled, invocation.remainingTimeMillis > 0 else { return nil }
            return try? provider.originalPageAsset(address, maxBytes: limit, invocation: invocation)
          }
          try Task.checkCancellation()
          try queue.stage(document.data, id: job.id)
          return document.data
        }
        do {
          let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
          try Task.checkCancellation()
          guard self.allows(job) else { throw CancellationError() }
          try queue.publish(job, data: data)
        } catch {
          completed = false
          if !Task.isCancelled, self.allows(job), !(error is CancellationError) {
            await Task.detached(priority: .utility) { try? queue.failed(job, now: Self.now()) }.value
          }
          else { break }
        }
        self.runningJob = nil
      }
      // A future-due job keeps durable intent, including after OS expiration.
      let pending = await Self.next(queue, now: Int64.max, excluding: skipped) != nil
      if self.bound, profile == self.store.profile.identityFingerprint {
        AgentIOSOriginalPageArchiveBackground.schedule(pending: pending)
      }
      return completed && !Task.isCancelled && self.bound && profile == self.store.profile.identityFingerprint
    }
  }

  private func contextChanged() {
    if let runningJob, !allows(runningJob) { work?.cancel() }
    wake()
  }

  private func allows(_ job: AgentIOSOriginalPageArchiveStore.Job) -> Bool {
    guard bound, UIApplication.shared.isProtectedDataAvailable, store.canReadAgentTranscript,
          job.profile == store.profile.identityFingerprint, !job.profile.isBlank,
          !store.agentSafetySettings.executionPaused, store.agentSafetySettings.connectorCallsAllowed,
          store.agentSafetySettings.taskExecutionMode != .planOnly,
          let session = store.agentSession(id: job.conversation), session.status == .active,
          !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank else { return false }
    return store.agentSessionMessages(job.conversation).contains {
      $0.isMine && !$0.isSystem && $0.turnId.ifBlank($0.id.uuidString) == job.turn
    }
  }

  nonisolated private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
  nonisolated private static func next(_ queue: AgentIOSOriginalPageArchiveStore, now: Int64,
                                      excluding: Set<String>) async -> AgentIOSOriginalPageArchiveStore.Job? {
    await Task.detached(priority: .utility) { try? queue.due(now: now, excluding: excluding) }.value
  }
  private func makeQueue(_ profile: String) -> AgentIOSOriginalPageArchiveStore {
    AgentIOSOriginalPageArchiveStore(profile: profile, cipher: GalaxySSIAttachmentAtRestCipher(
      secrets: store.secrets, keyAccount: "web.original.archive.aes256.v1"))
  }
  func invalidate() { bound = false; work?.cancel() }
}

enum AgentIOSOriginalPageArchiveBackground {
  static let identifier = "com.galaxyssi.chat.ios.original-page-archive"
  private static let pendingKey = "galaxyssi.web.original.archive.pending.v1"
  @MainActor private static weak var runtime: AgentIOSOriginalPageArchiveRuntime?

  @MainActor static func bind(_ value: AgentIOSOriginalPageArchiveRuntime) {
    guard runtime !== value else { return }
    runtime?.invalidate()
    runtime = value
  }

  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      let completion = AgentKnowledgeBackgroundCompletion { success, _ in
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
      }
      let worker = Task { @MainActor in
        guard let runtime else { schedule(pending: true); completion.finish(success: false, pending: nil); return }
        let result = await runtime.backgroundSlice()
        completion.finish(success: result, pending: nil)
      }
      completion.onCancellation { worker.cancel() }
      task.expirationHandler = { completion.finish(success: false, pending: nil); schedule(pending: true) }
    }
    if UserDefaults.standard.bool(forKey: pendingKey) { schedule(pending: true) }
  }

  static func schedule(pending: Bool) {
    UserDefaults.standard.set(pending, forKey: pendingKey)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    guard pending else { return }
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresNetworkConnectivity = true
    request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }
}
