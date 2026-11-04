import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthBackupView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  let originals: GalaxySSIHealthOriginalStore
  @State private var plan: GalaxySSIHealthPortableBackup.Plan?
  @State private var verificationInput: Data?
  @State private var password = ""
  @State private var repeated = ""
  @State private var generated: BackupFile?
  @State private var outcome: GalaxySSIHealthPortableBackup.Summary?
  @State private var task: Task<Void, Never>?
  @State private var token: UUID?
  @State private var choosing = false
  @State private var exporting = false
  @State private var generationID: UUID?
  @State private var saveAttempt: GalaxySSIHealthBackupHistory.Entry?
  @State private var exportDocument: BackupFile?
  @State private var verifyingSave = false
  @State private var entries: [GalaxySSIHealthBackupHistory.Entry] = []
  @State private var historyLoaded = false
  @State private var historyLimit = 10
  @State private var saveUnverified = false

  private var history: GalaxySSIHealthBackupHistory {
    GalaxySSIHealthBackupHistory(owner: records.owner, secrets: records.secrets)
  }
  @State private var error = false

  private enum WorkResult: Sendable {
    case created(Data, GalaxySSIHealthPortableBackup.Summary)
    case verified(GalaxySSIHealthPortableBackup.Summary)
  }

  var body: some View {
    Form {
      if scene == .active && !exporting {
        Section {
          Button(t("preview", "Preview new backup"), action: preview).disabled(task != nil)
          Button(t("choose", "Choose backup to verify")) {
            reset()
            choosing = true
          }
          .disabled(task != nil)
        }
        if let plan {
          Section(t("scope", "Backup contents")) { stats(plan.summary) }
        }
        if plan != nil || verificationInput != nil {
          passwordForm
        }
        if let outcome {
          Section(generated != nil ? t("created", "Encrypted backup ready") : t("verified", "Backup verified")) {
            stats(outcome)
            if generated != nil {
              Button(t("save", "Save encrypted backup")) {
                if let entry = entries.first(where: { $0.id == generationID }) { save(entry) }
              }
              .disabled(saveAttempt != nil)
            }
          }
        }
        historySection
        if saveUnverified { Text(t("save_unverified", "The external file could not be verified.")) }
        if task != nil || verifyingSave { ProgressView(t("working", "Processing backup")) }
        if saveAttempt != nil && !verifyingSave {
          Button(t("dismiss_save", "Dismiss unverified save")) { finishSave(.failure(CancellationError())) }
        }
        if error {
          Text(t("failed", "Could not prepare or verify this backup. Check its size, password and contents."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Health Backup"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      guard !historyLoaded else { return }
      do {
        try history.recover()
        entries = try history.entries()
        historyLoaded = true
      } catch { error = true }
    }
    .onChange(of: scene) { phase in
      if phase == .background && !exporting { reset() }
    }
    .onDisappear { reset() }
    .fileImporter(isPresented: $choosing, allowedContentTypes: [.data]) { result in
      guard scene != .background else { return }
      do {
        let url = try result.get()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: GalaxySSIHealthPortableBackup.maximumFileBytes + 1),
              !data.isEmpty, data.count <= GalaxySSIHealthPortableBackup.maximumFileBytes
        else { throw GalaxySSIHealthPortableBackup.Failure.limit }
        verificationInput = data
      } catch { error = true }
    }
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .data,
                  defaultFilename: "GalaxySSI-Health.galaxyhealth") { result in
      finishSave(result)
    }
  }

  private var historySection: some View {
    Section(t("history", "Backup history")) {
      ForEach(entries.prefix(historyLimit)) { entry in
        VStack(alignment: .leading, spacing: 5) {
          Text(entry.at, style: .date)
          Text(entry.generation == .ready ? t("history_ready", "Generated") :
            (entry.generation == .pending ? t("working", "Processing backup") :
              t("history_interrupted", "Generation interrupted")))
          Text(history.hasCopy(entry) ? t("copy_available", "Private copy available") :
            t("copy_unavailable", "No private copy")).foregroundColor(.secondary)
          if let at = entry.lastVerifiedAt {
            Text(t("last_verified", "Last verified save") + ": " + at.formatted())
          }
          if entry.latestSave == .unverified || entry.latestSave == .interrupted {
            Text(t("save_unverified", "The external file could not be verified.")).foregroundColor(.secondary)
          }
          if history.hasCopy(entry) {
            Button(t("save", "Save encrypted backup")) { save(entry) }
              .disabled(task != nil || saveAttempt != nil)
          }
        }
      }
      if entries.count > historyLimit {
        Button(t("history_more", "Show older backups")) { historyLimit += 10 }
      }
    }
  }

  private func save(_ entry: GalaxySSIHealthBackupHistory.Entry) {
    guard scene == .active, saveAttempt == nil else { return }
    do {
      let data = try history.readCopy(entry)
      saveAttempt = try history.beginSave(entry.id)
      exportDocument = BackupFile(data: data)
      saveUnverified = false
      exporting = true
    } catch { error = true }
  }

  private func finishSave(_ result: Result<URL, Error>) {
    guard let attempt = saveAttempt, !verifyingSave else { return }
    verifyingSave = true
    Task {
      let verified: Bool
      if case .success(let url) = result {
        verified = await Task.detached(priority: .utility) {
          (try? GalaxySSIHealthBackupHistory.verifyDestination(url, entry: attempt)) == true
        }.value
      } else { verified = false }
      do {
        try history.finishSave(attempt.id, verified: verified)
        entries = try history.entries()
        saveUnverified = !verified
      } catch { error = true }
      saveAttempt = nil
      exportDocument = nil
      verifyingSave = false
    }
  }

  private var passwordForm: some View {
    Section(t("password", "Backup password")) {
      SecureField(t("password", "Backup password"), text: $password)
      if plan != nil {
        SecureField(t("repeat", "Confirm password"), text: $repeated)
        Button(t("generate", "Generate encrypted backup"), action: generate)
          .disabled(password.count < 8 || password != repeated || task != nil)
      } else {
        Button(t("verify", "Verify without restoring"), action: verify)
          .disabled(password.count < 8 || task != nil)
      }
    }
  }

  private func stats(_ value: GalaxySSIHealthPortableBackup.Summary) -> some View {
    Group {
      Text(String(format: t("readings", "%lld confirmed measurements"), Int64(value.readings)))
      Text(String(format: t("originals", "%lld image or PDF originals"), Int64(value.originals)))
      Text(String(format: t("tables", "%lld table originals"), Int64(value.tables)))
      Text(String(format: t("links", "%lld measurement source links"), Int64(value.links)))
      if let start = value.start, let end = value.end {
        Text(start.formatted(date: .abbreviated, time: .omitted) + " – " + end.formatted(date: .abbreviated, time: .omitted))
      }
      Text(ByteCountFormatter.string(fromByteCount: Int64(value.estimatedBytes), countStyle: .file))
        .foregroundColor(.secondary)
      if value.missing > 0 {
        Text(String(format: t("incomplete", "Incomplete: %lld missing originals or source links"), Int64(value.missing)))
          .foregroundColor(.orange)
      }
    }
  }

  private func preview() {
    guard scene == .active else { return }
    reset()
    do { plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals) }
    catch { error = true }
  }

  private func generate() {
    guard scene == .active, let plan, password == repeated else { return }
    do {
      let (bytes, summary) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
      generationID = try history.begin()
      entries = try history.entries()
      run { [secret = password] in
        .created(try GalaxySSIHealthPortableBackup.seal(bytes, password: secret), summary)
      }
    } catch {
      password = ""; repeated = ""; error = true
    }
  }

  private func verify() {
    guard scene == .active, let verificationInput else { return }
    run { [secret = password] in
      .verified(try GalaxySSIHealthPortableBackup.verify(verificationInput, password: secret))
    }
  }

  private func run(_ work: @escaping @Sendable () throws -> WorkResult) {
    password = ""; repeated = ""; error = false
    let request = UUID()
    token = request
    task = Task {
      let worker = Task.detached(priority: .userInitiated, operation: work)
      do {
        let result = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                           onCancel: { worker.cancel() })
        guard token == request, scene != .background else { return }
        switch result {
        case .created(let data, let summary):
          guard let generationID else { throw GalaxySSIHealthPortableBackup.Failure.stale }
          try history.publish(data, id: generationID)
          entries = try history.entries()
          generated = BackupFile(data: data)
          outcome = summary
        case .verified(let summary): outcome = summary
        }
        plan = nil
        verificationInput = nil
      } catch {
        guard token == request, scene != .background else { return }
        error = true
      }
      task = nil
    }
  }

  private func reset() {
    if generationID != nil, task != nil, saveAttempt == nil {
      try? history.recover()
      if let refreshed = try? history.entries() { entries = refreshed }
    }
    generationID = nil
    task?.cancel(); task = nil; token = nil
    password = ""; repeated = ""
    plan = nil; verificationInput = nil; generated = nil; outcome = nil; error = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.backup." + key, fallback: fallback, language: language)
  }
}

private struct BackupFile: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  let data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
