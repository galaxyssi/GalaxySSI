import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIHealthTableSourceSample {
  let headers: [String]
  let rows: [[String]]
  let limited: Bool

  init(_ table: GalaxySSIHealthTableImport.Table) {
    let columns = table.headers.prefix(12).map { String($0.prefix(256)) }
    headers = columns
    rows = table.rows.prefix(30).map { row in
      columns.indices.map { row.indices.contains($0) ? String(row[$0].prefix(256)) : "" }
    }
    limited = table.headers.count > 12 || table.rows.count > 30 ||
      table.headers.prefix(12).contains(where: { $0.count > 256 }) ||
      table.rows.prefix(30).contains(where: { $0.prefix(12).contains { $0.count > 256 } })
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
        if let sample {
          if sample.limited {
            Text(t("limited", "Preview limited to 30 rows, 12 columns and 256 characters per cell."))
              .font(.footnote).foregroundColor(.secondary)
          }
          ForEach(sample.rows.indices, id: \.self) { row in
            DisclosureGroup(String(format: t("row", "Data row %lld"), Int64(row + 1))) {
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
    guard let batch = try records.load().tableBatches?.first(where: { $0.id == batchID }) else {
      throw GalaxySSIHealthTableImport.Failure.stale
    }
    return batch
  }

  private func reload() {
    guard scene == .active, !exporting else { return }
    name = nil
    sample = nil
    error = false
    do {
      let batch = try batch()
      name = batch.name
      let json = URL(fileURLWithPath: batch.name).pathExtension.lowercased() == "json"
      sample = GalaxySSIHealthTableSourceSample(try GalaxySSIHealthTableImport.parse(batch.data, json: json))
    } catch { error = true }
  }

  private func save() {
    guard scene == .active else { return }
    do {
      let batch = try batch()
      let ext = URL(fileURLWithPath: batch.name).pathExtension.lowercased()
      guard ext == "csv" || ext == "json" else { throw GalaxySSIHealthTableImport.Failure.malformed }
      document = TableOriginalDocument(data: batch.data, type: ext == "json" ? .json : .commaSeparatedText,
                                       name: batch.name)
      exporting = true
    } catch { error = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table_source." + key, fallback: fallback, language: language)
  }
}

private struct TableOriginalDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
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
