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
              Button(t("save", "Save encrypted backup")) { exporting = true }
            }
          }
        }
        if task != nil { ProgressView(t("working", "Processing backup")) }
        if error {
          Text(t("failed", "Could not prepare or verify this backup. Check its size, password and contents."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("title", "Health Backup"))
    .navigationBarTitleDisplayMode(.inline)
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
    .fileExporter(isPresented: $exporting, document: generated, contentType: .data,
                  defaultFilename: "GalaxySSI-Health.galaxyhealth") { result in
      if case .failure = result { error = true }
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
        case .created(let data, let summary): generated = BackupFile(data: data); outcome = summary
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
