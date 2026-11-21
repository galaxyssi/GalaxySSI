import Foundation

enum GalaxySSIHealthMeasurementComparison {
  enum Source: String { case manual, report, table, bluetooth, healthKit }
  static func source(_ reading: GalaxySSIHealthReading) -> Source {
    if reading.reportSource != nil { return .report }
    if reading.tableSource != nil { return .table }
    if reading.bluetoothReceipt != nil { return .bluetooth }
    if reading.healthKitSource != nil { return .healthKit }
    return .manual
  }
  static func unverifiedMethod(_ reading: GalaxySSIHealthReading) -> Bool {
    [.report, .table].contains(source(reading))
  }
  static func accepts(_ reading: GalaxySSIHealthReading, anchor: GalaxySSIHealthReading) -> Bool {
    guard reading.metric == anchor.metric, reading.unit == anchor.unit, reading.conditions == anchor.conditions,
          reading.normalizedMeasurementSide == anchor.normalizedMeasurementSide, source(reading) == source(anchor) else { return false }
    if source(anchor) == .bluetooth { return reading.bluetoothReceipt?.device == anchor.bluetoothReceipt?.device }
    if source(anchor) == .healthKit {
      return GalaxySSIHealthTrend.HealthOrigin.recorded(in: reading) == GalaxySSIHealthTrend.HealthOrigin.recorded(in: anchor)
    }
    return true
  }
  static func delta(_ before: GalaxySSIHealthReading?, _ after: GalaxySSIHealthReading?,
                    component: GalaxySSIHealthTrend.Component = .value) -> Decimal? {
    guard let before, let after, accepts(after, anchor: before), !unverifiedMethod(before),
          !before.conditions.isBlank, before.conditions != "unspecified", !before.unit.isBlank,
          before.metric != .bloodPressure || ["left", "right"].contains(before.measurementSide ?? ""),
          source(before) != .healthKit || GalaxySSIHealthTrend.HealthOrigin.recorded(in: before) != .unidentified,
          let a = component.value(in: before), let b = component.value(in: after) else { return nil }
    let result = b - a
    return result.isNaN ? nil : result
  }
}

enum GalaxySSIHealthMeasurementBatches {
  struct Group: Identifiable {
    let id: String
    let importedAt: Date
    let name: String
    let originals: [GalaxySSIHealthOriginalStore.Original]
    var tableID: UUID?
    var reportCount: Int { tableID == nil ? originals.count : 1 }
  }
  struct Snapshot {
    let latest: [GalaxySSIHealthMetric: GalaxySSIHealthReading]
    let associations: [UUID: Set<String>]
    var readings: [GalaxySSIHealthReading] { GalaxySSIHealthMetric.allCases.compactMap { latest[$0] } }
    func requiresMethodReview(_ reading: GalaxySSIHealthReading) -> Bool {
      associations[reading.id]?.isEmpty == false || GalaxySSIHealthMeasurementComparison.unverifiedMethod(reading)
    }
  }
  static func groups(_ archive: GalaxySSIHealthRecords.Archive) -> [Group] {
    let index = archive.originalIndex ?? .init()
    let originals = index.originals.values.filter { !index.removals.pending.contains($0.id) && !index.unreadableLegacy.contains($0.id) }
    let jobs = Dictionary(grouping: archive.recognitionJobs ?? [], by: { $0.original.id })
    var grouped: [String: [GalaxySSIHealthOriginalStore.Original]] = [:]
    for original in originals {
      let job = jobs[original.id]?.filter { $0.original.sha256 == original.sha256 }.min { $0.addedAt < $1.addedAt }
      let batch = job?.captureSource?.batchID ?? job?.reportBatchID
      let key = batch.map { "batch:" + $0.uuidString } ?? job.map { "job:" + $0.id.uuidString } ?? "original:" + original.id.uuidString
      grouped[key, default: []].append(original)
    }
    var result = grouped.map { key, originals in
      Group(id: key, importedAt: originals.map(\.importedAt).max() ?? .distantPast,
        name: originals.count == 1 ? originals[0].name : "", originals: originals.sorted { $0.id.uuidString < $1.id.uuidString })
    }
    result += (archive.tableBatches ?? []).filter { $0.undone == nil }.map {
      Group(id: "table:" + $0.id.uuidString, importedAt: $0.at, name: $0.name, originals: [], tableID: $0.id)
    }
    return result.sorted { ($0.importedAt, $0.id) > ($1.importedAt, $1.id) }
  }

  static func snapshot(_ group: Group, archive: GalaxySSIHealthRecords.Archive, report: UUID? = nil,
                       now: Date) throws -> Snapshot {
    guard let currentGroup = groups(archive).first(where: { $0.id == group.id }),
          currentGroup.originals == group.originals, currentGroup.tableID == group.tableID else {
      throw GalaxySSIHealthRecords.Failure.stale
    }
    if let report, !currentGroup.originals.contains(where: { $0.id == report }) { throw GalaxySSIHealthRecords.Failure.stale }
    let current = archive.current
    var candidates: [GalaxySSIHealthReading] = []
    var associations: [UUID: Set<String>] = [:]
    for original in currentGroup.originals where report == nil || report == original.id {
      let linked = GalaxySSIHealthReportReview.linked(original: original, revisions: current,
        current: current, evidence: archive.reportEvidence ?? []).map(\.reading)
      candidates += linked
      for reading in linked { associations[reading.id, default: []].insert("report:" + original.id.uuidString) }
    }
    if let tableID = currentGroup.tableID,
       let table = archive.tableBatches?.first(where: { $0.id == tableID && $0.undone == nil }) {
      guard let original = GalaxySSIHealthTableImport.Batch.original(for: table.id, in: archive.tableBatches ?? []) else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      let authenticated = GalaxySSIHealthTableImport.Batch(id: table.id, name: table.name, at: table.at, data: original.data,
        inserted: table.inserted, undone: table.undone, linked: table.linked, sourceDigest: table.sourceDigest)
      let linked = GalaxySSIHealthTableImport.linkedReadings(batch: authenticated, revisions: current,
        current: current, evidence: archive.tableEvidence ?? []).map(\.reading)
      candidates += linked
      for reading in linked { associations[reading.id, default: []].insert("table:" + table.id.uuidString) }
    }
    var latest: [GalaxySSIHealthMetric: GalaxySSIHealthReading] = [:]
    for reading in candidates where reading.isValid && !reading.deleted && reading.measuredAt <= now {
      if let old = latest[reading.metric], (old.measuredAt, old.id.uuidString) >= (reading.measuredAt, reading.id.uuidString) { continue }
      latest[reading.metric] = reading
    }
    return Snapshot(latest: latest, associations: associations)
  }
}
