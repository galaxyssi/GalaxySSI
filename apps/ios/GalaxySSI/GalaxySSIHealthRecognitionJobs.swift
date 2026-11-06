import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

enum GalaxySSIHealthRecognitionJobs {
  static let maximumPages = 40
  static let maximumJobs = 16
  static let maximumTextBytes = 2 * 1024 * 1024

  enum Phase: String, Codable { case queued, running, interrupted, completed, cancelled, failed }

  struct Line: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let ordinal: Int
    let text: String
    let bounds: CGRect
  }

  struct Page: Codable, Equatable, Sendable {
    let index: Int
    let fromOCR: Bool
    let lines: [Line]
    var textBytes: Int { lines.reduce(0) { $0 + $1.text.utf8.count } }
  }

  struct Job: Codable, Identifiable, Equatable {
    var id = UUID()
    var version = UUID()
    let original: GalaxySSIHealthOriginalStore.Original
    let addedAt: Date
    let pageCount: Int
    var phase = Phase.queued
    var run: UUID?
    var pages: [Page] = []
  }

  static func validDigest(_ hash: String) -> Bool {
    hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func line(_ region: GalaxySSIHealthPDFText.Region) -> Line {
    let bounds = region.highlight ?? region.bounds
    let geometry = [bounds.minX, bounds.minY, bounds.width, bounds.height].map {
      $0.isFinite ? String(Int((min(10_000, max(-10_000, $0)) * 10_000).rounded())) : "invalid"
    }.joined(separator: ":")
    let text = String(region.text.prefix(500))
    let digest = SHA256.hash(data: Data((region.text + "\n" + geometry).utf8))
      .map { String(format: "%02x", $0) }.joined()
    return .init(id: digest, ordinal: region.id, text: text, bounds: bounds)
  }

  static func process(_ data: Data, kind: GalaxySSIHealthOriginalStore.Kind, page: Int) throws -> Page {
    let result: GalaxySSIHealthPDFText.Result
    if kind == .pdf { result = try GalaxySSIHealthPDFText.read(data, page: page) }
    else { result = try GalaxySSIHealthPDFText.readImage(data) }
    var seen = Set<String>()
    let lines = result.regions.prefix(150).map(line).filter { seen.insert($0.id).inserted }
    return Page(index: page, fromOCR: result.method == .ocr, lines: lines)
  }
}

@MainActor
struct GalaxySSIHealthRecognitionJobsView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  let store: GalaxySSIHealthOriginalStore
  @State private var jobs: [GalaxySSIHealthRecognitionJobs.Job] = []
  @State private var originals: [GalaxySSIHealthOriginalStore.Original] = []
  @State private var task: Task<Void, Never>?
  @State private var activeID: UUID?
  @State private var activeRun: UUID?
  @State private var limit = 20
  @State private var failed = false
  @State private var repairJob: GalaxySSIHealthRecognitionJobs.Job?
  @State private var selectingRepair = false
  @State private var missingSource: UUID?
  @State private var removedSources: Set<UUID> = []

  var body: some View {
    List {
      if scene == .active {
        Section(t("jobs", "Recognition jobs")) {
          ForEach(jobs) { job in
            NavigationLink {
              detail(job.id)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(job.original.name)
                Text(phase(job)).foregroundColor(.secondary)
              }
            }
          }
          if jobs.isEmpty { Text(t("empty", "No recognition jobs")).foregroundColor(.secondary) }
        }
        Section(t("originals", "Saved originals")) {
          ForEach(originals.prefix(limit)) { original in
            Button(original.name) { enqueue(original) }.disabled(task != nil)
          }
          if originals.count > limit { Button(t("more", "Show more")) { limit += 20 } }
        }
        if failed { Text(t("failed", "The original or recognition job is unavailable.")) }
      }
    }
    .navigationTitle(t("title", "Local Report Recognition"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { if task != nil { stop(cancelled: false) } }
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else if $0 == .background {
        stop(cancelled: false)
        jobs = []; originals = []; failed = false
        selectingRepair = false; repairJob = nil; missingSource = nil; removedSources = []
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.reviewInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .fileImporter(isPresented: $selectingRepair, allowedContentTypes: [.pdf, .image]) { result in
      defer { repairJob = nil }
      guard scene != .background, let job = repairJob, case .success(let file) = result else { return }
      do {
        guard try records.load().recognitionJobs?.contains(where: { $0.id == job.id && $0.version == job.version }) == true
        else { throw GalaxySSIHealthRecords.Failure.stale }
        try store.repairRecognitionOriginal(job.original, from: file)
        missingSource = nil
        reload()
      } catch { failed = true }
    }
  }

  private func detail(_ id: UUID) -> some View {
    List {
      if scene == .active, let job = jobs.first(where: { $0.id == id }) {
        Text(phase(job))
        if removedSources.contains(job.original.id) {
          Text(t("source_removed", "The original was removed.")).foregroundColor(.secondary)
        } else if missingSource == id || !originals.contains(job.original) {
          Text(t("source_missing", "The original is unavailable. Choose an identical file to restore it."))
            .foregroundColor(.secondary)
          Button(t("repair", "Choose matching original")) { repairJob = job; selectingRepair = true }
            .disabled(task != nil)
        }
        if activeID == id {
          ProgressView()
          Button(t("cancel", "Cancel recognition"), role: .destructive) { stop(cancelled: true) }
        } else if job.phase != .completed && job.phase != .cancelled {
          Button(t("resume", "Start or resume recognition")) { run(job) }
            .disabled(task != nil || missingSource == id || !originals.contains(job.original))
          Button(t("cancel", "Cancel recognition"), role: .destructive) {
            do { try records.cancelRecognitionJob(id: job.id, expected: job.version); reload() }
            catch { failed = true }
          }
        }
        ForEach(originals.contains(job.original) && missingSource != id ? job.pages : [], id: \.index) { page in
          NavigationLink {
            pageDetail(page.index, jobID: job.id)
          } label: {
            Text(String(format: t("page", "Page %lld"), Int64(page.index + 1)))
          }
        }
        if activeID != id {
          Button(t("remove", "Remove job"), role: .destructive) {
            do { try records.removeRecognitionJob(id: id, expected: job.version); reload() }
            catch { failed = true }
          }
        }
        if failed { Text(t("failed", "The original or recognition job is unavailable.")) }
      }
    }
    .navigationTitle(t("jobs", "Recognition jobs"))
  }

  private func pageDetail(_ index: Int, jobID: UUID) -> some View {
    List {
      if scene == .active, missingSource != jobID,
         let job = jobs.first(where: { $0.id == jobID }), originals.contains(job.original),
         let page = job.pages.first(where: { $0.index == index }) {
        let sourceContext = GalaxySSIHealthOCRSourceContext.inspect(page.lines.map(\.text), timeZone: timeZone)
        ForEach(page.lines) { line in
          NavigationLink {
            GalaxySSIHealthReportItemEditor(records: records, source: .init(original: job.original.id,
              sha256: job.original.sha256, page: page.index, region: line.ordinal, fromOCR: page.fromOCR,
              evidenceKey: line.id), excerpt: line.text, sourceContext: sourceContext)
          } label: { Text(line.text) }
        }
        NavigationLink {
          GalaxySSIHealthReportBatchView(records: records, store: store, original: job.original)
        } label: {
          Text(GalaxySSIHealthReportReview.text("batch", "Reviewed measurements", language: language))
        }
      }
    }
    .navigationTitle(String(format: t("page", "Page %lld"), Int64(index + 1)))
    .onAppear {
      if scene == .active, let job = jobs.first(where: { $0.id == jobID }),
         (try? store.read(job.original)) == nil { missingSource = jobID }
    }
  }

  private func enqueue(_ original: GalaxySSIHealthOriginalStore.Original) {
    guard scene == .active else { return }
    do {
      let bytes = try store.read(original)
      let count = original.kind == .pdf ? try GalaxySSIHealthPDFText.pageCount(bytes) : 1
      try records.enqueueRecognition(original: original, pageCount: count)
      reload()
    } catch { failed = true }
  }

  private func run(_ job: GalaxySSIHealthRecognitionJobs.Job) {
    guard scene == .active, task == nil else { return }
    do {
      let bytes: Data
      do { bytes = try store.read(job.original) }
      catch { missingSource = job.id; throw error }
      let run = try records.beginRecognitionJob(id: job.id, expected: job.version)
      activeID = job.id; activeRun = run
      reload()
      task = Task {
        do {
          for index in job.pages.count..<job.pageCount {
            let worker = Task.detached(priority: .userInitiated) {
              try GalaxySSIHealthRecognitionJobs.process(bytes, kind: job.original.kind, page: index)
            }
            let page = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                             onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard scene == .active, activeRun == run else { throw CancellationError() }
            guard try store.list().originals.contains(job.original) else {
              missingSource = job.id
              throw GalaxySSIHealthRecords.Failure.stale
            }
            try records.commitRecognitionPage(id: job.id, run: run, page: page)
            reload()
          }
        } catch {
          if activeRun == run {
            try? records.finishRecognitionJob(id: job.id, run: run, phase: error is CancellationError ? .interrupted : .failed)
            failed = !(error is CancellationError)
          }
        }
        if activeRun == run { activeID = nil; activeRun = nil; task = nil; reload() }
      }
    } catch { failed = true }
  }

  private func stop(cancelled: Bool) {
    if let id = activeID, let run = activeRun {
      try? records.finishRecognitionJob(id: id, run: run, phase: cancelled ? .cancelled : .interrupted)
    }
    task?.cancel(); task = nil; activeID = nil; activeRun = nil
    reload()
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      jobs = try records.load().recognitionJobs ?? []
      let listing = try store.list()
      originals = listing.originals
      removedSources = Set(listing.removed.map(\.id)).union(listing.pendingRemovals)
    } catch {
      jobs = []
      originals = []
      removedSources = []
      failed = true
    }
  }

  private func phase(_ job: GalaxySSIHealthRecognitionJobs.Job) -> String {
    if job.phase == .cancelled { return t("cancelled", "Cancelled") }
    if job.phase == .failed { return t("phase_failed", "Failed; can retry") }
    if job.phase == .interrupted || (job.phase == .running && activeID != job.id) {
      return t("interrupted", "Interrupted; can resume") + " " +
        String(format: t("progress", "%lld / %lld pages recognized"), Int64(job.pages.count), Int64(job.pageCount))
    }
    return String(format: t("progress", "%lld / %lld pages recognized"), Int64(job.pages.count), Int64(job.pageCount))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.recognition." + key, fallback: fallback, language: language)
  }
}
