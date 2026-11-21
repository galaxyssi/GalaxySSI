import CryptoKit
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
  @State private var provider = ""
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
    let contact: GalaxySSIContact
    let model: CloudModelConfig
    let keyDigest: SHA256.Digest
    let jpeg: Data
    let zone: String
  }
  private var targets: [GalaxySSIContact] {
    store.contacts.filter { !$0.deleted && $0.deliveryMode == .cloudAPI }.map {
      CloudModelRequestRoutingPolicy.resolve(contact: $0, requestedModelId: "", hasImageInput: true)
    }.filter { $0.selectedCloudModel.flatMap(GalaxySSIHealthCareDiscussion.endpoint(for:)) != nil }
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
          Toggle(t("permission", "Allow report images in explicitly confirmed cloud requests"), isOn: Binding(get: { images }, set: { value in
            change { try records.setPrivacy(.reportImages, enabled: value) }
          }))
          Toggle(t("metrics", "Allow health measurement processing"), isOn: Binding(get: { metrics }, set: { value in
            change { try records.setPrivacy(.overview, enabled: value) }
          }))
          Picker(t("model", "Vision model"), selection: $provider) {
            Text(t("choose", "Choose a configured model")).tag("")
            ForEach(targets) { contact in Text(contact.name + " / " + (contact.selectedCloudModel?.modelId ?? "")).tag(contact.id) }
          }.disabled(task != nil)
          Button(t("preview", "Review image before sending"), action: prepare)
            .disabled(task != nil || !online || !images || !metrics || provider.isEmpty || !Vision.eligible(job))
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
          Text(approval.contact.name + " / " + approval.model.modelId)
          Text(approval.model.endpoint).font(.footnote)
          Text(String(format: t("bytes", "One image, %lld bytes"), Int64(approval.jpeg.count)))
          Text(t("disclosure", "This image may contain personal details. Send only this image for transcription; no chat history or other health records are included. Results remain unconfirmed drafts."))
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
      guard let job, Vision.eligible(job), let contact = targets.first(where: { $0.id == provider }),
            let model = contact.selectedCloudModel, let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key)
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      review = Review(job: job, consent: try .init(records.load()), contact: contact, model: model,
        keyDigest: SHA256.hash(data: Data(key.utf8)), jpeg: try GalaxySSIHealthReportVisionProvider.jpeg(input(job)), zone: zone.identifier)
      failed = false
    } catch { review = nil; failed = true }
  }
  private func current(_ approval: Review) throws -> String {
    guard accessible, !Task.isCancelled, provider == approval.contact.id, zone.identifier == approval.zone,
          targets.first(where: { $0.id == provider })?.selectedCloudModel == approval.model,
          try Vision.Consent(records.load()) == approval.consent,
          try records.load().recognitionJobs?.contains(approval.job) == true,
          try originals.list().originals.contains(approval.job.original),
          let key = store.apiKey(for: approval.model), SHA256.hash(data: Data(key.utf8)) == approval.keyDigest,
          !coordinator.healthDisclosureStore.blockedDestinationIds().contains(approval.contact.id) else {
      throw GalaxySSIHealthRecords.Failure.stale
    }
    _ = try input(approval.job)
    return key
  }
  private func send(_ approval: Review) {
    guard review?.id == approval.id, task == nil else { return }
    do {
      let key = try current(approval)
      let request = try GalaxySSIHealthReportVisionProvider.request(approval.model, key: key, jpeg: approval.jpeg)
      let ledger = coordinator.healthDisclosureStore
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: approval.contact),
        text: GalaxySSIHealthReportVisionProvider.instructions, systemInstructions: true, purpose: "Explicit report image transcription",
        attachments: [.init(displayName: "report.jpg", mimeType: "image/jpeg", sizeBytes: Int64(approval.jpeg.count))])
      guard ticket.allowed else { failed = true; review = nil; return }
      let id = UUID(); run = id; activeReview = approval; review = nil; failed = false
      task = Task {
        var status: AgentDisclosureStatus = .failed
        defer {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: status,
            failureReason: status == .failed ? "health_image_request_not_completed" : "")
          if run == id { run = nil; task = nil; activeReview = nil }
        }
        do {
          _ = try current(approval)
          let data = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 196_608, mimeTypes: ["application/json"])
          status = .sent
          _ = try current(approval)
          guard run == id else { throw CancellationError() }
          let result = try Vision.parse(GalaxySSIHealthFollowUpTransport.output(data, style: approval.model.apiStyle))
          try records.commitReportVision(result, job: approval.job, consent: approval.consent, zone: approval.zone)
          reload()
        } catch { if run == id, !Task.isCancelled { failed = true } }
      }
    } catch { review = nil; failed = true }
  }
  private func cancel() { task?.cancel(); task = nil; run = nil; activeReview = nil }
  private func t(_ key: String, _ fallback: String) -> String { Vision.text(key, fallback, language) }
}
