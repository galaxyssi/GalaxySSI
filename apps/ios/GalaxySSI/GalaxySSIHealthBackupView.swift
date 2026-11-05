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
  @State private var restoring = false
  @State private var restoreInput: GalaxySSIHealthPortableBackup.RestoreInput?
  @State private var restorePreview: GalaxySSIHealthPortableBackup.RestorePreview?
  @State private var acknowledged = false
  @State private var restored = false
  @State private var shownConflicts = 30
  @State private var replacements: Set<UUID> = []

  private enum WorkResult: Sendable {
    case created(Data, GalaxySSIHealthPortableBackup.Summary)
    case verified(GalaxySSIHealthPortableBackup.Summary)
    case unlocked(GalaxySSIHealthPortableBackup.RestoreInput)
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
          Button(t("choose_restore", "Choose backup to restore")) {
            reset()
            restoring = true
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
        Group {
          historySection
          if saveUnverified { Text(t("save_unverified", "The external file could not be verified.")) }
          if verifyingSave { ProgressView(t("working", "Processing backup")) }
          if saveAttempt != nil && !verifyingSave {
            Button(t("dismiss_save", "Dismiss unverified save")) { finishSave(.failure(CancellationError())) }
          }
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
        if let restorePreview { restoreSection(restorePreview) }
        if restored { Text(t("restored", "Health backup restored")) }
        if task != nil { ProgressView(t("working", "Processing backup")) }
        if error {
          Text(restoring ? t("restore_failed", "Could not restore this backup. Check its password, owner and contents, or reopen it if local data changed.") :
            t("failed", "Could not prepare or verify this backup. Check its size, password and contents."))
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
        Button(restoring ? t("restore_preview", "Unlock restore preview") : t("verify", "Verify without restoring"), action: verify)
          .disabled(password.count < 8 || task != nil)
      }
    }
  }

  private func restoreSection(_ preview: GalaxySSIHealthPortableBackup.RestorePreview) -> some View {
    Section(t("restore_preview", "Unlock restore preview")) {
      Text(t("restore_owner_review", "Restore to my current profile. Local versions are kept unless selected for replacement."))
      Text(String(format: t("restore_counts", "%lld new measurements · %lld duplicates · %lld conflicts"),
                  Int64(preview.readings), Int64(preview.duplicates), Int64(preview.conflicts.count)))
      Text(String(format: t("restore_files", "%lld original files · %lld tables · %lld missing sources"),
                  Int64(preview.originals), Int64(preview.tables), Int64(preview.missing)))
      Text(String(format: t("restore_links", "%lld new links · %lld reused · %lld skipped"),
                  Int64(preview.newLinks), Int64(preview.reusedLinks), Int64(preview.skippedLinks)))
      ForEach(preview.conflicts.prefix(shownConflicts)) { conflict in
        DisclosureGroup(conflict.backup.metric.title(language: language)) {
          conflictVersion(t("restore_local", "Local version"), reading: conflict.local)
          conflictVersion(t("restore_backup_version", "Backup version"), reading: conflict.backup)
          if let restriction = conflict.restriction {
            Text(restrictionText(restriction)).foregroundColor(.secondary)
          } else {
            Toggle(t("restore_use_backup", "Use backup version"), isOn: Binding(
              get: { replacements.contains(conflict.id) }, set: { selected in
                acknowledged = false
                if selected { replacements.insert(conflict.id) } else { replacements.remove(conflict.id) }
              }))
          }
        }
      }
      if preview.conflicts.count > shownConflicts {
        Button(t("more_conflicts", "Show more conflicts")) { shownConflicts += 30 }
      }
      if preview.hasChanges || !replacements.isEmpty {
        if !replacements.isEmpty {
          Text(String(format: t("restore_replace_count", "%lld new revisions selected"), Int64(replacements.count)))
        }
        Toggle(t("restore_consent", "I reviewed the changes"), isOn: $acknowledged)
        Button(t("restore", "Restore to this device"), action: restore).disabled(!acknowledged || task != nil)
      }
    }
  }

  private func conflictVersion(_ title: String, reading: GalaxySSIHealthReading) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.weight(.semibold))
      if reading.deleted {
        Text(t("restore_deleted", "Deleted locally"))
      } else {
        let value = reading.reported?.raw ?? reading.value?.formatted() ?? ""
        let diastolic = reading.diastolic.map { "/" + $0.formatted() } ?? ""
        Text(value + diastolic + " " + reading.unit)
        if let pulse = reading.pulse { Text(pulse.formatted() + " bpm") }
        Text(reading.measuredAt, format: .dateTime)
        if !reading.conditions.isEmpty { Text(reading.conditions) }
        if !reading.notes.isEmpty { Text(reading.notes) }
        if let reference = reading.referenceInterval, !reference.isEmpty { Text(reference) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func restrictionText(_ restriction: GalaxySSIHealthPortableBackup.RestoreConflict.Restriction) -> String {
    switch restriction {
    case .deleted: return t("restore_deleted", "Deleted locally")
    case .source: return t("restore_source_mismatch", "Source differs or cannot be verified")
    case .draft: return t("restore_pending_edit", "An unfinished local edit exists")
    case .ambiguous: return t("restore_ambiguous", "Another local measurement matches this version")
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
    run { [secret = password, restoring] in
      if restoring { return .unlocked(try GalaxySSIHealthPortableBackup.unlock(verificationInput, password: secret)) }
      return .verified(try GalaxySSIHealthPortableBackup.verify(verificationInput, password: secret))
    }
  }

  private func restore() {
    guard scene == .active, acknowledged, let restoreInput, let restorePreview else { return }
    do {
      try GalaxySSIHealthPortableBackup.restore(restoreInput, expected: restorePreview, records: records,
                                                originals: originals, replacing: replacements)
      reset()
      restored = true
    } catch {
      reset()
      restoring = true
      error = true
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
        case .unlocked(let input):
          restorePreview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: records, originals: originals)
          restoreInput = input
        }
        plan = nil
        verificationInput = nil
      } catch {
        guard token == request, scene != .background else { return }
        if generationID != nil {
          try? history.recover()
          if let refreshed = try? history.entries() { entries = refreshed }
        }
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
    restoring = false; restoreInput = nil; restorePreview = nil; acknowledged = false; restored = false; shownConflicts = 30
    replacements = []
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
