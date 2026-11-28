import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIHealthTableSourceSample: Sendable {
  let headers: [String]
  let rows: [[String]]
  let rowNumbers: [Int]
  let limited: Bool

  init(_ table: GalaxySSIHealthTableImport.Table, rowLimit: Int = 30, cellLimit: Int = 256) {
    let rowLimit = min(30, max(1, rowLimit)), cellLimit = min(512, max(1, cellLimit))
    let columns = table.headers.prefix(12).map { Self.clip($0, limit: cellLimit) }
    headers = columns
    rows = table.rows.prefix(rowLimit).map { row in
      columns.indices.map { row.indices.contains($0) ? Self.clip(row[$0], limit: cellLimit) : "" }
    }
    rowNumbers = (0..<min(table.rows.count, rowLimit)).map { $0 + 1 }
    limited = table.headers.count > 12 || table.rows.count > rowLimit ||
      table.headers.prefix(12).contains(where: { $0.count > cellLimit }) ||
      table.rows.prefix(rowLimit).contains(where: { $0.prefix(12).contains { $0.count > cellLimit } })
  }

  init(sheetRows: [GalaxySSIHealthXLSX.SheetRow], rowLimit: Int = 30, cellLimit: Int = 256) {
    let rowLimit = min(30, max(1, rowLimit)), cellLimit = min(512, max(1, cellLimit))
    let firstRows = sheetRows.prefix(rowLimit)
    let lastColumn = firstRows.flatMap { Array($0.cells.keys) + Array($0.formulas) }.max() ?? 0
    let columns = 0...min(lastColumn, 11)
    headers = columns.map { _ in "" }
    rowNumbers = firstRows.map(\.number)
    rows = firstRows.map { row in
      columns.map { column in
        let cached = row.cells[column] ?? ""
        if let formula = row.formulaText[column], !formula.isEmpty {
          return Self.clip("=" + formula + (cached.isEmpty ? "" : "\n" + cached), limit: cellLimit)
        }
        return Self.clip(cached, limit: cellLimit)
      }
    }
    limited = sheetRows.count > rowLimit || lastColumn > 11 || firstRows.contains { row in
      columns.contains { column in
        let formula = row.formulaText[column] ?? ""
        return (row.cells[column]?.count ?? 0) + (formula.isEmpty ? 0 : formula.count + 2) > cellLimit
      }
    }
  }

  private static func clip(_ text: String, limit: Int) -> String {
    // Legacy callers retain their existing 256-character contract.
    guard limit == 512, text.count > limit else { return String(text.prefix(limit)) }
    return String(text.prefix(limit - 1)) + "\u{2026}"
  }
}

@MainActor
struct GalaxySSIHealthTableSourceView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  let batchID: UUID
  @State private var name: String?
  @State private var sample: GalaxySSIHealthTableSourceSample?
  @State private var error = false
  @State private var confirming = false
  @State private var exporting = false
  @State private var document: TableOriginalDocument?
  @State private var sheets: [Worksheet] = []
  @State private var sheetID = ""
  @State private var requestID = UUID()
  @State private var loading = false
  @State private var previewEnabled = true
  @State private var linked: [GalaxySSIHealthTableImport.LinkedReading] = []
  @State private var linkedLimit = 30
  @State private var confirmingLinked = false

  private struct Worksheet: Identifiable, Sendable {
    let id: String
    let name: String
  }

  private struct LoadedPreview: Sendable {
    let sheets: [Worksheet]
    let sheetID: String
    let sample: GalaxySSIHealthTableSourceSample
  }

  var body: some View {
    List {
      if scene == .active && !exporting {
        if let name {
          Section {
            Text(name).font(.headline)
            Button { confirming = true } label: {
              Label(t("save", "Save original file"), systemImage: "square.and.arrow.up")
            }
          }
        }
        if !sheets.isEmpty {
          Picker(t("sheet", "Worksheet"), selection: Binding(get: { sheetID }, set: selectSheet)) {
            ForEach(sheets) { sheet in Text(sheet.name).tag(sheet.id) }
          }
        }
        if let sample {
          if sample.limited {
            Text(t("grid_limited", "Preview limited to 20 rows, 12 columns and 512 characters per cell."))
              .font(.footnote).foregroundColor(.secondary)
          }
          GalaxySSIHealthTablePreviewGrid(sample: sample).id(requestID)
        }
        if loading {
          ProgressView(t("loading", "Loading preview"))
          Button(t("cancel_preview", "Cancel preview"), action: invalidate)
        }
        if !previewEnabled {
          Button(t("reload", "Reload original"), action: reload)
        }
        if !linked.isEmpty {
          Section(t("linked_records", "Linked measurements")) {
            ForEach(linked.prefix(linkedLimit)) { item in
              VStack(alignment: .leading, spacing: 4) {
                Text(item.reading.metric.title(language: language))
                Text(String(format: t("row", "Source row %lld"), Int64(item.source.row)) + " · " +
                  String(format: t("link_revision", "Revision %lld"), Int64(item.reading.revision)))
                  .foregroundColor(.secondary)
                Text(item.secondary ? t("secondary_link", "Additional source") : t("primary_link", "Primary source"))
                  .foregroundColor(.secondary)
                if let decision = item.source.dateOnlyDecision {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(tableLabel("source_time", "Source time") + ": " + decision.sourceDate)
                    Text(String(format: tableLabel("date_only_applied", "Confirmed date-only time: %@"), decision.clock))
                    Text(tableLabel("resolved_time", "Resolved time") + ": " + decision.resolvedTime.formatted(.iso8601))
                  }
                  .font(.caption).foregroundColor(.secondary)
                }
              }
            }
            if linked.count > linkedLimit { Button(t("links_more", "Show more links")) { linkedLimit += 30 } }
            Button(t("export_linked", "Export linked measurements and original")) { confirmingLinked = true }
          }
        }
        if error {
          Text(t("unavailable", "The original or its preview is unavailable.")).foregroundColor(.secondary)
          Button(t("reload", "Reload original"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Table Original"))
    .galaxySSIHealthTheme()
    .task(id: requestID) { await loadPreview() }
    .onAppear { if !previewEnabled { reload() } }
    .onDisappear(perform: invalidate)
    .onChange(of: records.owner) { _ in reload() }
    .onChange(of: records.isolatedFile) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in
      invalidate()
    }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { invalidate() }
    }
    .confirmationDialog(t("unencrypted", "Save the unencrypted original?"), isPresented: $confirming,
                        titleVisibility: .visible) {
      Button(t("save", "Save original file"), action: save)
    }
    .confirmationDialog(t("unencrypted_linked", "Save an unencrypted ZIP with measurements and the original?"),
                        isPresented: $confirmingLinked, titleVisibility: .visible) {
      Button(t("export_linked", "Export linked measurements and original"), action: saveLinked)
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { confirmingLinked = false; reload() }
    }
    .fileExporter(isPresented: $exporting, document: document,
                  contentType: document?.type ?? .data, defaultFilename: document?.name) { result in
      document = nil
      if case .failure = result { error = true }
    }
    .onChange(of: exporting) {
      if !$0 {
        document = nil
        if sample == nil { reload() }
      }
    }
  }

  private func batch() throws -> GalaxySSIHealthTableImport.Batch {
    guard let batch = try GalaxySSIHealthTableImport.Batch.original(for: batchID, in: records.load().tableBatches ?? []) else {
      throw GalaxySSIHealthTableImport.Failure.stale
    }
    return batch
  }

  private func reload() {
    invalidate()
    previewEnabled = true
  }

  private func invalidate() {
    requestID = UUID()
    previewEnabled = false
    name = nil
    sample = nil
    linked = []
    sheets = []
    sheetID = ""
    loading = false
    confirming = false
    confirmingLinked = false
    error = false
    if !exporting { document = nil }
  }

  private func loadPreview() async {
    guard previewEnabled, scene == .active, !exporting, !Task.isCancelled else { return }
    let token = requestID, owner = records.owner, dataset = records.isolatedFile, selected = sheetID
    loading = true
    error = false
    do {
      let batch = try batch()
      let digest = GalaxySSIHealthTableImport.digest(batch.data)
      let ext = URL(fileURLWithPath: batch.name).pathExtension.lowercased()
      let worker = Task.detached(priority: .userInitiated) { [data = batch.data] in
        try Task.checkCancellation()
        let result: LoadedPreview
        if ext == "xlsx" {
          let contents = try GalaxySSIHealthXLSX(data)
          let choices = contents.sheets.map { Worksheet(id: $0.id, name: $0.name) }
          guard let first = choices.first,
                selected.isEmpty || choices.contains(where: { $0.id == selected })
          else { throw GalaxySSIHealthTableImport.Failure.stale }
          let id = selected.isEmpty ? first.id : selected
          let rows = try contents.rows(id)
          result = LoadedPreview(sheets: choices, sheetID: id,
            sample: GalaxySSIHealthTableSourceSample(sheetRows: rows, rowLimit: 20, cellLimit: 512))
        } else {
          let table = try GalaxySSIHealthTableImport.parse(data, json: ext == "json")
          result = LoadedPreview(sheets: [], sheetID: "",
            sample: GalaxySSIHealthTableSourceSample(table, rowLimit: 20, cellLimit: 512))
        }
        try Task.checkCancellation()
        return result
      }
      let result = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                       onCancel: { worker.cancel() })
      guard requestID == token, !Task.isCancelled, scene == .active,
            records.owner == owner, records.isolatedFile == dataset else { return }
      let fresh = try self.batch()
      guard fresh.id == batch.id, fresh.name == batch.name,
            GalaxySSIHealthTableImport.digest(fresh.data) == digest else {
        throw GalaxySSIHealthTableImport.Failure.stale
      }
      linked = try linkedReadings(fresh)
      name = fresh.name
      sheets = result.sheets
      sheetID = result.sheetID
      sample = result.sample
    } catch {
      if requestID == token, !Task.isCancelled, scene == .active { error = true }
    }
    if requestID == token { loading = false }
  }

  private func linkedReadings(_ batch: GalaxySSIHealthTableImport.Batch) throws -> [GalaxySSIHealthTableImport.LinkedReading] {
    let archive = try records.load()
    return GalaxySSIHealthTableImport.linkedReadings(batch: batch, revisions: archive.revisions,
      current: archive.current, evidence: archive.tableEvidence ?? [])
  }

  private func saveLinked() {
    guard scene == .active else { return }
    do {
      let batch = try batch()
      let fresh = try linkedReadings(batch)
      guard !fresh.isEmpty, fresh == linked else { throw GalaxySSIHealthTableImport.Failure.stale }
      let data = try GalaxySSIHealthTableImport.exportLinkedReadings(fresh, batch: batch)
      document = TableOriginalDocument(data: data, type: .zip, name: "GalaxySSI-Health-Table.zip")
      exporting = true
    } catch { error = true }
  }

  private func selectSheet(_ id: String) {
    guard scene == .active, sheets.contains(where: { $0.id == id }), id != sheetID else { return }
    invalidate()
    sheetID = id
    previewEnabled = true
  }

  private func save() {
    guard scene == .active else { return }
    do {
      let batch = try batch()
      let ext = URL(fileURLWithPath: batch.name).pathExtension.lowercased()
      let type: UTType
      switch ext {
      case "xlsx": type = TableOriginalDocument.workbookType
      case "json": type = .json
      default: type = .commaSeparatedText
      }
      document = TableOriginalDocument(data: batch.data, type: type, name: batch.name)
      exporting = true
    } catch { error = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table_source." + key, fallback: fallback, language: language)
  }

  private func tableLabel(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table." + key, fallback: fallback, language: language)
  }
}

private struct TableOriginalDocument: FileDocument {
  static let workbookType = UTType(filenameExtension: "xlsx") ?? .spreadsheet
  static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, workbookType, .zip] }
  let data: Data
  let type: UTType
  let name: String

  init(data: Data, type: UTType, name: String) { self.data = data; self.type = type; self.name = name }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    self.init(data: data, type: configuration.contentType, name: configuration.file.preferredFilename ?? "Health-Table")
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
