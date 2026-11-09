import CryptoKit
import XCTest
@testable import GalaxySSI

struct InterimPilotArchive {
  struct Entry: Equatable {
    let producer: AgentCollaborationToolEvidenceScope
    let milestoneID: String
    let artifactHash: String
    let originals: [Data]
    let observations: [String: Data]
  }

  let conversation: String
  let run: String
  let turn: String
  private(set) var entries: [String: Entry] = [:]
  private(set) var complete = false
  let peerReadProven = false
  let scientificAcceptanceProven = false

  var mayCleanUp: Bool { complete && !peerReadProven && !scientificAcceptanceProven }
  var report: AgentMcpJSONObject {
    let milestones = entries.sorted { $0.key < $1.key }.map { _, entry in
      AgentMcpJSONValue.object([
        "producer_member_id": .string(entry.producer.memberId), "producer_source_id": .string(entry.producer.sourceId),
        "milestone_id": .string(entry.milestoneID), "artifact_sha256": .string(entry.artifactHash),
        "originals_b64": .array(entry.originals.map { .string($0.base64EncodedString()) }),
        "observations_b64": .object(entry.observations.mapValues { .string($0.base64EncodedString()) })
      ])
    }
    return ["format": .string("galaxyssi.adaptive-pilot-milestones.v1"),
      "capture_role": .string("test_observer_not_agent"), "conversation_id": .string(conversation),
      "run_id": .string(run), "turn_id": .string(turn), "milestones": .array(milestones),
      "peer_read_proven": .bool(peerReadProven), "scientific_acceptance_proven": .bool(scientificAcceptanceProven)]
  }

  static func milestonePrefix(_ producer: AgentCollaborationToolEvidenceScope) -> String {
    "publication:" + AgentMcpJSONCodec.sha256(["run": .string(producer.runId),
      "member": .string(producer.memberId), "source": .string(producer.sourceId)]) + ":milestone:"
  }

  static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  mutating func capture(_ checkpoint: AgentTeamExecutionSnapshot, database: AgentTeamHistoryDatabase) throws {
    complete = false
    guard checkpoint.conversationId == conversation, checkpoint.supervisorRunId == run, checkpoint.taskId == turn
    else { throw AgentTeamHistoryDatabase.Failure.stale }
    let prior = entries
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let additions = try database.transaction { () -> [String: Entry] in
      guard let saved = try database.snapshots(runId: run).first, saved.conversationId == conversation,
            saved.taskId == turn, saved.teamId == checkpoint.teamId,
            saved.members.count == checkpoint.members.count,
            checkpoint.members.allSatisfy({ member in
              saved.members.contains {
                $0.memberId == member.memberId && $0.sourceMessageId == member.sourceMessageId &&
                  $0.agentId == member.agentId && $0.deliveryMode == member.deliveryMode &&
                  $0.researchStage == member.researchStage
              }
            })
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      var captured: [String: Entry] = [:]
      var seen = Set<String>()
      for member in checkpoint.members where member.deliveryMode == .observe ||
        member.researchStage == AgentSingleResearchCalibration.stage {
        let producer = AgentCollaborationToolEvidenceScope(runId: run, conversationId: conversation,
          turnId: turn, memberId: member.memberId, sourceId: member.sourceMessageId)
        let prefix = Self.milestonePrefix(producer)
        var cursor = ""
        while true {
          let keys = try database.milestoneKeys(conversationId: conversation, prefix: prefix, after: cursor)
          for key in keys {
            guard seen.insert(key).inserted,
                  let receipt = try database.researchRecord(AgentCollaborationResearchPublication.self,
                    conversationId: conversation, key: key, revision: 0),
                  let id = receipt.milestoneId, receipt.recordedAtMillis != nil, !receipt.references.isEmpty,
                  AgentCollaborationSourceAccess.validDigest(receipt.requestHash),
                  key == prefix + AgentMcpJSONCodec.sha256(["id": .string(id)])
            else { throw AgentTeamHistoryDatabase.Failure.corrupt }
            var originals: [Data] = []
            var observations: [String: Data] = [:]
            for ref in receipt.references {
              guard let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                conversationId: conversation, key: "object:" + ref.objectId, revision: ref.revision),
                record.reference == ref, record.runId == run, record.turnId == turn,
                record.authorId == producer.memberId, record.sourceId == producer.sourceId
              else { throw AgentTeamHistoryDatabase.Failure.stale }
              var unhashed = record
              unhashed.reference.sha256 = ""
              guard try Self.digest(encoder.encode(unhashed)) == ref.sha256
              else { throw AgentTeamHistoryDatabase.Failure.corrupt }
              originals.append(try encoder.encode(record))
              func save(_ bytes: Data, origin: String, id: String, hash: String) throws {
                guard Self.digest(bytes) == hash else { throw AgentTeamHistoryDatabase.Failure.corrupt }
                observations[origin + ":" + id + ":" + hash] = bytes
              }
              for read in record.frozenCloudReads ?? [] {
                guard let original = try database.readableCollaborationEvidence(id: read.evidenceId,
                  sha256: read.sha256, scope: producer) else { throw AgentTeamHistoryDatabase.Failure.stale }
                try save(original.bytes, origin: "cloud", id: read.evidenceId, hash: read.sha256)
              }
              for read in record.frozenNativeReads ?? [] {
                guard let native = try database.researchRecord(AgentCollaborationNativeToolObservation.self,
                  conversationId: conversation, key: "native-evidence:" + read.evidenceId, revision: 0),
                  native.conversationId == conversation, native.runId == run, native.turnId == turn
                else { throw AgentTeamHistoryDatabase.Failure.stale }
                try save(encoder.encode(native), origin: "native", id: read.evidenceId, hash: read.sha256)
              }
              for read in record.frozenDesktopReads ?? [] {
                let archiveKey = "desktop-evidence:" + read.evidenceId
                let runKey = AgentMcpJSONCodec.sha256(["run": .string(run), "turn": .string(turn)])
                let width = AgentDesktopToolEvidenceWire.maximumPageBytes
                guard let archive = try database.researchRecord(AgentDesktopToolEvidenceWire.AcceptanceArchive.self,
                  conversationId: conversation, key: "desktop-acceptance:" + runKey + ":" + read.evidenceId, revision: 0),
                  archive.binding.identity.conversationId == conversation, archive.binding.identity.turnId == turn,
                  archive.binding.teamSource?.supervisorRunId == run, archive.receipt.archiveId == read.evidenceId,
                  archive.receipt.sha256 == read.sha256, archive.receipt.totalBytes == read.totalBytes,
                  (1...AgentDesktopToolEvidenceWire.maximumOriginalBytes).contains(read.totalBytes),
                  archive.receipt.pageCount == (read.totalBytes - 1) / width + 1,
                  try database.researchRecord(AgentDesktopToolEvidenceWire.ArchiveReceipt.self,
                    conversationId: conversation, key: archiveKey, revision: 0) == archive.receipt
                else { throw AgentTeamHistoryDatabase.Failure.stale }
                var bytes = Data()
                for index in 0..<archive.receipt.pageCount {
                  guard let page = try database.researchRecord(Data.self, conversationId: conversation,
                    key: archiveKey, revision: Int64(index + 1)), page.count == min(width, read.totalBytes - index * width)
                  else { throw AgentTeamHistoryDatabase.Failure.corrupt }
                  bytes.append(page)
                }
                try save(bytes, origin: "desktop", id: read.evidenceId, hash: read.sha256)
              }
            }
            let entry = Entry(producer: producer, milestoneID: id, artifactHash: receipt.requestHash,
              originals: originals, observations: observations)
            guard prior[key] == nil || prior[key] == entry else { throw AgentTeamHistoryDatabase.Failure.stale }
            captured[key] = entry
          }
          guard keys.count == 33, let last = keys.last else { break }
          cursor = last
        }
      }
      return captured
    }
    entries.merge(additions) { saved, _ in saved }
    complete = true
  }
}

final class AgentInterimPilotArchiveTests: XCTestCase {
  func testObserverCapturesEveryMilestonePageAndSeparateDispatchWithoutProvingARead() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    var checkpoint = fixture.checkpoint
    XCTAssertTrue(fixture.history.upsert(checkpoint))
    var archive = fixture.archive()
    XCTAssertFalse(archive.mayCleanUp)
    try archive.capture(checkpoint, database: fixture.database)
    XCTAssertTrue(archive.entries.isEmpty)
    XCTAssertTrue(archive.mayCleanUp)
    let producer = fixture.scope(checkpoint.members[0])
    for index in 0..<35 {
      try fixture.publish("milestone-\(index)", scope: producer)
    }
    try archive.capture(checkpoint, database: fixture.database)
    XCTAssertEqual(archive.entries.count, 35)
    let saved = archive.entries
    try archive.capture(checkpoint, database: fixture.database)
    XCTAssertEqual(archive.entries, saved)
    checkpoint.members.append(.init(agentId: "peer", instanceId: "next-attempt", sourceMessageId: "next-source",
      dispatchCheckpoint: .accepted))
    checkpoint.updatedAtMillis += 1
    XCTAssertTrue(fixture.history.upsert(checkpoint))
    try fixture.publish("milestone-0", scope: fixture.scope(checkpoint.members[1]))
    try archive.capture(checkpoint, database: fixture.database)
    XCTAssertEqual(archive.entries.count, 36)
    XCTAssertFalse(archive.peerReadProven)
    XCTAssertFalse(archive.scientificAcceptanceProven)
    var foreign = checkpoint
    foreign.taskId = "foreign-turn"
    XCTAssertThrowsError(try archive.capture(foreign, database: fixture.database))
    XCTAssertEqual(archive.entries.count, 36)
    XCTAssertFalse(archive.mayCleanUp)
    foreign = checkpoint
    foreign.members[0].sourceMessageId = "forged-source"
    XCTAssertThrowsError(try archive.capture(foreign, database: fixture.database))
    XCTAssertEqual(archive.entries.count, 36)
  }

  func testMissingObservationPreventsPartialCaptureAndRetryReadsExactOriginalWithoutCoverage() throws {
    let fixture = try Fixture()
    defer { fixture.cleanup() }
    let checkpoint = fixture.checkpoint
    XCTAssertTrue(fixture.history.upsert(checkpoint))
    let producer = fixture.scope(checkpoint.members[0])
    try fixture.publish("normal", scope: producer)
    let observation = AgentCollaborationCloudToolEvidence(scope: producer, round: 1,
      call: .init(callId: "call", index: 0, name: "fixture_probe", argumentsJson: "{}"),
      output: "{\"value\":7}", succeeded: true, startedAtMillis: 2, finishedAtMillis: 3)
    let id = AgentMcpJSONCodec.sha256(["run": .string(producer.runId), "member": .string(producer.memberId),
      "source": .string(producer.sourceId), "round": .int(1), "call": .string("call"), "index": .int(0)])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let original = try encoder.encode(observation)
    let hash = InterimPilotArchive.digest(original)
    let coverageKey = "cloud-read-coverage:" + AgentMcpJSONCodec.sha256(["run": .string(producer.runId),
      "group": .string(producer.conversationId), "turn": .string(producer.turnId),
      "member": .string(producer.memberId), "source": .string(producer.sourceId),
      "evidence": .string(id), "sha256": .string(hash)])
    let artifact = AgentCollaborationResearchDraft(id: "fixture", objectId: nil, baseRevision: 0,
      kind: .artifact, title: "Synthetic frozen record", body: ["content": .string("Fixture")], parents: [])
    var revision = AgentCollaborationResearchRevision(reference: .init(objectId: String(repeating: "a", count: 64),
      revision: 1, sha256: ""), previousHash: nil, runId: producer.runId, turnId: producer.turnId,
      authorId: producer.memberId, sourceId: producer.sourceId, draft: artifact,
      frozenCloudReads: [.init(evidenceId: id, sha256: hash, totalCharacters: Int64(original.count))])
    revision.reference.sha256 = try InterimPilotArchive.digest(encoder.encode(revision))
    let milestone = "missing"
    let key = InterimPilotArchive.milestonePrefix(producer) + AgentMcpJSONCodec.sha256(["id": .string(milestone)])
    try fixture.database.transaction {
      try fixture.database.insertResearchRecord(revision, conversationId: producer.conversationId,
        key: "object:" + revision.reference.objectId, revision: 1)
      try fixture.database.insertResearchRecord(AgentCollaborationResearchPublication(requestHash: hash,
        references: [revision.reference], milestoneId: milestone, recordedAtMillis: 3),
        conversationId: producer.conversationId, key: key, revision: 0)
    }
    var archive = fixture.archive()
    XCTAssertThrowsError(try archive.capture(checkpoint, database: fixture.database))
    XCTAssertTrue(archive.entries.isEmpty)
    XCTAssertFalse(archive.mayCleanUp)
    XCTAssertFalse(try fixture.removeResearch(ifCaptured: archive))
    XCTAssertNotNil(try fixture.database.researchRecord(AgentCollaborationResearchPublication.self,
      conversationId: producer.conversationId, key: key, revision: 0))
    XCTAssertEqual(try fixture.history.recordCloudEvidence(observation)["evidence_id"], .string(id))
    try archive.capture(checkpoint, database: fixture.database)
    XCTAssertTrue(archive.mayCleanUp)
    XCTAssertEqual(archive.entries.count, 2)
    XCTAssertEqual(archive.entries[key]?.observations["cloud:" + id + ":" + hash], original)
    XCTAssertNil(try fixture.database.researchRecord(AgentCollaborationReadCoverage.self,
      conversationId: producer.conversationId, key: coverageKey, revision: 0))
    XCTAssertTrue(try fixture.removeResearch(ifCaptured: archive))
    XCTAssertNil(try fixture.database.researchRecord(AgentCollaborationResearchPublication.self,
      conversationId: producer.conversationId, key: key, revision: 0))
    XCTAssertEqual(archive.entries[key]?.observations["cloud:" + id + ":" + hash], original)
  }

  private struct Fixture {
    let root: URL
    let suite: String
    let defaults: UserDefaults
    let history: AgentTeamExecutionHistoryStore
    let database: AgentTeamHistoryDatabase
    let checkpoint = AgentTeamExecutionSnapshot(supervisorRunId: "pilot-run", teamId: "pilot-team",
      conversationId: "pilot-conversation", taskId: "pilot-turn", primaryAgentId: "coordinator", state: .running,
      members: [.init(agentId: "author", instanceId: "first-attempt", sourceMessageId: "first-source",
        dispatchCheckpoint: .accepted)], createdAtMillis: 1, updatedAtMillis: 1)

    init() throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      suite = "ios-interim-pilot-" + UUID().uuidString
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let file = root.appendingPathComponent("history.sqlite")
      let secrets = InMemorySecretStore()
      history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets, fileURL: file)
      database = try AgentTeamHistoryDatabase(fileURL: file,
        storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    }

    func archive() -> InterimPilotArchive {
      .init(conversation: checkpoint.conversationId, run: checkpoint.supervisorRunId, turn: checkpoint.taskId)
    }

    func scope(_ member: AgentTeamMemberSnapshot) -> AgentCollaborationToolEvidenceScope {
      .init(runId: checkpoint.supervisorRunId, conversationId: checkpoint.conversationId,
        turnId: checkpoint.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    }

    func publish(_ id: String, scope: AgentCollaborationToolEvidenceScope) throws {
      let raw = AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
        "summary": .string("Synthetic pilot artifact"), "workspace": .array([.object([
          "id": .string(id), "base_revision": .int(0), "kind": .string("artifact"), "title": .string(id),
          "body": .object(["content": .string("Unverified fixture")]), "parents": .array([])
        ])])])
      XCTAssertEqual(try history.publishCollaborationMilestone(["mode": .string("publish"),
        "milestone_id": .string(id), "artifact": .string(raw)], scope: scope)["status"], .string("published"))
    }

    func removeResearch(ifCaptured archive: InterimPilotArchive) throws -> Bool {
      guard archive.mayCleanUp, archive.conversation == checkpoint.conversationId,
            archive.run == checkpoint.supervisorRunId, archive.turn == checkpoint.taskId else { return false }
      try database.transaction { try database.removeResearchRecords(conversationId: checkpoint.conversationId) }
      return true
    }

    func cleanup() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }
}
