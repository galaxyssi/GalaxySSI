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
  @State private var job: GalaxySSIHealthRecognitionJobs.Job?
  @State private var online = false
  @State private var images = false
  @State private var metrics = false
  @State private var review: Review?
  @State private var activeReview: Review?
  @State private var task: Task<Void, Never>?
  @State private var run: UUID?
  @State private var failed = false
  @State private var originalPreview: UIImage?

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
        if let originalPreview { Image(uiImage: originalPreview).resizable().scaledToFit() }
        if let result = job.reportVision {
          Text(t("unverified", "Model transcription is unverified. Check every field against the original.")).foregroundColor(.secondary)
          if result.partial { Text(t("partial", "Some results were omitted or unreadable.")).foregroundColor(.secondary) }
          ForEach(result.rows) { row in
            NavigationLink {
              GalaxySSIHealthReportItemEditor(records: records, source: Vision.source(row, job: job), excerpt: row.source,
                sourceContext: sourceContext(result), modelPrefill: row, modelSourceIsAvailable: {
                  accessible && (try? input(job)) != nil
                })
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(row.metric.title(language: language))
                Text((row.values["value"] ?? "") + " " + row.unit).foregroundColor(.secondary)
              }
            }
          }
          NavigationLink {
            GalaxySSIHealthReportBatchView(records: records, store: originals, original: job.original)
          } label: { Text(GalaxySSIHealthReportReview.text("batch", "Reviewed measurements", language: language)) }
        } else {
          Toggle(t("online", "Allow confirmed online health requests"), isOn: Binding(get: { online }, set: { value in
            change { try records.setHealthOnlinePermission(value) }
          }))
          Toggle(t("permission", "Allow report images in explicitly confirmed online requests"), isOn: Binding(get: { images }, set: { value in
            change { try records.setPrivacy(.reportImages, enabled: value) }
          }))
          Toggle(t("metrics", "Allow health measurement processing"), isOn: Binding(get: { metrics }, set: { value in
            change { try records.setPrivacy(.overview, enabled: value) }
          }))
          if let target = coordinator.privateHealthReportCodexTarget() { Text(target.title) }
          else { Text(t("codex_unavailable", "Pair a ready Desktop with private report transcription support.")).foregroundColor(.secondary) }
          Button(t("preview", "Review image before sending"), action: prepare)
            .disabled(task != nil || !online || !images || !metrics || coordinator.privateHealthReportCodexTarget() == nil || !Vision.eligible(job))
          if task != nil {
            ProgressView()
            Button(t("cancel", "Cancel request"), role: .destructive) { cancel() }
          }
        }
      }
      if failed { Text(t("failed", "Nothing was confirmed. The image, permission or provider may have changed, or the reply was invalid.")).foregroundColor(.secondary) }
    }
    .navigationTitle(t("title", "Transcribe with a vision model"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { cancel(); review = nil }
    .onChange(of: scene) { phase in
      if phase == .active { reload() } else { cancel(); review = nil; job = nil; originalPreview = nil }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in cancel(); review = nil; job = nil; originalPreview = nil }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      cancel(); review = nil; job = nil; originalPreview = nil
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { event in
      if event.object as? String == records.owner {
        reload()
        if let activeReview, (try? current(activeReview)) == nil { cancel() }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { event in
      if event.object as? String == records.owner { cancel(); review = nil; originalPreview = nil; reload() }
    }
    .sheet(item: $review) { approval in
      NavigationView {
        List {
          if let image = UIImage(data: approval.jpeg) { Image(uiImage: image).resizable().scaledToFit() }
          Text(approval.target.title)
          Text(String(format: t("bytes", "One image, %lld bytes"), Int64(approval.jpeg.count)))
          Text(t("paired_disclosure", "Send this single image to the paired Desktop's Codex in a separate temporary read-only thread. No history, tools, search, offline queue or provider fallback. Results remain unconfirmed."))
          Button(t("send", "Send this image once")) { send(approval) }
        }
        .navigationTitle(t("preview", "Review image before sending"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel", "Cancel request")) { review = nil } } }
      }.navigationViewStyle(.stack)
    }
  }

  private func sourceContext(_ result: Vision.Result) -> GalaxySSIHealthOCRSourceContext {
    GalaxySSIHealthOCRSourceContext.inspect(["Collected at: " + result.collected],
      timeZone: job?.reportVisionZone.flatMap(TimeZone.init(identifier:)) ?? zone)
  }
  private func change(_ operation: () throws -> Void) {
    cancel(); review = nil
    do { try operation(); failed = false; reload() } catch { failed = true }
  }
  private func reload() {
    guard accessible else { job = nil; return }
    do {
      let archive = try records.load()
      online = archive.healthOnlinePermission != nil; images = archive.reportImagePermission != nil; metrics = archive.derivesOverview == true
      guard let current = archive.recognitionJobs?.first(where: { $0.id == jobID }),
            try originals.list().originals.contains(current.original) else { throw GalaxySSIHealthRecords.Failure.stale }
      job = current
      if originalPreview == nil { originalPreview = UIImage(data: try GalaxySSIHealthReportVisionProvider.jpeg(input(current))) }
    } catch { job = nil; originalPreview = nil; failed = true }
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
    do {
      reload()
      guard let job, Vision.eligible(job), let target = coordinator.privateHealthReportCodexTarget()
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      review = Review(job: job, consent: try .init(records.load()), target: target,
        jpeg: try GalaxySSIHealthReportVisionProvider.jpeg(input(job)), zone: zone.identifier)
      failed = false
    } catch { review = nil; failed = true }
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
      let id = UUID(); run = id; activeReview = approval; review = nil; failed = false
      task = Task {
        defer {
          if run == id { run = nil; task = nil; activeReview = nil }
        }
        do {
          try current(approval)
          let response = try await coordinator.transcribePrivateHealthReport(target: approval.target, jpeg: approval.jpeg,
            instructions: GalaxySSIHealthReportVisionProvider.instructions, valid: { (try? current(approval)) != nil })
          try current(approval)
          guard run == id else { throw CancellationError() }
          let result = try Vision.parse(response)
          try records.commitReportVision(result, job: approval.job, consent: approval.consent, zone: approval.zone)
          reload()
        } catch { if run == id, !Task.isCancelled { failed = true } }
      }
    } catch { review = nil; failed = true }
  }
  private func cancel() { task?.cancel(); task = nil; run = nil; activeReview = nil }
  private func t(_ key: String, _ fallback: String) -> String { Vision.text(key, fallback, language) }
}
