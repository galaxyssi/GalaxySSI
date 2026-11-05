import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIHealthTableSourceSample {
  let headers: [String]
  let rows: [[String]]
  let rowNumbers: [Int]
  let limited: Bool

  init(_ table: GalaxySSIHealthTableImport.Table) {
    let columns = table.headers.prefix(12).map { String($0.prefix(256)) }
    headers = columns
    rows = table.rows.prefix(30).map { row in
      columns.indices.map { row.indices.contains($0) ? String(row[$0].prefix(256)) : "" }
    }
    rowNumbers = (0..<min(table.rows.count, 30)).map { $0 + 1 }
    limited = table.headers.count > 12 || table.rows.count > 30 ||
      table.headers.prefix(12).contains(where: { $0.count > 256 }) ||
      table.rows.prefix(30).contains(where: { $0.prefix(12).contains { $0.count > 256 } })
  }

  init(sheetRows: [GalaxySSIHealthXLSX.SheetRow]) {
    let firstRows = sheetRows.prefix(30)
    let lastColumn = firstRows.flatMap { Array($0.cells.keys) + Array($0.formulas) }.max() ?? 0
    let columns = 0...min(lastColumn, 11)
    headers = columns.map { _ in "" }
    rowNumbers = firstRows.map(\.number)
    rows = firstRows.map { row in
      columns.map { column in
        let cached = row.cells[column] ?? ""
        if let formula = row.formulaText[column], !formula.isEmpty {
          return String(("=" + formula + (cached.isEmpty ? "" : "\n" + cached)).prefix(256))
        }
        return String(cached.prefix(256))
      }
    }
    limited = sheetRows.count > 30 || lastColumn > 11 || firstRows.contains { row in
      columns.contains { column in
        let formula = row.formulaText[column] ?? ""
        return (row.cells[column]?.count ?? 0) + (formula.isEmpty ? 0 : formula.count + 2) > 256
      }
    }
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
  @State private var workbook: GalaxySSIHealthXLSX?
  @State private var sheetID = ""

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
        if let workbook {
          Picker(t("sheet", "Worksheet"), selection: Binding(get: { sheetID }, set: selectSheet)) {
            ForEach(workbook.sheets) { sheet in Text(sheet.name).tag(sheet.id) }
          }
        }
        if let sample {
          if sample.limited {
            Text(t("limited", "Preview limited to 30 rows, 12 columns and 256 characters per cell."))
              .font(.footnote).foregroundColor(.secondary)
          }
          ForEach(sample.rows.indices, id: \.self) { row in
            DisclosureGroup(String(format: t("row", "Source row %lld"), Int64(sample.rowNumbers[row]))) {
              ForEach(sample.headers.indices, id: \.self) { column in
                VStack(alignment: .leading, spacing: 3) {
                  Text(sample.headers[column].isEmpty
                    ? String(format: t("column", "Column %lld"), Int64(column + 1))
                    : sample.headers[column]).font(.caption).foregroundColor(.secondary)
                  let text = sample.rows[row][column]
                  Text(text.isEmpty ? t("empty_cell", "Empty") : text).textSelection(.disabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
              }
            }
          }
        }
        if error {
          Text(t("unavailable", "The original or its preview is unavailable.")).foregroundColor(.secondary)
          Button(t("reload", "Reload original"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Table Original"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else {
        name = nil
        sample = nil
        workbook = nil
        sheetID = ""
        confirming = false
        if !exporting { document = nil }
      }
    }
    .confirmationDialog(t("unencrypted", "Save the unencrypted original?"), isPresented: $confirming,
                        titleVisibility: .visible) {
      Button(t("save", "Save original file"), action: save)
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
    guard scene == .active, !exporting else { return }
    name = nil
    sample = nil
    workbook = nil
    sheetID = ""
    error = false
    do {
      let batch = try batch()
      name = batch.name
      let ext = URL(fileURLWithPath: batch.name).pathExtension.lowercased()
      if ext == "xlsx" {
        let contents = try GalaxySSIHealthXLSX(batch.data)
        workbook = contents
        if let first = contents.sheets.first { selectSheet(first.id) }
      } else {
        sample = GalaxySSIHealthTableSourceSample(try GalaxySSIHealthTableImport.parse(batch.data, json: ext == "json"))
      }
    } catch { error = true }
  }

  private func selectSheet(_ id: String) {
    guard scene == .active, let workbook else { return }
    sheetID = id
    sample = nil
    do {
      sample = GalaxySSIHealthTableSourceSample(sheetRows: try workbook.rows(id))
      error = false
    } catch { error = true }
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
}

private struct TableOriginalDocument: FileDocument {
  static let workbookType = UTType(filenameExtension: "xlsx") ?? .spreadsheet
  static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, workbookType] }
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
