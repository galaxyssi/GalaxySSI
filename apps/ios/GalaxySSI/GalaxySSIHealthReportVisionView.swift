import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthReportVisionView: View {
  typealias Vision = GalaxySSIHealthReportVision
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.timeZone) private var zone
  let records: GalaxySSIHealthRecords
  let originals: GalaxySSIHealthOriginalStore
  let jobID: UUID
  var automaticallyPreview = false
  @State private var job: GalaxySSIHealthRecognitionJobs.Job?
  @State private var online = false
  @State private var metrics = false
  @State private var review: Review?
  @State private var activeReview: Review?
  @State private var task: Task<Void, Never>?
  @State private var run: UUID?
  @State private var failed = false
  @State private var originalAvailable = true
  @State private var previewStarted = false
  @State private var outcome: GalaxySSIHealthReportQuickImport.Outcome?
  @State private var savedRecords: [GalaxySSIHealthReading] = []
  @State private var stage: Stage?
  @State private var contextReview: GalaxySSIHealthReportBatch.Review?
  @State private var contextPrompted = false

  private enum Stage: Int, CaseIterable {
    case compressing, sending, saving
  }

  private struct Review: Identifiable {
    let id = UUID()
    let job: GalaxySSIHealthRecognitionJobs.Job
    let consent: Vision.Consent
    let target: GalaxySSIHealthReportCodex.Target
    let jpeg: Data
    let zone: String
  }
  private var accessible: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  var body: some View {
    List {
      if accessible, let job {
        Text(job.original.name)
        if let stage {
          Section {
            ProgressView(stageTitle(stage)).accessibilityIdentifier("health-report-import-stage")
            ForEach(Stage.allCases, id: \.rawValue) { step in
              HStack {
                Text(stageTitle(step)); Spacer()
                Text(step.rawValue < stage.rawValue ? q("stage_done", "Done") :
                  step == stage ? q("stage_active", "In progress") : q("stage_wait", "Waiting"))
                  .foregroundColor(.secondary)
              }
            }
            Button(t("cancel", "Cancel request"), role: .destructive) { cancel() }
          }
        } else if metrics, outcome?.pendingConfirmation == true {
          Text(q("confirmation_pending", "Recognition complete; waiting for sampling confirmation"))
          if let selection = batchSelection {
            NavigationLink(q("batch_title", "Selected health files")) {
              GalaxySSIHealthSelectedFilesView(records: records, originals: originals, selection: selection)
            }
          } else { Button(q("confirm_batch", "Confirm sampling details")) { prepareContext() } }
        } else if metrics, let outcome, outcome.skipped != nil {
          resultSummary(outcome)
          if outcome.contextConfirmed != true, outcome.deferred?.values.contains(.sampleTime) == true {
            Button(q("confirm_batch", "Confirm sampling details")) { prepareContext() }
          }
        } else if job.reportVision != nil, metrics {
          Button(q("finish", "Finish saved report import"), action: beginQuickImport)
            .disabled(!online || !metrics || !originalAvailable)
        } else {
          Toggle(t("online", "Allow confirmed online health requests"), isOn: Binding(get: { online }, set: { value in
            change { try records.setHealthOnlinePermission(value) }
          }))
          Toggle(t("metrics", "Allow health measurement processing"), isOn: Binding(get: { metrics }, set: { value in
            change { try records.setPrivacy(.overview, enabled: value) }
          }))
          if let target = coordinator.privateHealthReportCodexTarget() { Text(target.title) }
          else { Text(t("codex_unavailable", "Pair a ready Desktop with private report transcription support.")).foregroundColor(.secondary) }
          Button(t("preview", "Review image before sending"), action: prepare)
            .disabled(task != nil || !online || !metrics || coordinator.privateHealthReportCodexTarget() == nil || !Vision.eligible(job))
        }
      }
      if failed { Text(t("failed", "Nothing was confirmed. The image, permission or provider may have changed, or the reply was invalid.")).foregroundColor(.secondary) }
    }
    .navigationTitle(q("import_title", "Import report image"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      originals.releaseCompletedQuickReportOriginals()
      reload()
      if outcome?.pendingConfirmation == true, !contextPrompted { prepareContext() }
      if job?.reportVision != nil, outcome?.skipped == nil, online, metrics { beginQuickImport() }
      if automaticallyPreview, !previewStarted {
        previewStarted = true
        if job?.reportVision == nil, online, metrics { prepare() }
      }
    }
    .onDisappear { cancel(); review = nil; contextReview = nil }
    .onChange(of: scene) { phase in
      if phase == .active { reload() } else { clearSensitive() }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in clearSensitive() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      clearSensitive()
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { event in
      if event.object as? String == records.owner {
        reload()
        if let contextReview, (try? Vision.Consent(records.load())) != contextReview.consent { self.contextReview = nil }
        if let activeReview, (try? current(activeReview)) == nil { cancel() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { event in
      if event.object as? String == records.owner { cancel(); review = nil; contextReview = nil; reload() }
    }
    .sheet(item: $review) { approval in
      NavigationView {
        List {
          if let image = UIImage(data: approval.jpeg) { Image(uiImage: image).resizable().scaledToFit() }
          Text(approval.target.title)
          Text(String(format: t("bytes", "One image, %lld bytes"), Int64(approval.jpeg.count)))
          Text(q("automatic_disclosure", "Send only this image to paired Desktop Codex in a temporary read-only thread. No history, tools, search, offline queue or provider fallback. Missing sampling details are confirmed locally before saving, without resending the image. Unusable fields are skipped. Transcription is not clinician verification."))
          Button(t("send", "Send this image once")) { send(approval) }
        }
        .navigationTitle(t("preview", "Review image before sending"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel request")) { review = nil } } }
      }.navigationViewStyle(.stack)
    }
    .sheet(item: $contextReview) { selection in
      GalaxySSIHealthReportContextForm(review: selection) { input in
        guard accessible else { throw GalaxySSIHealthRecords.Failure.permission }
        _ = try records.completeReportBatch(selection, supplement: input, originals: originals, confirmed: true, zone: zone)
        originals.releaseCompletedQuickReportOriginals(); reload()
      }
    }
  }

  @ViewBuilder private func resultSummary(_ outcome: GalaxySSIHealthReportQuickImport.Outcome) -> some View {
    Section {
      Label(outcome.saved > 0 ? String(format: q("import_count", "%lld measurements imported"), Int64(outcome.saved)) :
        outcome.duplicates > 0 ? q("existing", "Measurements already recorded") : q("not_imported", "No measurements imported"),
        systemImage: outcome.saved + outcome.duplicates > 0 ? "checkmark.circle" : "exclamationmark.circle")
        .font(.headline).accessibilityIdentifier("health-report-import-summary")
      if let bytes = outcome.imageBytes, bytes > 0 {
        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).foregroundColor(.secondary)
      }
      if outcome.duplicates > 0 {
        Text(String(format: q("duplicate_count", "%lld existing measurements linked; no records overwritten"), Int64(outcome.duplicates)))
          .font(.caption).foregroundColor(.secondary)
      }
      if let skipped = outcome.skipped, skipped > 0 {
        Text(String(format: q("skipped_count", "%lld unreadable, ambiguous or undated results skipped"), Int64(skipped)))
          .font(.caption).foregroundColor(.secondary)
      }
      if outcome.partial { Text(t("partial", "Some results were omitted or unreadable.")).font(.caption).foregroundColor(.secondary) }
      deferredRows(outcome)
      Text(q("saved_unverified", "Model transcription is not clinician verification. Saved measurements can be reviewed in Health Records."))
        .font(.caption).foregroundColor(.secondary)
      ForEach(savedRecords) { reading in
        NavigationLink { GalaxySSIHealthCenterView(records: records, initialRecordID: reading.id) } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(reading.metric.title(language: language))
            Text(measurement(reading)).foregroundColor(.secondary)
            Text(reading.unit).font(.caption).foregroundColor(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder private func deferredRows(_ outcome: GalaxySSIHealthReportQuickImport.Outcome) -> some View {
    if let job, let reasons = outcome.deferred {
      ForEach(job.reportVision?.rows ?? []) { row in
        if let reason = reasons[Vision.source(row, job: job).regionIdentity] {
          VStack(alignment: .leading, spacing: 4) {
            Text(row.metric.title(language: language) + ": " + (row.values["value"] ?? "") + " " + row.unit)
            Text(GalaxySSIHealthReportBatch.deferredTitle(reason, language: language))
              .font(.caption).foregroundColor(.secondary)
          }
        }
      }
    }
  }

  private func stageTitle(_ value: Stage) -> String {
    switch value {
    case .compressing: return q("compressing", "Compressing image")
    case .sending: return q("sending", "Recognizing report")
    case .saving: return q("saving", "Saving measurements")
    }
  }

  private func measurement(_ reading: GalaxySSIHealthReading) -> String {
    let value = reading.reportedNotation ?? reading.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    if let diastolic = reading.diastolic { return value + " / " + NSDecimalNumber(decimal: diastolic).stringValue }
    return value
  }
  private func change(_ operation: () throws -> Void) {
    cancel(); review = nil
    do { try operation(); failed = false; reload() } catch { failed = true }
  }
  private func reload() {
    guard accessible else { job = nil; return }
    do {
      let archive = try records.load()
      online = archive.healthOnlinePermission != nil; metrics = archive.derivesOverview == true
      guard let current = archive.recognitionJobs?.first(where: { $0.id == jobID }) else { throw GalaxySSIHealthRecords.Failure.stale }
      let listing = try originals.list()
      originalAvailable = listing.originals.contains(current.original)
      guard originalAvailable || current.reportImportOutcome?.releaseOriginal == true else { throw GalaxySSIHealthRecords.Failure.stale }
      job = current
      outcome = metrics ? current.reportImportOutcome : nil
      let live = Dictionary(archive.current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      savedRecords = (outcome?.recordIDs ?? []).compactMap { live[$0] }
    } catch { job = nil; outcome = nil; savedRecords = []; failed = true }
  }
  private func input(_ job: GalaxySSIHealthRecognitionJobs.Job) throws -> Data {
    _ = try originals.read(job.original)
    if let revision = job.captureSource?.cropRevision {
      guard let crop = try originals.readCrop(for: job.original), crop.metadata.revision == revision else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      return crop.png
    }
    return try originals.read(job.original)
  }
  private func prepare() {
    guard accessible, task == nil else { return }
    stage = .compressing
    let token = UUID(); run = token
    task = Task {
      defer { if run == token { task = nil; run = nil; stage = nil } }
      await Task.yield()
      do {
        reload()
        guard accessible, run == token, !Task.isCancelled, let job, Vision.eligible(job),
              let target = coordinator.privateHealthReportCodexTarget() else { throw GalaxySSIHealthRecords.Failure.stale }
        let approval = Review(job: job, consent: try .init(records.load()), target: target,
          jpeg: try GalaxySSIHealthReportVisionProvider.jpeg(input(job)), zone: zone.identifier)
        try current(approval)
        review = approval; failed = false
      } catch { if run == token, !Task.isCancelled { review = nil; failed = true } }
    }
  }
  private func current(_ approval: Review) throws {
    guard accessible, !Task.isCancelled, zone.identifier == approval.zone,
          coordinator.privateHealthReportCodexTarget() == approval.target,
          try Vision.Consent(records.load()) == approval.consent,
          try records.load().recognitionJobs?.contains(approval.job) == true,
          try originals.list().originals.contains(approval.job.original),
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(approval.target.route.connector.contactId) else {
      throw GalaxySSIHealthRecords.Failure.stale
    }
    _ = try input(approval.job)
  }
  private func send(_ approval: Review) {
    guard review?.id == approval.id, task == nil else { return }
    do {
      try current(approval)
      let id = UUID(); run = id; activeReview = approval; review = nil; failed = false; stage = .sending
      task = Task {
        defer {
          if run == id { run = nil; task = nil; activeReview = nil; stage = nil }
        }
        do {
          try current(approval)
          let response = try await coordinator.transcribePrivateHealthReport(target: approval.target, jpeg: approval.jpeg,
            instructions: GalaxySSIHealthReportVisionProvider.instructions, valid: { (try? current(approval)) != nil })
          try current(approval)
          guard run == id else { throw CancellationError() }
          let result = try Vision.parse(response)
          stage = .saving
          await Task.yield()
          try current(approval)
          activeReview = nil
          outcome = try records.commitAutomaticReportVision(result, job: approval.job, consent: approval.consent,
            zone: approval.zone, imageBytes: approval.jpeg.count, originals: originals,
            holdForBatch: approval.job.reportBatchID != nil,
            active: { run == id && (try? current(approval)) != nil })
          originals.releaseCompletedQuickReportOriginals()
          reload()
          if outcome?.pendingConfirmation == true, !contextPrompted { prepareContext() }
        } catch { if run == id, !Task.isCancelled { failed = true } }
      }
    } catch { review = nil; failed = true }
  }
  private func cancel() { task?.cancel(); task = nil; run = nil; activeReview = nil; stage = nil }
  private func clearSensitive() {
    cancel(); review = nil; contextReview = nil; job = nil; outcome = nil; savedRecords = []
  }
  private func beginQuickImport() {
    guard accessible, task == nil else { return }
    let token = UUID(); run = token; stage = .saving
    task = Task {
      defer { if run == token { task = nil; run = nil; stage = nil } }
      await Task.yield()
      do {
        outcome = try records.finishAutomaticReport(job: jobID, originals: originals, active: { accessible && run == token })
        originals.releaseCompletedQuickReportOriginals()
        reload(); failed = false
        if outcome?.pendingConfirmation == true, !contextPrompted { prepareContext() }
      } catch { if run == token, !Task.isCancelled { failed = true } }
    }
  }
  private func prepareContext() {
    guard accessible, job?.reportBatchID == nil else { return }
    do {
      let selection = try records.reportBatchReview(ids: [jobID], originals: originals, zone: zone)
      contextPrompted = true
      contextReview = selection
    } catch { failed = true }
  }
  private var batchSelection: GalaxySSIHealthSelectedFiles.Selection? {
    guard let batch = job?.reportBatchID else { return nil }
    return try? GalaxySSIHealthSelectedFiles.restore(batch: batch, records: records)
  }
  private func q(_ key: String, _ fallback: String) -> String { GalaxySSIHealthReportQuickImport.text(key, fallback, language) }
  private func t(_ key: String, _ fallback: String) -> String { Vision.text(key, fallback, language) }
}
