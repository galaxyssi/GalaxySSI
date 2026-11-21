import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthSelectedFilesView: View {
  typealias Files = GalaxySSIHealthSelectedFiles
  @EnvironmentObject private var app: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.timeZone) private var zone
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let originals: GalaxySSIHealthOriginalStore
  let selection: Files.Selection
  @State private var jobs: [UUID: GalaxySSIHealthRecognitionJobs.Job] = [:]
  @State private var failures: Set<UUID> = []
  @State private var approval: GalaxySSIHealthReportPickerApproval?
  @State private var pendingApproval: GalaxySSIHealthReportPickerApproval?
  @State private var authorizing = false
  @State private var task: Task<Void, Never>?
  @State private var token: UUID?
  @State private var activeID: UUID?
  @State private var stage = ""
  @State private var contextReview: GalaxySSIHealthReportBatch.Review?
  @State private var prompted = false
  @State private var entered = false
  @State private var unavailable = false
  @State private var metrics = false

  private var accessible: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && app.profile.identityFingerprint == records.owner
  }

  var body: some View {
    List {
      if accessible {
        Section {
          Text(String(format: t("batch_count", "%lld / %lld files ready"), Int64(readyCount), Int64(selection.entries.count)))
            .font(.headline).accessibilityIdentifier("health-import-batch-count")
          if task != nil {
            ProgressView(stage)
            Button(t("cancel", "Cancel"), role: .destructive) { stop(); approval = nil }
          } else if waitingModelImages {
            Button(t("resume_selected", "Recognize remaining selected images")) { requestApproval() }
          } else if !failures.isEmpty || unfinishedLocalJobs {
            Button(t("retry_files", "Retry local files")) { failures = []; start() }
          }
          if task == nil, !pendingIDs.isEmpty, !hasUnrecognizedModelImages {
            Button(t("confirm_batch", "Confirm sampling details")) { prepareContext(force: true) }
          }
          if unavailable { Text(t("batch_unavailable", "The selection, source, permissions or destination changed. Reopen or select the files again.")) }
        }
        ForEach(selection.entries) { entry in
          Section(entry.name) {
            if failures.contains(entry.id) {
              Text(t("file_failed", "Could not process this file. Other files are unchanged.")).foregroundColor(.secondary)
            }
            row(entry)
          }
        }
      }
    }
    .navigationTitle(t("batch_title", "Selected health files"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      reload()
      if !entered { entered = true; approval = selection.approval; start() }
    }
    .onDisappear { stop(); approval = nil; contextReview = nil; jobs = [:] }
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { stop(); approval = nil; pendingApproval = nil; contextReview = nil; jobs = [:] }
    }
    .onChange(of: zone) { _ in stop(); approval = nil; contextReview = nil; reload() }
    .onChange(of: app.profile.identityFingerprint) { _ in stop(); approval = nil; contextReview = nil; jobs = [:] }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      stop(); approval = nil; pendingApproval = nil; contextReview = nil; jobs = [:]
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner {
        reload()
        if let contextReview,
           (try? GalaxySSIHealthReportVision.Consent(records.load())) != contextReview.consent { self.contextReview = nil }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) {
      if $0.object as? String == records.owner { stop(); approval = nil; contextReview = nil; reload() }
    }
    .confirmationDialog(t("resume_selected", "Recognize remaining selected images"), isPresented: $authorizing, titleVisibility: .visible) {
      Button(t("resume_selected", "Recognize remaining selected images")) {
        approval = pendingApproval; pendingApproval = nil; failures = []; start()
      }
      Button(t("cancel", "Cancel"), role: .cancel) { pendingApproval = nil }
    } message: {
      Text((pendingApproval?.target.title ?? "") + "\n" + t("batch_disclosure", "Send only the remaining selected report images to paired Desktop Codex. Each is limited to 100 KB. No history, tools, offline queue or provider fallback. Sampling confirmation is local and does not resend images."))
    }
    .sheet(item: $contextReview) { review in
      GalaxySSIHealthReportContextForm(review: review) { input in
        guard accessible else { throw GalaxySSIHealthRecords.Failure.permission }
        _ = try records.completeReportBatch(review, supplement: input, originals: originals, confirmed: true, zone: zone)
        originals.releaseCompletedQuickReportOriginals(); reload()
      }
    }
  }

  @ViewBuilder private func row(_ entry: Files.Entry) -> some View {
    switch entry.kind {
    case .failure: Text(t("file_failed", "Could not process this file. Other files are unchanged.")).foregroundColor(.secondary)
    case .table(let input):
      NavigationLink(t("table_ready", "Table ready for local mapping and review")) {
        GalaxySSIHealthTableImportView(records: records, resumeReviewID: input.id, resumeReviewVersion: input.version)
      }.disabled(task != nil)
    case .pdf(let original):
      NavigationLink(t("pdf_unlock", "Open PDF and unlock locally")) {
        GalaxySSIHealthPDFTextView(store: originals, initialOriginal: original, reviewRecords: records)
      }.disabled(task != nil)
    case .job(let id):
      if let job = jobs[id] {
        if job.phase == .cancelled { Text(t("file_skipped", "File skipped")).foregroundColor(.secondary) }
        else if activeID == id { Text(stage).foregroundColor(.secondary) }
        else if job.reportImportOutcome?.pendingConfirmation == true {
          Text(t("confirmation_pending", "Recognition complete; waiting for sampling confirmation")).foregroundColor(.secondary)
          if metrics {
            ForEach(job.reportVision?.rows ?? []) { item in
              Text(item.metric.title(language: language) + ": " + (item.values["value"] ?? "") + " " + item.unit).font(.caption)
            }
          }
        } else if job.reportVision != nil {
          NavigationLink(t("view_import", "View import result")) {
            GalaxySSIHealthReportVisionView(records: records, originals: originals, jobID: id)
          }.disabled(task != nil)
        } else if job.original.kind == .pdf {
          NavigationLink(t("local_ready", "Review local recognition")) {
            GalaxySSIHealthPDFTextView(store: originals, initialOriginal: job.original, reviewRecords: records)
          }.disabled(task != nil)
        } else if job.reportModelFirst == true {
          Text(t("interrupted", "Waiting for authorization to recognize this image")).foregroundColor(.secondary)
          if task == nil {
            Button(t("skip_image", "Skip this image"), role: .destructive) {
              do {
                try records.skipSelectedReportImage(job); reload()
                if !hasUnrecognizedModelImages { prepareContext(force: false) }
              } catch { unavailable = true }
            }
          }
        } else {
          NavigationLink(t("local_ready", "Review local recognition")) {
            GalaxySSIHealthRecognitionJobsView(records: records, store: originals, initialLocalReview: id)
          }.disabled(task != nil)
        }
      } else { Text(t("file_failed", "Could not process this file. Other files are unchanged.")) }
    }
  }

  private var hasUnrecognizedModelImages: Bool {
    jobs.values.contains { $0.reportModelFirst == true && $0.reportVision == nil &&
      ![.failed, .cancelled].contains($0.phase) && !failures.contains($0.id) }
  }

  private var waitingModelImages: Bool {
    jobs.values.contains { $0.reportModelFirst == true && $0.reportVision == nil && $0.phase != .cancelled }
  }

  private var unfinishedLocalJobs: Bool {
    jobs.values.contains { $0.reportModelFirst != true && ![.completed, .cancelled].contains($0.phase) }
  }

  private var pendingIDs: [UUID] {
    selection.entries.compactMap {
      guard case .job(let id) = $0.kind, jobs[id]?.reportImportOutcome?.pendingConfirmation == true else { return nil }
      return id
    }
  }

  private var readyCount: Int {
    selection.entries.filter {
      if failures.contains($0.id) { return true }
      if case .job(let id) = $0.kind {
        return jobs[id]?.reportVision != nil || (jobs[id]?.reportModelFirst != true && jobs[id]?.phase == .completed) ||
          jobs[id]?.phase == .cancelled || jobs[id]?.phase == .failed
      }
      return true
    }.count
  }

  private func reload() {
    guard accessible else { jobs = [:]; return }
    do {
      let archive = try records.load()
      metrics = archive.derivesOverview == true
      let ids = Set(selection.entries.compactMap { entry -> UUID? in if case .job(let id) = entry.kind { return id }; return nil })
      jobs = Dictionary((archive.recognitionJobs ?? []).filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      if archive.derivesOverview != true { contextReview = nil }
    } catch { jobs = [:]; unavailable = true }
  }

  private func requestApproval() {
    guard accessible, let consent = try? GalaxySSIHealthReportVision.Consent(records.load()),
          let target = coordinator.privateHealthReportCodexTarget() else { unavailable = true; return }
    pendingApproval = .init(owner: records.owner, consent: consent, target: target, expires: Date().addingTimeInterval(1800))
    authorizing = true
  }

  private func valid(_ approved: GalaxySSIHealthReportPickerApproval, job: GalaxySSIHealthRecognitionJobs.Job,
      requestZone: String, run: UUID) -> Bool {
    guard accessible, !Task.isCancelled, token == run, requestZone == zone.identifier,
          let archive = try? records.load(), let consent = try? GalaxySSIHealthReportVision.Consent(archive),
          approved.matches(owner: records.owner, consent: consent, target: coordinator.privateHealthReportCodexTarget()),
          archive.recognitionJobs?.contains(job) == true, job.reportBatchID == selection.id,
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(approved.target.route.connector.contactId),
          (try? originals.read(job.original)) != nil else { return false }
    if let revision = job.captureSource?.cropRevision { return (try? originals.readCrop(for: job.original)?.metadata.revision) == revision }
    return true
  }

  private func start() {
    guard accessible, task == nil else { return }
    let run = UUID(); token = run; unavailable = false
    task = Task {
      defer { if token == run { token = nil; task = nil; activeID = nil; stage = "" } }
      do { try records.reconcileAbandonedRecognitionJobs() }
      catch { unavailable = true; return }
      for entry in selection.entries {
        guard accessible, token == run, !Task.isCancelled else { return }
        guard case .job(let id) = entry.kind else { continue }
        do {
          guard let current = try records.load().recognitionJobs?.first(where: { $0.id == id }) else { throw GalaxySSIHealthRecords.Failure.stale }
          if current.reportVision != nil || current.phase == .cancelled { continue }
          if current.reportModelFirst == true && approval == nil { continue }
          activeID = id; stage = t("preparing_file", "Preparing file")
          if current.phase != .completed && current.pages.count < current.pageCount { try await recognizeLocal(current, run: run) }
          if current.reportModelFirst == true, let approved = approval {
            guard let job = try records.load().recognitionJobs?.first(where: { $0.id == id }) else { throw GalaxySSIHealthRecords.Failure.stale }
            let requestZone = zone.identifier
            guard valid(approved, job: job, requestZone: requestZone, run: run) else { throw GalaxySSIHealthRecords.Failure.stale }
            stage = t("compressing", "Compressing image"); await Task.yield()
            let bytes: Data
            if job.captureSource?.cropRevision != nil, let crop = try originals.readCrop(for: job.original) { bytes = crop.png }
            else { bytes = try originals.read(job.original) }
            let jpeg = try GalaxySSIHealthReportVisionProvider.jpeg(bytes)
            guard valid(approved, job: job, requestZone: requestZone, run: run) else { throw GalaxySSIHealthRecords.Failure.stale }
            stage = t("sending", "Recognizing report")
            let response = try await coordinator.transcribePrivateHealthReport(target: approved.target, jpeg: jpeg,
              instructions: GalaxySSIHealthReportVisionProvider.instructions,
              valid: { valid(approved, job: job, requestZone: requestZone, run: run) })
            guard valid(approved, job: job, requestZone: requestZone, run: run) else { throw GalaxySSIHealthRecords.Failure.stale }
            stage = t("holding", "Holding results for batch confirmation")
            _ = try records.commitAutomaticReportVision(GalaxySSIHealthReportVision.parse(response), job: job,
              consent: approved.consent, zone: requestZone, imageBytes: jpeg.count, originals: originals, holdForBatch: true,
              active: { valid(approved, job: job, requestZone: requestZone, run: run) })
          }
        } catch {
          if Task.isCancelled || token != run { return }
          try? records.failSelectedReportJob(id: id, batch: selection.id)
          failures.insert(id)
        }
        reload()
      }
      activeID = nil
      reload()
      if !hasUnrecognizedModelImages { prepareContext(force: false) }
    }
  }

  private func recognizeLocal(_ job: GalaxySSIHealthRecognitionJobs.Job, run: UUID) async throws {
    let data = try originals.read(job.original)
    let recognition = try records.beginRecognitionJob(id: job.id, expected: job.version)
    do {
      for index in job.pages.count..<job.pageCount {
        guard accessible, token == run, !Task.isCancelled else { throw CancellationError() }
        let page: GalaxySSIHealthRecognitionJobs.Page
        if job.reportModelFirst == true { page = .init(index: index, fromOCR: false, lines: []) }
        else {
          let worker = Task.detached(priority: .userInitiated) {
            try GalaxySSIHealthRecognitionJobs.process(data, kind: job.original.kind, page: index)
          }
          page = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        }
        guard accessible, token == run, !Task.isCancelled, (try? originals.read(job.original)) != nil else { throw CancellationError() }
        try records.commitRecognitionPage(id: job.id, run: recognition, page: page)
      }
    } catch {
      try? records.finishRecognitionJob(id: job.id, run: recognition, phase: error is CancellationError ? .interrupted : .failed)
      throw error
    }
  }

  private func prepareContext(force: Bool) {
    guard accessible, !pendingIDs.isEmpty, force || !prompted else { return }
    do {
      let review = try records.reportBatchReview(ids: pendingIDs, originals: originals, zone: zone)
      prompted = true
      if review.scope.needed || force { contextReview = review }
      else {
        _ = try records.completeReportBatch(review, supplement: .init(), originals: originals, confirmed: true, zone: zone)
        originals.releaseCompletedQuickReportOriginals(); reload()
      }
    } catch { unavailable = true }
  }

  private func stop() { task?.cancel(); task = nil; token = nil; activeID = nil; stage = "" }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthReportQuickImport.text(key, fallback, language) }
}
