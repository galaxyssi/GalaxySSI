import Foundation
import ImageIO

struct GalaxySSIHealthSelectedTable: Identifiable {
  let id: UUID
  let version: UUID
  let name: String
}

struct GalaxySSIHealthReportPickerApproval {
  let owner: String
  let consent: GalaxySSIHealthReportVision.Consent
  let target: GalaxySSIHealthReportCodex.Target
  let expires: Date

  func matches(owner: String, consent: GalaxySSIHealthReportVision.Consent,
      target: GalaxySSIHealthReportCodex.Target?, now: Date = Date()) -> Bool {
    self.owner == owner && self.consent == consent && self.target == target && now < expires
  }
}

enum GalaxySSIHealthSelectedFiles {
  struct Entry: Identifiable {
    var id = UUID()
    let name: String
    let kind: Kind
    enum Kind {
      case job(UUID), pdf(GalaxySSIHealthOriginalStore.Original), table(GalaxySSIHealthSelectedTable), failure
    }
  }

  struct Selection: Identifiable {
    let id: UUID
    let entries: [Entry]
    let approval: GalaxySSIHealthReportPickerApproval?
  }

  @MainActor static func restore(batch: UUID, records: GalaxySSIHealthRecords) throws -> Selection {
    let archive = try records.load()
    let jobs = (archive.recognitionJobs ?? []).filter { $0.reportBatchID == batch }.sorted {
      $0.addedAt != $1.addedAt ? $0.addedAt < $1.addedAt : $0.id.uuidString < $1.id.uuidString
    }
    var entries = jobs.map { Entry(id: $0.id, name: $0.original.name, kind: .job($0.id)) }
    entries += (archive.tableReviews ?? []).filter { $0.reportBatchID == batch }.map {
      Entry(id: $0.id, name: $0.name, kind: .table(.init(id: $0.id, version: $0.version, name: $0.name)))
    }
    guard !entries.isEmpty else { throw GalaxySSIHealthRecords.Failure.stale }
    return .init(id: batch, entries: entries, approval: nil)
  }

  @MainActor static func read(_ urls: [URL], records: GalaxySSIHealthRecords, originals: GalaxySSIHealthOriginalStore,
      retainOriginal: Bool, approval: GalaxySSIHealthReportPickerApproval?) throws -> Selection {
    var seen = Set<URL>()
    let files = urls.filter { seen.insert($0).inserted }
    guard !files.isEmpty, files.count <= GalaxySSIHealthRecognitionJobs.maximumJobs,
          originals.owner == records.owner, originals.restoreRecordsFile == records.isolatedFile else {
      throw GalaxySSIHealthRecords.Failure.limit
    }
    if let approval {
      guard approval.matches(owner: records.owner, consent: try .init(records.load()), target: approval.target) else {
        throw GalaxySSIHealthRecords.Failure.permission
      }
    }
    let batch = UUID()
    var ids = Set<UUID>()
    let entries = files.map { url -> Entry in
      let name = String(url.lastPathComponent.prefix(180))
      do {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: GalaxySSIHealthOriginalStore.maximumFileBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= GalaxySSIHealthOriginalStore.maximumFileBytes else { throw GalaxySSIHealthRecords.Failure.limit }
        let ext = url.pathExtension.lowercased()
        if ["csv", "json", "xlsx", "txt"].contains(ext) {
          guard data.count <= GalaxySSIHealthTableImport.maximumBytes else { throw GalaxySSIHealthRecords.Failure.limit }
          var worksheet: GalaxySSIHealthXLSX.Selection?
          if ext == "xlsx" {
            let workbook = try GalaxySSIHealthXLSX(data)
            guard let sheet = workbook.sheets.first, let first = try workbook.rows(sheet.id).dropLast().first else {
              throw GalaxySSIHealthRecords.Failure.invalid
            }
            let selection = GalaxySSIHealthXLSX.Selection(sheet: sheet.id, header: first.number)
            _ = try workbook.table(selection)
            worksheet = selection
          }
          else { _ = try GalaxySSIHealthTableImport.parse(data, json: ext == "json") }
          let draft = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: name, at: Date(), data: data,
            mapping: .init(), worksheet: worksheet, retainOriginal: retainOriginal, reportBatchID: batch)
          try records.saveTableReview(draft, replacing: nil)
          return .init(id: draft.id, name: name, kind: .table(.init(id: draft.id, version: draft.version, name: name)))
        }
        if data.starts(with: Data("%PDF-".utf8)) {
          let original = try originals.storeSelectedPDF(data, name: name, retainOriginal: retainOriginal)
          do {
            let count = try GalaxySSIHealthRecognitionJobs.pdfPageCount(data)
            let job = try records.enqueueRecognition(original: original, pageCount: count)
            try records.attachSelectedReportJob(job, batch: batch, modelFirst: false)
            return .init(id: job.id, name: name, kind: .job(job.id))
          } catch GalaxySSIHealthPDFText.Failure.locked { return .init(name: name, kind: .pdf(original)) }
          catch GalaxySSIHealthPDFText.Failure.extractionRestricted { return .init(name: name, kind: .pdf(original)) }
        }
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
        let job = try originals.storeReportImage(data, name: name, retainOriginal: retainOriginal,
          batchID: batch, modelFirst: approval != nil)
        return .init(id: job.id, name: name, kind: .job(job.id))
      } catch { return .init(name: name, kind: .failure) }
    }.filter { ids.insert($0.id).inserted }
    return .init(id: batch, entries: entries, approval: approval)
  }
}

extension GalaxySSIHealthRecords {
  func skipSelectedReportImage(_ expected: GalaxySSIHealthRecognitionJobs.Job) throws {
    var archive = try load()
    guard expected.reportBatchID != nil, expected.reportModelFirst == true, expected.reportVision == nil,
          expected.phase != .cancelled,
          expected.run == nil, let index = archive.recognitionJobs?.firstIndex(where: { $0 == expected }) else { throw Failure.stale }
    archive.recognitionJobs?[index].phase = .cancelled
    archive.recognitionJobs?[index].version = UUID()
    try persistQuickReport(archive)
  }

  func failSelectedReportJob(id: UUID, batch: UUID) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.reportBatchID == batch }),
          var job = archive.recognitionJobs?[index], job.run == nil, job.reportVision == nil,
          job.phase != .cancelled else { throw Failure.stale }
    job.phase = .failed; job.version = UUID(); archive.recognitionJobs?[index] = job
    try persistQuickReport(archive)
  }

  func attachSelectedReportJob(_ job: GalaxySSIHealthRecognitionJobs.Job, batch: UUID, modelFirst: Bool) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0 == job }) else { throw Failure.stale }
    archive.recognitionJobs?[index].reportBatchID = batch
    archive.recognitionJobs?[index].reportModelFirst = modelFirst
    archive.recognitionJobs?[index].version = UUID()
    try persistQuickReport(archive)
  }
}
