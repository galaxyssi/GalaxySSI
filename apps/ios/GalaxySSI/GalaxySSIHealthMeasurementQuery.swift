import Foundation
import SwiftUI
import UIKit

// Owns immutable value snapshots only; no store, Keychain client or UI object crosses the worker boundary.
struct GalaxySSIHealthMeasurementInput: @unchecked Sendable {
  let readings: [GalaxySSIHealthReading]
  private let index: GalaxySSIHealthOriginalStore.Index?
  private let reportLinks: [GalaxySSIHealthReportReview.Evidence]
  private let tableLinks: [GalaxySSIHealthTableImport.Evidence]
  private let tables: [GalaxySSIHealthTableImport.Batch]
  let allowed: Bool
  private let consentEvent: UUID?

  init(_ archive: GalaxySSIHealthRecords.Archive) {
    readings = archive.current; index = archive.originalIndex
    reportLinks = archive.reportEvidence ?? []; tableLinks = archive.tableEvidence ?? []
    tables = archive.tableBatches ?? []; allowed = archive.derivesOverview == true
    consentEvent = archive.privacyEvents?.last?.id
  }
  func matches(_ archive: GalaxySSIHealthRecords.Archive) -> Bool {
    let freshTables = archive.tableBatches ?? []
    return readings == archive.current && index == archive.originalIndex &&
      reportLinks == (archive.reportEvidence ?? []) && tableLinks == (archive.tableEvidence ?? []) &&
      allowed == (archive.derivesOverview == true) && consentEvent == archive.privacyEvents?.last?.id &&
      tables.count == freshTables.count && zip(tables, freshTables).allSatisfy { pair in
        let (old, new) = pair
        return old.id == new.id && old.undone == new.undone && old.sourceDigest == new.sourceDigest && old.data == new.data
      }
  }
  func unverifiedSources() throws -> Set<UUID> {
    var result = Set(readings.filter(GalaxySSIHealthMeasurementComparison.unverifiedMethod).map(\.id))
    let current = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0.revision) })
    let removed = (index?.removals.pending ?? []).union(index?.unreadableLegacy ?? [])
    for link in reportLinks {
      try Task.checkCancellation()
      guard current[link.target.record] == link.target.revision, !removed.contains(link.source.original),
            index?.originals[link.source.original]?.sha256 == link.source.sha256 else { continue }
      result.insert(link.target.record)
    }
    var digests: [UUID: String] = [:]
    let referenced = Set(tableLinks.map { $0.source.batch })
    for table in tables where table.undone == nil && referenced.contains(table.id) {
      try Task.checkCancellation()
      if let original = GalaxySSIHealthTableImport.Batch.original(for: table.id, in: tables) {
        digests[table.id] = GalaxySSIHealthTableImport.digest(original.data)
      }
    }
    for link in tableLinks {
      try Task.checkCancellation()
      if current[link.target.record] == link.target.revision && digests[link.source.batch] == link.source.sha256 {
        result.insert(link.target.record)
      }
    }
    return result
  }
}

@MainActor
final class GalaxySSIHealthMeasurementQuery: ObservableObject {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  typealias Model = GalaxySSIHealthMeasurementPeriods
  enum Scope: Hashable {
    case overview(period: Period?, abnormal: Bool, after: Model.Cursor?, expanded: Bool, outsideIDs: Set<UUID>)
    case comparison(kind: Period.Kind, first: Period?, second: Period?)
    case picker(kind: Period.Kind, before: String?)
    var requiresPermission: Bool {
      if case .overview(let period, let abnormal, _, _, _) = self { return period != nil || abnormal }
      return true
    }
  }
  // The worker result, like its input, contains only immutable value data.
  struct Output: @unchecked Sendable {
    var first: Model.Summary? = nil
    var second: Model.Summary? = nil
    var periods: Model.PeriodPage? = nil
    var records: Model.RecordPage? = nil
  }
  enum Failure { case permission, changed, unavailable }
  @Published private(set) var output: Output?
  @Published private(set) var failure: Failure?
  private var task: Task<Void, Never>?
  private var worker: Task<Output, Error>?
  private var token = UUID()
  private var lastInput: GalaxySSIHealthMeasurementInput?
  private var lastScope: Scope?
  private var lastOwner: String?

  func load(records: GalaxySSIHealthRecords, scope: Scope, zone: TimeZone, preservingOutput: Bool = false,
            ownerMatches: @escaping @MainActor () -> Bool) {
    cancel(clear: false)
    failure = nil
    guard ownerMatches(), UIApplication.shared.isProtectedDataAvailable else { cancel(); return }
    do {
      let archive = try records.load()
      if scope.requiresPermission && archive.derivesOverview != true { cancel(); failure = .permission; return }
      if !preservingOutput || records.owner != lastOwner || scope != lastScope || lastInput?.matches(archive) != true { output = nil }
      let input = GalaxySSIHealthMeasurementInput(archive), now = Date(), request = token
      lastInput = input; lastScope = scope; lastOwner = records.owner
      let work = Task.detached(priority: .userInitiated) { try Self.run(input, scope: scope, now: now, zone: zone) }
      worker = work
      task = Task { @MainActor in
        do {
          let value = try await work.value
          guard !Task.isCancelled, request == token, ownerMatches(),
                UIApplication.shared.applicationState == .active, UIApplication.shared.isProtectedDataAvailable else { return }
          let fresh = try records.load()
          guard input.matches(fresh) else {
            output = nil; failure = fresh.derivesOverview == true || !scope.requiresPermission ? .changed : .permission
            return
          }
          output = value
        } catch is CancellationError { }
        catch {
          guard !Task.isCancelled, request == token, ownerMatches() else { return }
          output = nil; failure = .unavailable
        }
      }
    } catch { output = nil; failure = .unavailable }
  }
  func cancel(clear: Bool = true) {
    token = UUID(); task?.cancel(); worker?.cancel(); task = nil; worker = nil
    if clear { output = nil; failure = nil; lastInput = nil; lastScope = nil; lastOwner = nil }
  }
  func isCurrent(records: GalaxySSIHealthRecords) -> Bool {
    guard lastOwner == records.owner, output != nil, failure == nil, let archive = try? records.load(),
          lastScope?.requiresPermission != true || archive.derivesOverview == true else { return false }
    return lastInput?.matches(archive) == true
  }
  func hasScope(_ scope: Scope) -> Bool { lastScope == scope }
  func adopt(_ other: GalaxySSIHealthMeasurementQuery, records: GalaxySSIHealthRecords) -> Bool {
    guard other.isCurrent(records: records) else { return false }
    let value = other.output, input = other.lastInput, scope = other.lastScope
    cancel()
    lastInput = input; lastScope = scope; lastOwner = records.owner; output = value
    return true
  }
  nonisolated static func run(_ input: GalaxySSIHealthMeasurementInput, scope: Scope,
                             now: Date, zone: TimeZone) throws -> Output {
    try Task.checkCancellation()
    if scope.requiresPermission && !input.allowed { throw GalaxySSIHealthRecords.Failure.permission }
    switch scope {
    case .picker(let kind, let before):
      return Output(periods: try Model.page(input.readings, kind: kind, now: now, zone: zone, before: before))
    case .comparison(let kind, let a, let b):
      let first = try a ?? Model.page(input.readings, kind: kind, now: now, zone: zone).periods.first
      guard first?.kind == kind || first == nil, b?.kind == kind || b == nil else { throw GalaxySSIHealthRecords.Failure.invalid }
      let second = b ?? (try? first?.previous())
      let unverified = try input.unverifiedSources()
      return Output(first: try first.map { try Model.summary(input.readings, period: $0, now: now, zone: zone, unverified: unverified) },
        second: try second.map { try Model.summary(input.readings, period: $0, now: now, zone: zone, unverified: unverified) })
    case .overview(let period, let abnormal, let after, let expanded, let outsideIDs):
      let unverified = input.allowed ? try input.unverifiedSources() : []
      return Output(first: try Model.summary(input.readings, period: period, now: now, zone: zone, unverified: unverified,
        compareRanges: input.allowed), records: expanded ? try Model.records(input.readings, period: period, now: now,
          zone: zone, after: after, abnormal: abnormal, outsideIDs: outsideIDs) : nil)
    }
  }
}
