import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthOriginalExportSaveControl: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIHealthOriginalStore
  let attempt: GalaxySSIHealthOriginalStore.ExportAttempt
  let activity: (Bool) -> Void
  @State private var confirming = false
  @State private var exporting = false
  @State private var verifying = false
  @State private var failed = false
  @State private var request: GalaxySSIHealthOriginalExportSave.Request?
  @State private var document: ZIPDocument?

  var body: some View {
    Group {
      if scene == .active {
        if let at = attempt.lastVerifiedAt {
          Text(t("last_verified", "Last verified save") + ": " + at.formatted()).foregroundColor(.secondary)
        }
        if let receipt = attempt.latestSave {
          Text(status(receipt.outcome)).foregroundColor(.secondary)
        }
        if store.hasShareArtifact(attempt) {
          Button { confirming = true } label: {
            Label(t("save_again", "Save ZIP to Files"), systemImage: "square.and.arrow.down")
          }
          .disabled(exporting || verifying || request != nil || liveSave)
        }
        if verifying { ProgressView(t("verifying_destination", "Verifying saved file")) }
        if failed { Text(t("save_receipt_failed", "The save or its receipt could not be verified. Check history before retrying.")) }
      }
    }
    .privacySensitive()
    .confirmationDialog(t("save_plain_zip", "Save this unencrypted ZIP?"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("save_again", "Save ZIP to Files"), action: save)
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: .zip,
                  defaultFilename: "GalaxySSI-Health-Originals") { result in finish(result) }
    .onChange(of: scene) {
      if $0 != .active { confirming = false; if !exporting { document = nil } }
    }
    .onDisappear {
      if !exporting && !verifying, let request {
        try? store.interruptExportSave(request)
        self.request = nil
        document = nil
        activity(false)
      }
    }
  }

  private var liveSave: Bool {
    guard let receipt = attempt.latestSave, receipt.outcome == .pending else { return false }
    return GalaxySSIHealthOriginalExportSave.isActive(receipt.id,
      scope: .init(owner: store.owner, directory: store.fixtureDirectory, recordsFile: store.restoreRecordsFile))
  }

  private func save() {
    guard scene == .active, request == nil, !exporting, !verifying else { return }
    do {
      let (bytes, request) = try store.beginExportSave(attempt)
      self.request = request
      document = ZIPDocument(data: bytes)
      failed = false
      activity(true)
      exporting = true
    } catch { failed = true }
  }

  private func finish(_ result: Result<URL, Error>) {
    guard let request, !verifying else { return }
    document = nil
    verifying = true
    Task {
      let verified: Bool
      if case .success(let url) = result {
        verified = await Task.detached(priority: .utility) {
          (try? GalaxySSIHealthOriginalStore.verifyDestination(url, for: request.export)) == true
        }.value
      } else { verified = false }
      do { try store.finishExportSave(request, verified: verified); failed = !verified }
      catch { failed = true }
      self.request = nil
      verifying = false
      activity(false)
    }
  }

  private func status(_ outcome: GalaxySSIHealthOriginalExportSave.Receipt.Outcome) -> String {
    switch outcome {
    case .pending: return t("save_pending", "Save pending")
    case .verified: return t("verified", "Save verified")
    case .unverified: return t("not_verified", "Save could not be verified")
    case .interrupted: return t("save_interrupted", "Previous save was interrupted")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.originals." + key, fallback: fallback, language: language)
  }
}

private struct ZIPDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.zip] }
  let data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
