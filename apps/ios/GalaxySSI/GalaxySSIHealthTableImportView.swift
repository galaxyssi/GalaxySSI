import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct GalaxySSIHealthTableImportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var choosing = false
  @State private var input: Input?
  @State private var mapping = GalaxySSIHealthTableImport.Mapping()
  @State private var rows: [GalaxySSIHealthTableImport.Row]?
  @State private var batches: [GalaxySSIHealthTableImport.Batch] = []
  @State private var owned = false
  @State private var limit = 30
  @State private var undo: GalaxySSIHealthTableImport.Batch?
  @State private var message: String?
  @State private var original: OriginalSelection?

  private struct OriginalSelection: Identifiable { let id: UUID }

  private struct Input {
    let name: String
    let data: Data
    let json: Bool
    let table: GalaxySSIHealthTableImport.Table
  }

  var body: some View {
    List {
      if scene == .active {
        Button { choosing = true } label: {
          Label(t("choose", "Choose CSV or JSON"), systemImage: "folder")
        }
        if let input {
          mappingSection(input)
          if let rows { review(rows) }
        }
        if let message { Text(message).foregroundColor(.secondary) }
        if !batches.isEmpty {
          Section(t("history", "Imported batches")) {
            ForEach(batches) { batch in
              VStack(alignment: .leading, spacing: 4) {
                Text(batch.name)
                Text(batch.at, style: .date).foregroundColor(.secondary)
                Text(String(format: t("saved", "%lld measurements saved"), Int64(batch.inserted)))
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
      else if phase == .background { clear(); batches = []; undo = nil; original = nil; message = nil }
    }
    .onDisappear { clear(); batches = []; undo = nil; message = nil }
    .onChange(of: mapping) { _ in rows = nil; owned = false }
    .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .json]) { result in
      guard scene != .background else { return }
      do { try open(result.get()) }
      catch { clear(); message = t("read_failed", "Could not open this CSV or JSON table.") }
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

  private func mappingSection(_ input: Input) -> some View {
    Section(input.name) {
      Picker(t("metric", "Measurement"), selection: $mapping.metric) {
        ForEach(GalaxySSIHealthMetric.allCases) { Text(metricTitle($0)).tag($0) }
      }
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
      }
      if mapping.dateStyle != .iso {
        Picker(t("zone", "Time zone"), selection: $mapping.localZone) {
          Text(TimeZone.current.identifier).tag(TimeZone.current)
          if let utc = TimeZone(identifier: "Etc/UTC"), utc != .current { Text("UTC").tag(utc) }
        }
      }
      Toggle(String(format: t("unit", "The selected values use %@"), mapping.metric.unit), isOn: $mapping.confirmedUnit)
        .onChange(of: mapping.metric) { _ in mapping.confirmedUnit = false }
      Button(t("review", "Review rows"), action: prepare)
    }
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
        }
      }
      if rows.count > limit { Button(t("more", "Show more")) { limit += 30 } }
      Toggle(t("owned", "These measurements are mine and I checked values, units and times"), isOn: $owned)
      Button(t("save", "Save valid rows"), action: save).disabled(!owned || ready == 0)
    }
  }

  private func readingSummary(_ reading: GalaxySSIHealthReading) -> String {
    func exact(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    let pressure = reading.diastolic.map { "/" + exact($0) } ?? ""
    let pulse = reading.pulse.map { " · " + exact($0) + " bpm" } ?? ""
    return exact(reading.value) + pressure + " " + reading.metric.unit + pulse
  }

  private func column(_ title: String, _ selection: Binding<Int>, _ input: Input) -> some View {
    Picker(title, selection: selection) {
      Text(t("not_selected", "Not selected")).tag(-1)
      ForEach(input.table.headers.indices, id: \.self) { index in
        Text(String(input.table.headers[index].prefix(120)) + " [\(index + 1)]").tag(index)
      }
    }
  }

  private func open(_ url: URL) throws {
    clear()
    message = nil
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let data = try file.read(upToCount: GalaxySSIHealthTableImport.maximumBytes + 1) ?? Data()
    let json = url.pathExtension.lowercased() == "json"
    input = Input(name: url.lastPathComponent, data: data, json: json,
                  table: try GalaxySSIHealthTableImport.parse(data, json: json))
  }

  private func prepare() {
    guard scene == .active, let input else { return }
    rows = nil
    owned = false
    message = nil
    limit = 30
    do { rows = try GalaxySSIHealthTableImport.preview(input.table, mapping: mapping, current: records.load().current) }
    catch { message = t("mapping_failed", "Select distinct columns and confirm the unit.") }
  }

  private func save() {
    guard scene == .active, owned, let input, let rows else { return }
    do {
      let count = try records.importTable(input.data, name: input.name, json: input.json,
                                          mapping: mapping, expected: rows.map(\.status))
      clear()
      reload()
      message = String(format: t("saved", "%lld measurements saved"), Int64(count))
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
    do { batches = try records.load().tableBatches ?? [] }
    catch { batches = []; message = t("read_failed", "Could not open this CSV or JSON table.") }
  }

  private func clear() { input = nil; rows = nil; owned = false; mapping = .init() }
  private func statusTitle(_ status: GalaxySSIHealthTableImport.Status) -> String {
    switch status {
    case .ready: return t("ready", "Ready")
    case .duplicate: return t("duplicate", "Duplicate")
    case .missing: return t("missing", "Missing")
    case .invalid: return t("invalid", "Invalid")
    }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    let label: (String, String)
    switch metric {
    case .bloodPressure: label = ("blood_pressure", "Blood pressure")
    case .glucose: label = ("glucose", "Blood glucose")
    case .weight: label = ("weight", "Weight")
    case .heartRate: label = ("heart_rate", "Heart rate")
    }
    return GalaxySSILocalization.string("galaxyssi.health." + label.0, fallback: label.1, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.table." + key, fallback: fallback, language: language)
  }
}
