import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthTableImportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  var sharedRetentionChoice: Binding<GalaxySSIHealthImportRetentionChoice>?
  @State private var localRetentionChoice = GalaxySSIHealthImportRetentionChoice.useDefault
  @State private var retentionDefault: Bool?
  @State private var fileRetention: Bool?
  var resumeReviewID: UUID?
  var resumeReviewVersion: UUID?
  @State private var pendingReviews: [GalaxySSIHealthReviewReminders.TableDraft] = []
  @State private var openedReview: GalaxySSIHealthReviewReminders.TableDraft?
  @State private var initialRouteOpened = false
  @State private var choosing = false
  @State private var input: Input?
  @State private var mapping = GalaxySSIHealthTableImport.Mapping()
  @State private var rows: [GalaxySSIHealthTableImport.Row]?
  @State private var batches: [GalaxySSIHealthTableImport.Batch] = []
  @State private var owned = false
  @State private var linkedRows: Set<Int> = []
  @State private var limit = 30
  @State private var undo: GalaxySSIHealthTableImport.Batch?
  @State private var message: String?
  @State private var original: OriginalSelection?

  private struct OriginalSelection: Identifiable { let id: UUID }
  @State private var workbook: WorkbookInput?
  @State private var sheetID = ""
  @State private var header = 0
  @State private var headerChoices: [Int] = []

  private struct Input {
    let name: String
    let data: Data
    let json: Bool
    let table: GalaxySSIHealthTableImport.Table
    let retainOriginal: Bool
    var worksheet: GalaxySSIHealthXLSX.Selection?
  }

  private struct WorkbookInput {
    let name: String
    let data: Data
    let contents: GalaxySSIHealthXLSX
    let retainOriginal: Bool
  }

  private var retentionChoice: Binding<GalaxySSIHealthImportRetentionChoice> {
    sharedRetentionChoice ?? $localRetentionChoice
  }

  var body: some View {
    List {
      if scene == .active {
        GalaxySSIHealthImportRetentionPicker(currentDefault: retentionDefault, choice: retentionChoice)
        Button(action: chooseFile) {
          Label(t("choose_formats", "Choose CSV, JSON or XLSX"), systemImage: "folder")
        }
        if let workbook { workbookSection(workbook) }
        if let input {
          mappingSection(input)
          if let rows { review(rows) }
          if rows != nil {
            Button(t("save_review_draft", "Save encrypted review draft")) { saveReviewDraft(input) }
              .disabled(openedReview == nil && pendingReviews.count >= GalaxySSIHealthReviewReminders.maximumTableDrafts)
          }
        } else if !pendingReviews.isEmpty {
          Section(t("resume_review_draft", "Saved table reviews")) {
            ForEach(pendingReviews) { draft in
              Button { resume(draft) } label: { Label(draft.name, systemImage: "tablecells") }
                .swipeActions(allowsFullSwipe: false) {
                  Button(t("discard_review_draft", "Discard saved table review"), role: .destructive) {
                    do { try records.discardTableReview(draft); reload() }
                    catch { message = t("save_failed", "Could not save this batch. Review the rows again.") }
                  }
                }
            }
          }
        }
        if let message { Text(message).foregroundColor(.secondary) }
        if !batches.isEmpty {
          Section(t("history", "Imported batches")) {
            ForEach(batches) { batch in
              VStack(alignment: .leading, spacing: 4) {
                Text(batch.name)
                Text(batch.at, style: .date).foregroundColor(.secondary)
                Text(String(format: t("saved", "%lld measurements saved"), Int64(batch.inserted)))
                if let linked = batch.linked {
                  Text(String(format: t("linked", "%lld source links"), Int64(linked))).foregroundColor(.secondary)
                }
                Button(t("open_source", "View table original")) { original = OriginalSelection(id: batch.id) }
                if let count = batch.undone {
                  Text(String(format: t("undone", "%lld measurements removed"), Int64(count)))
                    .foregroundColor(.secondary)
                } else {
                  Button(t("undo", "Undo this batch"), role: .destructive) { undo = batch }
                }
              }
              .buttonStyle(.borderless)
            }
          }
        }
      }
    }
    .navigationTitle(t("title", "Import Measurement Table"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else if phase == .background {
        choosing = false; fileRetention = nil
        clear(); batches = []; pendingReviews = []; undo = nil; original = nil; message = nil
      }
    }
    .onDisappear { clear(); batches = []; pendingReviews = []; undo = nil; message = nil }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if scene == .active, notification.object as? String == records.owner {
        retentionDefault = (try? records.load())?.keepsNewImportOriginals
      }
    }
    .onChange(of: mapping) { _ in rows = nil; owned = false; linkedRows = [] }
    .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .json,
      UTType(filenameExtension: "xlsx") ?? .spreadsheet]) { result in
      defer { fileRetention = nil }
      guard scene != .background, let retainOriginal = fileRetention else { return }
      do { try open(result.get(), retainOriginal: retainOriginal) }
      catch { clear(); message = t("workbook_failed", "Could not open this measurement table.") }
    }
    .alert(item: $undo) { batch in
      Alert(title: Text(t("undo", "Undo this batch")),
            message: Text(t("undo_scope", "Only unchanged measurements added by this batch will be removed.")),
            primaryButton: .destructive(Text(t("remove", "Remove")), action: { undoBatch(batch.id) }),
            secondaryButton: .cancel())
    }
    .sheet(item: $original) { selection in
      NavigationView {
        GalaxySSIHealthTableSourceView(records: records, batchID: selection.id)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(t("close_source", "Close")) { original = nil }
            }
          }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func workbookSection(_ workbook: WorkbookInput) -> some View {
    Section(t("worksheet_options", "Worksheet options")) {
      Picker(t("worksheet", "Worksheet"), selection: Binding(get: { sheetID }, set: selectSheet)) {
        ForEach(workbook.contents.sheets) { Text($0.name).tag($0.id) }
      }
      if !headerChoices.isEmpty {
        Picker(t("header", "Header row"), selection: Binding(get: { header }, set: selectHeader)) {
          ForEach(headerChoices, id: \.self) { row in
            Text(String(format: t("sheet_row", "Worksheet row %lld"), Int64(row))).tag(row)
          }
        }
      }
      Toggle(t("formula_cache", "Allow stored formula results; do not calculate formulas"), isOn: $mapping.useFormulaCache)
    }
  }

  private func mappingSection(_ input: Input) -> some View {
    Section(input.name) {
      Text(input.retainOriginal ? t("retention_keep", "Original will be kept")
                                : t("retention_review", "Original will not be kept"))
        .foregroundColor(.secondary)
      Picker(t("metric", "Measurement"), selection: $mapping.metric) {
        ForEach(GalaxySSIHealthMetric.allCases) { Text(metricTitle($0)).tag($0) }
      }
      .onChange(of: mapping.metric) { _ in mapping.unitOverride = nil; mapping.confirmedUnit = false }
      column(mapping.metric == .bloodPressure ? t("systolic", "Systolic") : t("value", "Value"), $mapping.value, input)
      if mapping.metric == .bloodPressure {
        column(t("diastolic", "Diastolic"), $mapping.lower, input)
        column(t("pulse", "Pulse (bpm, optional)"), $mapping.pulse, input)
      }
      column(t("date", "Measurement time"), $mapping.date, input)
      column(t("notes", "Notes (optional)"), $mapping.notes, input)
      Picker(t("date_style", "Date format"), selection: $mapping.dateStyle) {
        Text("ISO 8601").tag(GalaxySSIHealthTableImport.DateStyle.iso)
        Text("yyyy-MM-dd HH:mm:ss").tag(GalaxySSIHealthTableImport.DateStyle.localTime)
        Text("yyyy-MM-dd").tag(GalaxySSIHealthTableImport.DateStyle.day)
        if input.worksheet != nil {
          Text(t("excel_date", "Excel date serial")).tag(GalaxySSIHealthTableImport.DateStyle.excel)
        }
      }
      if mapping.dateStyle != .iso || input.worksheet != nil {
        Picker(t("zone", "Time zone"), selection: $mapping.localZone) {
          Text(TimeZone.current.identifier).tag(TimeZone.current)
          if let utc = TimeZone(identifier: "Etc/UTC"), utc != .current { Text("UTC").tag(utc) }
        }
      }
      Group {
        if mapping.metric.units.count > 1 {
          Picker(t("unit_picker", "Unit"), selection: Binding(
            get: { mapping.unitOverride ?? mapping.metric.unit }, set: { mapping.unitOverride = $0; mapping.confirmedUnit = false })) {
            ForEach(mapping.metric.units, id: \.self) { Text($0).tag($0) }
          }
        }
        let unit = mapping.unitOverride ?? mapping.metric.unit
        Toggle(unit.isEmpty ? t("unitless", "The selected results are unitless") :
          String(format: t("unit", "The selected values use %@"), unit), isOn: $mapping.confirmedUnit)
        if input.table.isoDates?.contains(where: { $0.contains(mapping.date) }) == true {
          Toggle(t("date_only_time", "Set time for date-only cells"), isOn: Binding(
            get: { mapping.dateOnlyMinute != nil }, set: { mapping.dateOnlyMinute = $0 ? 0 : nil }))
          if mapping.dateOnlyMinute != nil {
            Stepper(value: dateOnlyPart(hours: true), in: 0...23) {
              Text(String(format: t("date_only_hour", "Hour: %02lld"), Int64((mapping.dateOnlyMinute ?? 0) / 60)))
            }
            Stepper(value: dateOnlyPart(hours: false), in: 0...59) {
              Text(String(format: t("date_only_minute", "Minute: %02lld"), Int64((mapping.dateOnlyMinute ?? 0) % 60)))
            }
          }
        }
      }
      Button(t("review", "Review rows"), action: prepare)
    }
  }

  private func dateOnlyPart(hours: Bool) -> Binding<Int> {
    Binding(get: {
      let time = mapping.dateOnlyMinute ?? 0
      return hours ? time / 60 : time % 60
    }, set: { value in
      let time = mapping.dateOnlyMinute ?? 0
      mapping.dateOnlyMinute = hours ? value * 60 + time % 60 : time / 60 * 60 + value
    })
  }

  private func review(_ rows: [GalaxySSIHealthTableImport.Row]) -> some View {
    let ready = rows.filter { $0.status == .ready }.count
    return Section(t("review", "Review rows")) {
      ForEach([GalaxySSIHealthTableImport.Status.ready, .duplicate, .missing, .invalid], id: \.self) { state in
        let count = rows.filter { $0.status == state }.count
        Text("\(statusTitle(state)): \(count)")
      }
      ForEach(rows.prefix(limit)) { row in
        VStack(alignment: .leading, spacing: 4) {
          Text(String(format: t("row", "Data row %lld"), Int64(row.id)) + " · " + statusTitle(row.status))
          if let reading = row.reading {
            Text(readingSummary(reading)).foregroundColor(.secondary)
            Text(t("resolved_time", "Resolved time") + ": " + reading.measuredAt.formatted(.iso8601))
              .foregroundColor(.secondary)
            if !reading.notes.isEmpty {
              Text(reading.notes).lineLimit(4).foregroundColor(.secondary)
            }
          } else {
            Text(row.rawValue).lineLimit(2).foregroundColor(.secondary)
          }
          Text(t("source_time", "Source time") + ": " + row.rawDate).lineLimit(2).foregroundColor(.secondary)
          if row.duplicateTarget != nil {
            Toggle(t("link_duplicate", "Link this row to the existing measurement"), isOn: Binding(
              get: { linkedRows.contains(row.id) }, set: {
                owned = false
                if $0 { linkedRows.insert(row.id) } else { linkedRows.remove(row.id) }
              }))
          }
        }
      }
      if rows.count > limit { Button(t("more", "Show more")) { limit += 30 } }
      Toggle(t("owned", "These measurements are mine and I checked values, units and times"), isOn: $owned)
      Button(t("save", "Save valid rows"), action: save).disabled(!owned || (ready == 0 && linkedRows.isEmpty))
    }
  }

  private func readingSummary(_ reading: GalaxySSIHealthReading) -> String {
    func exact(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    let pressure = reading.diastolic.map { "/" + exact($0) } ?? ""
    let pulse = reading.pulse.map { " · " + exact($0) + " bpm" } ?? ""
    return (reading.reported?.raw ?? reading.value.map(exact) ?? "") + pressure +
      (reading.unit.isEmpty ? "" : " " + reading.unit) + pulse
  }

  private func column(_ title: String, _ selection: Binding<Int>, _ input: Input) -> some View {
    Picker(title, selection: selection) {
      Text(t("not_selected", "Not selected")).tag(-1)
      ForEach(input.table.headers.indices, id: \.self) { index in
        Text(String(input.table.headers[index].prefix(120)) + " [\(index + 1)]").tag(index)
      }
    }
  }

  private func chooseFile() {
    guard scene == .active else { return }
    retentionDefault = (try? records.load())?.keepsNewImportOriginals
    let choice = retentionChoice
    guard let retain = choice.wrappedValue.resolve(default: retentionDefault) else { return }
    fileRetention = retain
    choice.wrappedValue = .useDefault
    choosing = true
  }

  private func open(_ url: URL, retainOriginal: Bool) throws {
    clear()
    message = nil
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: GalaxySSIHealthTableImport.maximumBytes + 1) ?? Data()
    try openData(data, name: url.lastPathComponent, retainOriginal: retainOriginal)
  }

  private func openData(_ data: Data, name: String, retainOriginal: Bool) throws {
    let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
    if ext == "xlsx" {
      let contents = try GalaxySSIHealthXLSX(data)
      workbook = WorkbookInput(name: name, data: data, contents: contents, retainOriginal: retainOriginal)
      if let first = contents.sheets.first { selectSheet(first.id) }
      return
    }
    let json = ext == "json"
    input = Input(name: name, data: data, json: json,
                  table: try GalaxySSIHealthTableImport.parse(data, json: json), retainOriginal: retainOriginal)
  }

  private func saveReviewDraft(_ input: Input) {
    guard scene == .active, rows != nil else { return }
    do {
      let draft = GalaxySSIHealthReviewReminders.TableDraft(id: openedReview?.id ?? UUID(),
        name: String(input.name.prefix(180)), at: Date(), data: input.data,
        mapping: mapping, worksheet: input.worksheet, retainOriginal: input.retainOriginal)
      try records.saveTableReview(draft, replacing: openedReview?.version)
      openedReview = draft
      reload()
      message = t("review_draft_saved", "Encrypted review draft saved")
    } catch { message = t("save_failed", "Could not save this batch. Review the rows again.") }
  }

  private func resume(_ draft: GalaxySSIHealthReviewReminders.TableDraft) {
    clear()
    do {
      guard let fresh = try records.load().tableReviews?.first(where: { $0.id == draft.id && $0.version == draft.version })
      else { throw GalaxySSIHealthRecords.Failure.stale }
      try openData(fresh.data, name: fresh.name, retainOriginal: fresh.retainOriginal)
      if let worksheet = draft.worksheet {
        selectSheet(worksheet.sheet)
        selectHeader(worksheet.header)
      }
      guard let input, input.worksheet == draft.worksheet else { throw GalaxySSIHealthTableImport.Failure.mapping }
      mapping = draft.mapping
      openedReview = draft
      prepare()
    } catch { message = t("workbook_failed", "Could not open this measurement table.") }
  }

  private func selectSheet(_ id: String) {
    guard let workbook else { return }
    sheetID = id
    headerChoices = []
    input = nil
    rows = nil
    owned = false
    do {
      headerChoices = Array(try workbook.contents.rows(id).dropLast().prefix(30).map(\.number))
      guard let first = headerChoices.first else { throw GalaxySSIHealthTableImport.Failure.mapping }
      selectHeader(first)
    } catch { message = t("worksheet_failed", "This worksheet could not be read.") }
  }

  private func selectHeader(_ row: Int) {
    guard let workbook else { return }
    header = row
    let selection = GalaxySSIHealthXLSX.Selection(sheet: sheetID, header: row)
    rows = nil
    owned = false
    mapping = .init()
    do {
      input = Input(name: workbook.name, data: workbook.data, json: false,
                    table: try workbook.contents.table(selection), retainOriginal: workbook.retainOriginal,
                    worksheet: selection)
      message = nil
    } catch {
      input = nil
      message = t("worksheet_failed", "This worksheet could not be read.")
    }
  }

  private func prepare() {
    guard scene == .active, let input else { return }
    rows = nil
    linkedRows = []
    owned = false
    message = nil
    limit = 30
    do { rows = try GalaxySSIHealthTableImport.preview(input.table, mapping: mapping, current: records.load().current) }
    catch { message = t("mapping_failed", "Select distinct columns and confirm the unit.") }
  }

  private func save() {
    guard scene == .active, owned, let input, let rows else { return }
    do {
      let targets = Dictionary(rows.compactMap { row in
        linkedRows.contains(row.id) ? row.duplicateTarget.map { (row.id, $0) } : nil
      }, uniquingKeysWith: { first, _ in first })
      let count = try records.importTable(input.data, name: input.name, json: input.json,
                                          mapping: mapping, expected: rows.map(\.status), worksheet: input.worksheet,
                                          retainOriginal: input.retainOriginal,
                                          linkDuplicates: targets, reviewVersion: openedReview?.version)
      clear()
      reload()
      message = String(format: t("saved", "%lld measurements saved"), Int64(count))
      if !targets.isEmpty {
        message = (message ?? "") + " · " + String(format: t("linked", "%lld source links"), Int64(targets.count))
      }
    } catch {
      prepare()
      message = t("save_failed", "Could not save this batch. Review the rows again.")
    }
  }

  private func undoBatch(_ id: UUID) {
    guard scene == .active else { return }
    do {
      let count = try records.undoTableBatch(id)
      reload()
      rows = nil
      owned = false
      message = String(format: t("undone", "%lld measurements removed"), Int64(count))
    } catch { message = t("undo_failed", "Could not undo this batch.") }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      batches = archive.tableBatches ?? []
      retentionDefault = archive.keepsNewImportOriginals
      pendingReviews = (archive.tableReviews ?? []).sorted { ($0.at, $0.id.uuidString) > ($1.at, $1.id.uuidString) }
      if !initialRouteOpened, let resumeReviewID {
        initialRouteOpened = true
        if let draft = pendingReviews.first(where: { $0.id == resumeReviewID && $0.version == resumeReviewVersion }) {
          resume(draft)
        }
        else { message = t("save_failed", "Could not save this batch. Review the rows again.") }
      }
    } catch {
      batches = []
      pendingReviews = []
      retentionDefault = nil
      message = t("read_failed", "Could not open this CSV or JSON table.")
    }
  }

  private func clear() {
    input = nil; rows = nil; owned = false; mapping = .init()
    workbook = nil; sheetID = ""; header = 0; headerChoices = []
    linkedRows = []
    openedReview = nil
  }
  private func statusTitle(_ status: GalaxySSIHealthTableImport.Status) -> String {
    switch status {
    case .ready: return t("ready", "Ready")
    case .duplicate: return t("duplicate", "Duplicate")
    case .missing: return t("missing", "Missing")
    case .invalid: return t("invalid", "Invalid")
    }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    metric.title(language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table." + key, fallback: fallback, language: language)
  }
}
