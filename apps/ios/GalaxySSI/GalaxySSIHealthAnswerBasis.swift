import Foundation

enum GalaxySSIHealthAnswerBasis {
  enum Kind: String, Codable { case measurement, context, profile, guideline, target, retrieved }
  struct File: Codable, Equatable {
    let id: UUID
    let sha256: String
  }
  struct Source: Codable, Equatable, Identifiable {
    let kind: Kind
    var at: Date?
    var title = ""
    var metric: GalaxySSIHealthMetric?
    var record: GalaxySSIHealthCare.Record?
    var files: [File] = []
    var id: String { kind.rawValue + ":" + (record.map { "\($0.id):\($0.revision)" } ?? title) }
  }
  struct Grant: Codable, Equatable {
    let binding: GalaxySSIHealthCareEvidence.Binding
    let conversation: String
    let metric: GalaxySSIHealthMetric
    let reviewedAt: Date
    let profileScope: GalaxySSIHealthCareProfileScope.Link?
    let profileEpoch: UUID?
    let related: GalaxySSIHealthCareRelatedContext.Scope
    let researchAuthorization: UUID?
    var sources: [Source]
    var until: Date { reviewedAt.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime) }
  }
  struct Display: Equatable {
    let sources: [Source]
    let until: Date
  }

  // Called only after beginLocalCareDiscussionTurn has validated the exact approved payload.
  @MainActor
  static func capture(_ approval: GalaxySSIHealthCareDiscussion.Approval, concern: GalaxySSIHealthCare.Concern,
                      thread: GalaxySSIHealthCareDiscussion.Thread, archive: GalaxySSIHealthRecords.Archive) -> Grant? {
    guard let conversation = thread.agentConversationID, !conversation.isBlank else { return nil }
    var sources: [Source] = []
    func measurement(_ record: GalaxySSIHealthCare.Record?, metric: GalaxySSIHealthMetric, at: Date?) {
      guard let record, record.revision > 0, let at, at.timeIntervalSince1970 > 0,
            !sources.contains(where: { $0.record == record }) else { return }
      let reading = archive.current.first { $0.id == record.id && $0.revision == record.revision &&
        $0.metric == metric && $0.measuredAt == at && !$0.deleted }
      var files: [File] = []
      if let reading {
        let links = (reading.reportSource.map { [$0] } ?? []) + (archive.reportEvidence ?? []).filter {
          $0.target.record == record.id && $0.target.revision == record.revision
        }.map(\.source)
        for link in links where files.count < 8 && !files.contains(where: { $0.id == link.original && $0.sha256 == link.sha256 }) {
          files.append(.init(id: link.original, sha256: link.sha256))
        }
      }
      sources.append(.init(kind: .measurement, at: at, metric: metric, record: record, files: files))
    }
    measurement(concern.assessment.record, metric: approval.metric, at: concern.assessment.measuredAt)
    if let comparison = concern.comparison, comparison.after.record == concern.assessment.record,
       comparison.kind != .recordCorrection {
      measurement(comparison.before.record, metric: approval.metric, at: comparison.before.measuredAt)
    }
    if let page = approval.history?.recent.payload {
      for row in (page["samples"]?.arrayValue ?? []).prefix(30) {
        guard let row = row.objectValue, case .string(let rawID)? = row["record_id"],
              let id = UUID(uuidString: rawID), case .int(let rawRevision)? = row["revision"],
              let revision = Int(exactly: rawRevision), case .int(let time)? = row["measured_at_unix_ms"] else { continue }
        // Resolve only the exact approved history row; no whole-profile projection.
        if let reading = archive.current.first(where: { $0.id == id && $0.revision == revision && $0.metric == approval.metric }),
           Int64(exactly: (reading.measuredAt.timeIntervalSince1970 * 1_000).rounded(.down)) == time {
          measurement(.init(reading), metric: approval.metric, at: reading.measuredAt)
        }
      }
    }
    for row in (approval.relatedPayload["selected"]?.arrayValue ?? []).prefix(GalaxySSIHealthMetric.allCases.count) {
      guard let row = row.objectValue, row["available"] == .bool(true),
            case .string(let name)? = row["metric"], let metric = GalaxySSIHealthMetric(rawValue: name),
            approval.relatedMeasurements[name] != nil,
            let record = row["record"]?.objectValue, case .string(let rawID)? = record["record_id"],
            let id = UUID(uuidString: rawID), case .int(let rawRevision)? = record["revision"],
            let revision = Int(exactly: rawRevision),
            let reading = archive.current.first(where: { $0.id == id && $0.revision == revision && $0.metric == metric })
      else { continue }
      measurement(.init(reading), metric: metric, at: reading.measuredAt)
    }
    if let context = concern.context, context.record == concern.assessment.record,
       let at = context.confirmedAt, at.timeIntervalSince1970 > 0 {
      sources.append(.init(kind: .context, at: at))
    }
    if approval.profileScope != nil,
       let payload = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(approval.payload.utf8)),
       let profile = payload["saved_profile"]?.objectValue,
       profile["fields"]?.objectValue?.values.contains(where: { $0.objectValue?["state"] == .string("known") }) == true ||
        !(profile["entries"]?.arrayValue ?? []).isEmpty {
      sources.append(.init(kind: .profile))
    }
    if let title = concern.assessment.guidelineVersion, !title.isBlank {
      sources.append(.init(kind: .guideline, title: String(title.prefix(256))))
    }
    if let target = concern.target { sources.append(.init(kind: .target, at: target.confirmedAt)) }
    return Grant(binding: .init(approval), conversation: conversation, metric: approval.metric,
      reviewedAt: approval.reviewedAt, profileScope: approval.profileScope, profileEpoch: approval.profileScopeEpoch,
      related: approval.relatedMeasurements, researchAuthorization: approval.research?.authorization, sources: sources)
  }

  static func retrieved(_ receipts: [GalaxySSIHealthCareEvidence.Receipt], grant: Grant, now: Date) -> [Source] {
    var latest: [URL: GalaxySSIHealthCareEvidence.Receipt] = [:]
    for receipt in receipts.prefix(3) where receipt.binding == grant.binding &&
      grant.reviewedAt <= receipt.retrievedAt && receipt.retrievedAt <= receipt.observedAt && receipt.observedAt <= now &&
      GalaxySSIHealthCareEvidence.PublicSource.allCases.contains(where: { $0.url == receipt.url }) &&
      !receipt.title.isBlank && receipt.title.utf8.count <= 1_024 &&
      (100...8_000).contains(receipt.excerpt.count) &&
      (receipt.excerptByteLimit == nil || receipt.excerptByteLimit == GalaxySSIHealthCareEvidence.maximumModelExcerptBytes) &&
      receipt.contentHash.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil {
      if latest[receipt.url].map({ $0.retrievedAt >= receipt.retrievedAt }) != true { latest[receipt.url] = receipt }
    }
    return latest.keys.sorted { $0.absoluteString < $1.absoluteString }.compactMap { url in
      latest[url].map { .init(kind: .retrieved, at: $0.retrievedAt,
        title: String($0.title.prefix(180)) + " · " + String((url.host ?? "").prefix(64))) }
    }
  }
}
