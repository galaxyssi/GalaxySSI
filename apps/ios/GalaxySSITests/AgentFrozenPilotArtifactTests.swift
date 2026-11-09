import CryptoKit
import XCTest
@testable import GalaxySSI

enum FrozenPilot {
  static let nodes = ["draft", "review", "final"]
  static let format = "galaxyssi.ios.remote-pilot-candidate.v1"
  enum Failure: Error { case source, dispatch, output, conflict, integrity }

  struct Identity: Codable, Equatable {
    let run: String
    let conversation: String
    let turn: String
    let task: String
  }

  struct Source: Codable, Equatable {
    let pilot: String
    let identity: Identity
    let protocolSHA256: String
    let goalSHA256: String
    let target: String
    let model: String
    let effort: String
  }

  struct Binding: Codable, Equatable {
    let source: Source
    let slot: String
    let caseID: String
    let arm: String

    func artifactID() throws -> String {
      let identity = source.identity
      let ids = [identity.run, identity.conversation, identity.turn, identity.task]
      guard [source.pilot, slot, caseID].allSatisfy({ value in
        value.range(of: #"\A[A-Za-z0-9][A-Za-z0-9_-]{0,47}\z"#, options: .regularExpression) != nil
      }), ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 160 }), Set(ids).count == ids.count,
            ["single", "team"].contains(arm), isDigest(source.protocolSHA256), isDigest(source.goalSHA256),
            !source.target.isEmpty, !source.model.isEmpty, AgentModelReasoningEffort(rawValue: source.effort) != nil
      else { throw Failure.source }
      return "candidate-" + digest(try encode(self))
    }

    func person(for node: String) -> String { arm == "team" && node == "review" ? "reviewer" : "analyst" }
  }

  struct Reference: Codable, Equatable {
    let artifactID: String
    let sha256: String
  }

  struct Dispatch: Codable {
    let node: String
    let person: String
    let identity: Identity
    let child: String
    let key: String
    let target: String
    let model: String
    let effort: String
    let promptSHA256: String
    let returnedOutputSHA256: String
    var androidSourceMessageID: Int64? = nil
  }

  struct ReportProvenance: Codable {
    var origin = "completed_test_report"
    let reportSHA256: String
    var providerAttested = false
  }

  struct Output: Codable {
    let node: String
    let text: String
  }

  struct Payload: Codable {
    var format = FrozenPilot.format
    var trust = "unverified_candidate"
    var grantsPermissions = false
    let binding: Binding
    let finalOutput: String
    let finalOutputSHA256: String
    let outputs: [Output]
    let dispatches: [Dispatch]
    var reportRecovery: ReportProvenance? = nil

    func validate(expected: Binding) throws {
      guard format == (reportRecovery == nil ? FrozenPilot.format : FrozenPilot.recoveredFormat),
            trust == "unverified_candidate", !grantsPermissions,
            binding == expected else { throw Failure.source }
      if let reportRecovery {
        guard reportRecovery.origin == "completed_test_report", !reportRecovery.providerAttested,
              isDigest(reportRecovery.reportSHA256), Set(dispatches.map(\.child)).count == nodes.count,
              Set(dispatches.map(\.key)).count == nodes.count,
              Set(dispatches.compactMap(\.androidSourceMessageID)).count == nodes.count else { throw Failure.dispatch }
      }
      let source = expected.source
      guard outputs.map(\.node) == nodes, dispatches.map(\.node) == nodes,
            outputs.last?.text.utf8.elementsEqual(finalOutput.utf8) == true,
            digest(Data(finalOutput.utf8)) == finalOutputSHA256 else { throw Failure.output }
      for (output, dispatch) in zip(outputs, dispatches) {
        guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              output.text.utf8.count <= 96_000, dispatch.returnedOutputSHA256 == digest(Data(output.text.utf8))
        else { throw Failure.output }
        let validIdentity: Bool
        if reportRecovery != nil {
          validIdentity = !dispatch.child.isBlank && !dispatch.key.isBlank &&
            dispatch.androidSourceMessageID == androidSourceID(dispatch.key)
        } else {
          validIdentity = dispatch.androidSourceMessageID == nil &&
            dispatch.child == AgentTeamExecutionRuntime.stableChildRunId(supervisorRunId: source.identity.run,
              instanceId: dispatch.node) && dispatch.key == source.identity.run + ":" + dispatch.node
        }
        guard validIdentity, dispatch.identity == source.identity, dispatch.person == expected.person(for: dispatch.node),
              dispatch.target == source.target, dispatch.model == source.model, dispatch.effort == source.effort,
              isDigest(dispatch.promptSHA256) else { throw Failure.dispatch }
      }
    }
  }

  struct Envelope: Codable {
    let reference: Reference
    let body: Data
  }

  struct Locator: Codable {
    let binding: Binding
    let reference: Reference
  }

  struct ProbeOriginal: Encodable {
    let source: Source
    let finalOutput: String
    let observerOutputs: [String]
    var reportRecovery: ReportProvenance? = nil
  }

  static func capture(binding: Binding, snapshot: AgentTeamExecutionSnapshot, dispatches: [Dispatch]) throws -> Payload {
    _ = try binding.artifactID()
    let identity = binding.source.identity
    guard snapshot.state == .succeeded, snapshot.supervisorRunId == identity.run,
          snapshot.teamId == identity.run + "-team", snapshot.conversationId == identity.conversation,
          snapshot.taskId == identity.task, snapshot.primaryAgentId == binding.source.target, snapshot.primaryMemberId == "final",
          digest(Data(snapshot.goal.utf8)) == binding.source.goalSHA256,
          snapshot.members.map(\.memberId) == nodes,
          snapshot.members.allSatisfy({ $0.status == .succeeded && $0.agentId == binding.source.target }) else { throw Failure.source }
    let artifact = Payload(binding: binding, finalOutput: snapshot.finalOutput,
      finalOutputSHA256: digest(Data(snapshot.finalOutput.utf8)),
      outputs: snapshot.members.map { .init(node: $0.memberId, text: $0.output) }, dispatches: dispatches)
    try artifact.validate(expected: binding)
    return artifact
  }

  final class Store: @unchecked Sendable {
    private static let lock = NSRecursiveLock()
    let directory: URL
    private let cipher: GalaxySSIAttachmentAtRestCipher

    init(directory: URL, secrets: GalaxySSISecretStore, account: String) {
      self.directory = directory
      cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: account)
    }

    func freeze(_ artifact: Payload) throws -> Reference {
      Self.lock.lock()
      defer { Self.lock.unlock() }
      try artifact.validate(expected: artifact.binding)
      let bytes = try encode(artifact)
      guard bytes.count <= 512_000 else { throw Failure.output }
      let reference = Reference(artifactID: try artifact.binding.artifactID(), sha256: digest(bytes))
      let file = url(reference)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: file.path) {
        _ = try read(expected: artifact.binding, reference: reference)
        return reference
      }
      let encrypted = try cipher.encrypt(encode(Envelope(reference: reference, body: bytes)), purpose: reference.artifactID)
      let temporary = directory.appendingPathComponent(UUID().uuidString + ".staged")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try encrypted.write(to: temporary, options: .withoutOverwriting)
      do {
        // Publishing a hard link fails atomically when another writer has already frozen this source.
        try FileManager.default.linkItem(at: temporary, to: file)
      } catch {
        guard FileManager.default.fileExists(atPath: file.path) else { throw error }
        _ = try read(expected: artifact.binding, reference: reference)
      }
      return reference
    }

    func read(expected: Binding, reference: Reference) throws -> Payload {
      Self.lock.lock()
      defer { Self.lock.unlock() }
      guard try expected.artifactID() == reference.artifactID, isDigest(reference.sha256) else { throw Failure.source }
      let bytes = try boundedRead(url(reference), limit: 800_000)
      let raw = try cipher.decrypt(bytes, expectedPurpose: reference.artifactID)
      let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
      guard envelope.reference == reference, digest(envelope.body) == reference.sha256 else { throw Failure.conflict }
      let artifact = try JSONDecoder().decode(Payload.self, from: envelope.body)
      try artifact.validate(expected: expected)
      return artifact
    }

    func url(_ reference: Reference) -> URL { directory.appendingPathComponent(reference.artifactID + ".saenc") }
  }

  static func boundedRead(_ url: URL, limit: Int) throws -> Data {
    let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard metadata.isRegularFile == true, metadata.isSymbolicLink == false,
          let size = metadata.fileSize, size <= limit else { throw Failure.integrity }
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    let bytes = try input.read(upToCount: limit + 1) ?? Data()
    guard bytes.count == size else { throw Failure.integrity }
    return bytes
  }

  static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
}

final class AgentFrozenPilotArtifactTests: XCTestCase {
  private typealias Pilot = FrozenPilot
  private let objective = "Return a method for the synthetic source task."

  func testFreezeBeforeRuntimeCleanupReopensExactUnverifiedArtifact() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let store = Pilot.Store(directory: root, secrets: secrets, account: "frozen-fixture")
    let binding = binding(pilot: "synthetic", protocolSHA256: String(repeating: "a", count: 64))
    let ref = try await capture(binding: binding, store: store)
    let reopened = Pilot.Store(directory: root, secrets: secrets, account: "frozen-fixture")
    let saved = try reopened.read(expected: binding, reference: ref)
    XCTAssertEqual(saved.outputs.map(\.node), Pilot.nodes)
    XCTAssertEqual(saved.finalOutput, output("final"))
    XCTAssertFalse(saved.grantsPermissions)
    XCTAssertEqual(saved.trust, "unverified_candidate")
    XCTAssertNil(try Data(contentsOf: store.url(ref)).range(of: Data(output("final").utf8)))
    let other = self.binding(pilot: "foreign", protocolSHA256: binding.source.protocolSHA256)
    XCTAssertThrowsError(try reopened.read(expected: other, reference: ref))
    var corrupt = try Data(contentsOf: store.url(ref))
    corrupt[corrupt.count - 1] ^= 1
    try corrupt.write(to: store.url(ref), options: .atomic)
    XCTAssertThrowsError(try reopened.read(expected: binding, reference: ref))
  }

  func testWriteOnceRejectsCompetingChangedOutputForSameSource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Pilot.Store(directory: root, secrets: InMemorySecretStore(), account: "write-once-fixture")
    let binding = binding(pilot: "synthetic", protocolSHA256: String(repeating: "a", count: 64))
    let ref = try await capture(binding: binding, store: store)
    let saved = try store.read(expected: binding, reference: ref)
    XCTAssertEqual(try store.freeze(saved), ref)
    let updated = "Different final output"
    let newDigest = Pilot.digest(Data(updated.utf8))
    let prior = try XCTUnwrap(saved.dispatches.last)
    let changed = Pilot.Dispatch(node: prior.node, person: prior.person, identity: prior.identity,
      child: prior.child, key: prior.key, target: prior.target, model: prior.model, effort: prior.effort,
      promptSHA256: prior.promptSHA256, returnedOutputSHA256: newDigest)
    let competing = Pilot.Payload(binding: binding, finalOutput: updated, finalOutputSHA256: newDigest,
      outputs: Array(saved.outputs.dropLast()) + [.init(node: "final", text: updated)],
      dispatches: Array(saved.dispatches.dropLast()) + [changed])
    XCTAssertThrowsError(try store.freeze(competing))
    XCTAssertEqual(try store.read(expected: binding, reference: ref).finalOutput, output("final"))
    let fresh = Pilot.Store(directory: root.appendingPathComponent("competing"), secrets: InMemorySecretStore(),
      account: "competing-fixture")
    let first = Task.detached { Result { try fresh.freeze(saved) } }
    let second = Task.detached { Result { try fresh.freeze(competing) } }
    let writes = await [first.value, second.value]
    let committed = writes.compactMap { try? $0.get() }
    XCTAssertEqual(committed.count, 1)
    let winner = try XCTUnwrap(committed.first)
    let resolved = try fresh.read(expected: binding, reference: winner)
    XCTAssertEqual(resolved.finalOutput, winner == ref ? saved.finalOutput : updated)
  }

  func testTruncatedRuntimeOutputCannotFreeze() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = Pilot.Store(directory: root, secrets: InMemorySecretStore(), account: "truncate-fixture")
    let binding = binding(pilot: "synthetic", protocolSHA256: String(repeating: "a", count: 64))
    do {
      _ = try await capture(binding: binding, store: store, maxOutputCharacters: 8)
      XCTFail("Truncated output must not produce a candidate")
    } catch Pilot.Failure.output {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  func testOptInFreezeSyntheticPilotArtifact() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let pilot = env["GALAXYSSI_FREEZE_PILOT_ID"] else { throw XCTSkip("Artifact freezing is opt-in") }
    let file = URL(fileURLWithPath: try XCTUnwrap(env["GALAXYSSI_FREEZE_PROTOCOL_FILE"]))
    let protocolBytes = try Pilot.boundedRead(file, limit: 60_000)
    let digest = Pilot.digest(protocolBytes)
    guard !protocolBytes.isEmpty, digest == env["GALAXYSSI_FREEZE_PROTOCOL_SHA256"] else { throw Pilot.Failure.source }
    let binding = binding(pilot: pilot, protocolSHA256: digest)
    _ = try binding.artifactID()
    let root = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
      .appendingPathComponent("XCTest-FrozenPilotArtifacts", isDirectory: true)
      .appendingPathComponent(pilot, isDirectory: true)
    let account = "xc-test-frozen-pilot:" + pilot
    let store = Pilot.Store(directory: root, secrets: KeychainSecretStore.shared, account: account)
    let locator: Pilot.Locator
    if let path = env["GALAXYSSI_FREEZE_REFERENCE_FILE"] {
      locator = try JSONDecoder().decode(Pilot.Locator.self,
        from: Pilot.boundedRead(URL(fileURLWithPath: path), limit: 20_000))
      guard locator.binding.source.pilot == pilot, locator.binding.source.protocolSHA256 == digest
      else { throw Pilot.Failure.source }
    } else {
      let reference = try await capture(binding: binding, store: store)
      locator = .init(binding: binding, reference: reference)
    }
    let ref = locator.reference
    let reopened = Pilot.Store(directory: root, secrets: KeychainSecretStore.shared, account: account)
    let saved = try reopened.read(expected: locator.binding, reference: ref)
    let attachment = XCTAttachment(data: try Pilot.encode(locator), uniformTypeIdentifier: "public.json")
    attachment.name = "Frozen candidate locator"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("GALAXYSSI_FROZEN_ARTIFACT_ID=\(ref.artifactID)")
    print("GALAXYSSI_FROZEN_ARTIFACT_SHA256=\(ref.sha256)")
    if let export = env["GALAXYSSI_FREEZE_EXPORT_DIRECTORY"] {
      let bytes = try Pilot.encode(Pilot.ProbeOriginal(source: saved.binding.source, finalOutput: saved.finalOutput,
        observerOutputs: saved.outputs.dropLast().map(\.text), reportRecovery: saved.reportRecovery))
      guard bytes.count <= 192_000 else { throw Pilot.Failure.output }
      let hash = Pilot.digest(bytes)
      try bytes.write(to: URL(fileURLWithPath: export, isDirectory: true).appendingPathComponent(hash + ".json"),
        options: .withoutOverwriting)
      print("GALAXYSSI_ARTIFACT_PROBE_ORIGINAL_SHA256=\(hash)")
    }
  }

  private actor Receipts {
    private(set) var values: [Pilot.Dispatch] = []
    func record(_ dispatch: Pilot.Dispatch) throws {
      guard values.count < Pilot.nodes.count, Pilot.nodes[values.count] == dispatch.node else { throw Pilot.Failure.dispatch }
      values.append(dispatch)
    }
  }

  private func capture(binding: Pilot.Binding, store: Pilot.Store, maxOutputCharacters: Int = 16_000) async throws -> Pilot.Reference {
    let source = binding.source, identity = source.identity
    let receipts = Receipts(), runtimeStore = InMemoryAgentTeamExecutionStore()
    let runtime = AgentTeamExecutionRuntime(store: runtimeStore, mailbox: InMemoryAgentTeamMailbox(),
      limits: .init(maxChildren: 3, maxConcurrency: 1, maxOutputCharacters: maxOutputCharacters))
    defer { runtime.close(); runtimeStore.remove(supervisorRunId: identity.run) }
    let definition = AgentTeamDefinition(teamId: identity.run + "-team", primaryAgentId: source.target,
      members: Pilot.nodes.enumerated().map { index, node in
        .init(agentId: source.target, deliveryMode: node == "final" ? .respond : .observe, requiredCapabilities: [],
          role: node, objective: objective, dependsOnAgentIds: Set(Pilot.nodes.prefix(index)),
          context: ["_galaxyssi_member_model_id": source.model, AgentCollaborationReasoningSelection.contextKey: source.effort],
          instanceId: node)
      }, visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: "final")
    let request = AgentRunRequest(conversationId: identity.conversation, messageId: identity.turn, taskId: identity.task,
      runId: identity.run, parentRunId: "", goal: objective, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: identity.run, createdAtMillis: 1)
    let handle = try runtime.start(definition: definition, request: request, worker: ClosureAgentTeamMemberWorker { context in
      let node = context.member.memberId, child = context.request
      guard child.conversationId == identity.conversation, child.messageId == identity.turn, child.taskId == identity.task,
            child.parentRunId == identity.run, child.goal.utf8.elementsEqual(request.goal.utf8) else { throw Pilot.Failure.dispatch }
      let sections: [AgentCollaborationPromptBudget.Section] = [
        .init(name: AgentCollaborationPromptBudget.goal, body: child.goal), .init(name: "Node", body: node)
      ] + context.handoff.dependencies.map { .init(name: $0.childId, body: $0.output) }
      let prompt = try AgentCollaborationPromptBudget.assemble(required: sections, optional: []).text
      let text = self.output(node)
      try await receipts.record(.init(node: node, person: binding.person(for: node), identity: identity,
        child: child.runId, key: child.idempotencyKey, target: context.member.agentId,
        model: child.context.string("_galaxyssi_member_model_id"),
        effort: child.context.string(AgentCollaborationReasoningSelection.contextKey),
        promptSHA256: Pilot.digest(Data(prompt.utf8)), returnedOutputSHA256: Pilot.digest(Data(text.utf8))))
      return AgentSubagentOutput(content: text)
    })
    let snapshot = try await handle.wait()
    let artifact = try Pilot.capture(binding: binding, snapshot: snapshot, dispatches: await receipts.values)
    let ref = try store.freeze(artifact)
    runtimeStore.remove(supervisorRunId: identity.run)
    guard !handle.isActive, runtimeStore.snapshots().isEmpty else { throw Pilot.Failure.dispatch }
    return ref
  }

  private func binding(pilot: String, protocolSHA256: String) -> Pilot.Binding {
    let run = UUID().uuidString.lowercased()
    return .init(source: .init(pilot: pilot, identity: .init(run: run, conversation: "group-" + run, turn: "turn-" + run,
      task: "task-" + run), protocolSHA256: protocolSHA256, goalSHA256: Pilot.digest(Data(objective.utf8)),
      target: "fixture:codex", model: "frozen-model", effort: "high"), slot: "fixture", caseID: "source", arm: "team")
  }

  private func output(_ node: String) -> String { "Original synthetic output for \(node).\nSecond line." }
}
