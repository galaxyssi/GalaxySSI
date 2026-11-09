import CoreGraphics
import Foundation

enum GalaxySSIHealthInstruction {
  enum Failure: Error { case sourceInUse }
  static let pageSize = 30
  static let readingLifetime: TimeInterval = 600

  enum Kind: String, Codable, CaseIterable, Identifiable {
    case medication, test, followUp, rehabilitation, lifestyle, other
    var id: Self { self }

    var fields: [Field] {
      self == .medication ? Field.allCases : [.name, .frequency, .start, .end, .details]
    }
  }

  enum Field: String, Codable, CaseIterable, Identifiable {
    case name, dose, unit, route, frequency, start, end, details
    var id: Self { self }
  }

  enum Review: String, Codable, CaseIterable, Identifiable {
    case unreviewed, transcribed, notStated
    var id: Self { self }
  }

  struct Value: Codable, Equatable {
    var text = ""
    var review = Review.unreviewed
  }

  struct Draft: Codable, Equatable {
    private(set) var kind = Kind.other
    private(set) var fields: [Field: Value] = [:]

    var reviewed: Bool {
      kind.fields.allSatisfy { field in fields[field].map { $0.review != .unreviewed } ?? false }
    }

    var eligibleForAction: Bool {
      reviewed && (kind == .medication ? kind.fields : [.name, .details]).allSatisfy {
        value($0).review == .transcribed && !value($0).text.isEmpty
      }
    }

    func value(_ field: Field) -> Value { fields[field] ?? .init() }

    mutating func changeKind(_ next: Kind) {
      guard next != kind else { return }
      kind = next
      fields = fields.filter { next.fields.contains($0.key) }.mapValues { .init(text: $0.text) }
    }

    mutating func edit(_ field: Field, text: String) {
      guard kind.fields.contains(field), value(field).text != text else { return }
      fields[field] = .init(text: String(text.prefix(1_000)))
    }

    mutating func review(_ field: Field, as state: Review) {
      guard kind.fields.contains(field) else { return }
      let text = value(field).text.trimmingCharacters(in: .whitespacesAndNewlines)
      switch state {
      case .notStated: fields[field] = .init(text: "", review: .notStated)
      case .transcribed:
        if !text.isEmpty { fields[field] = .init(text: text, review: .transcribed) }
      case .unreviewed: fields[field] = .init(text: text)
      }
    }

    func validated() throws -> Self {
      guard Set(fields.keys).isSubset(of: kind.fields) else { throw GalaxySSIHealthRecords.Failure.invalid }
      var copy = self
      for (field, value) in fields {
        let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf16.count <= 1_000, value.review != .transcribed || !text.isEmpty,
              value.review != .notStated || text.isEmpty else { throw GalaxySSIHealthRecords.Failure.invalid }
        copy.fields[field] = .init(text: text, review: value.review)
      }
      return copy
    }
  }

  enum Recognition: String, Codable { case pdfText, onDeviceOCR }

  struct ActionReference: Codable, Equatable {
    let instruction: UUID
    let revision: Int
    let visit: UUID
    let link: UUID
    let original: UUID
    let fingerprint: Data
    let page: Int
    let pageCount: Int
    let permission: UUID
    let profileEpoch: UUID?
    let assessment: String
    var invalidated = false

    func pageLabel(language: String) -> String {
      String(format: GalaxySSIHealthInstruction.text("action_source_page", "Revision %lld · page %lld of %lld", language),
        Int64(revision), Int64(page), Int64(pageCount))
    }

    func matches(_ entry: Entry) -> Bool {
      !invalidated && entry.id == instruction && entry.revision == revision && entry.visit == visit &&
        entry.source.linkID == link && entry.source.originalID == original && entry.source.fingerprint == fingerprint &&
        entry.source.page == page && entry.source.pageCount == pageCount && entry.draft.eligibleForAction
    }
  }

  struct Box: Codable, Equatable {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    init?(_ rect: CGRect?) {
      guard let rect, !rect.isEmpty, !rect.isNull,
            [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy({ $0.isFinite }) else { return nil }
      func scaled(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 1_000).rounded()) }
      left = scaled(rect.minX)
      top = scaled(rect.minY)
      right = scaled(rect.maxX)
      bottom = scaled(rect.maxY)
      guard left < right, top < bottom else { return nil }
    }
  }

  struct Line: Codable, Equatable {
    let id: Int
    let box: Box?
  }

  struct Source: Codable, Equatable {
    let linkID: UUID
    let linkRevision: Int
    let originalID: UUID
    let fingerprint: Data
    let page: Int
    let pageCount: Int
    let recognition: Recognition
    let quote: String
    let lines: [Line]

    @MainActor
    static func select(_ reading: Reading, ids: Set<Int>) throws -> Self {
      let regions = reading.result.regions.filter { ids.contains($0.id) }.sorted { $0.id < $1.id }
      let quote = regions.map(\.text).joined(separator: "\n")
      guard (1...200).contains(ids.count), regions.count == ids.count, !quote.isBlank, quote.utf16.count <= 8_000
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      return .init(linkID: reading.link.id, linkRevision: reading.link.revision, originalID: reading.link.originalID,
        fingerprint: reading.link.fingerprint, page: reading.page, pageCount: reading.link.pageCount,
        recognition: reading.result.method == .native ? .pdfText : .onDeviceOCR, quote: quote,
        lines: regions.map { .init(id: $0.id, box: Box($0.highlight)) })
    }

    func matches(_ link: GalaxySSIHealthEncounterDocument.Link) -> Bool {
      linkID == link.id && linkRevision == link.revision && originalID == link.originalID &&
        fingerprint == link.fingerprint && pageCount == link.pageCount && (1...max(1, pageCount)).contains(page) &&
        pageCount > 0 && (link.page == nil || link.page == page)
    }
  }

  struct Reading {
    let scope: GalaxySSIHealthEncounterDocument.Scope
    let link: GalaxySSIHealthEncounterDocument.Link
    let page: Int
    let result: GalaxySSIHealthPDFText.Result
    let capturedAt: Date
    let expires: Date
  }

  struct Entry: Codable, Equatable, Identifiable {
    let id: UUID
    let concern: UUID
    let visit: UUID
    let revision: Int
    let source: Source
    let draft: Draft
    let createdAt: Date
    let updatedAt: Date
  }

  struct Receipt: Codable, Equatable, Identifiable {
    let id: UUID
    let expectedConcern: Int
    let expectedEntry: Int?
    let entry: Entry
  }

  struct Ledger: Codable {
    private(set) var current: [UUID: Entry] = [:]
    private(set) var receipts: [UUID: Receipt] = [:]

    mutating func save(id: UUID, operation: UUID, scope: GalaxySSIHealthEncounterDocument.Scope, expectedEntry: Int?,
        expectedConcern: Int, source: Source, draft: Draft, now: Date) throws -> (Receipt, Bool) {
      let draft = try draft.validated()
      let concern = scope.stamp.concern, visit = scope.visit.id
      if let saved = receipts[operation] {
        guard saved.entry.id == id, saved.entry.concern == concern, saved.entry.visit == visit,
              saved.expectedConcern == expectedConcern, saved.expectedEntry == expectedEntry,
              saved.entry.source == source, saved.entry.draft == draft else { throw GalaxySSIHealthRecords.Failure.stale }
        return (saved, false)
      }
      let previous = current[id]
      guard expectedConcern == scope.stamp.revision, expectedConcern < Int.max - 1, previous?.revision == expectedEntry,
            previous.map({ $0.concern == concern && $0.visit == visit && $0.source == source }) ?? true
      else { throw GalaxySSIHealthRecords.Failure.stale }
      let updated = max(now, previous?.updatedAt ?? now)
      let entry = Entry(id: id, concern: concern, visit: visit, revision: expectedConcern + 1, source: source,
        draft: draft, createdAt: previous?.createdAt ?? now, updatedAt: updated)
      let receipt = Receipt(id: operation, expectedConcern: expectedConcern, expectedEntry: expectedEntry, entry: entry)
      current[id] = entry
      receipts[operation] = receipt
      return (receipt, true)
    }

    func uses(linkID: UUID) -> Bool { current.values.contains { $0.source.linkID == linkID } }
    func uses(originalID: UUID) -> Bool { current.values.contains { $0.source.originalID == originalID } }

    mutating func remove(concern: UUID, visit: UUID? = nil, entry: UUID? = nil) {
      func matches(_ value: Entry) -> Bool {
        value.concern == concern && (visit == nil || value.visit == visit) && (entry == nil || value.id == entry)
      }
      current = current.filter { !matches($0.value) }
      receipts = receipts.filter { !matches($0.value.entry) }
    }
  }

  struct Item: Identifiable {
    let entry: Entry
    let originalName: String?
    var id: UUID { entry.id }
    var originalAvailable: Bool { originalName != nil }
  }

  struct Page {
    let scope: GalaxySSIHealthEncounterDocument.Scope
    let items: [Item]
    let next: Int?
  }

  struct History {
    let scope: GalaxySSIHealthEncounterDocument.Scope
    let item: Item
    let receipts: [Receipt]
    let next: Int?
    let expires: Date
  }
}
