import SwiftUI

@MainActor
struct GalaxySSIHealthCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  @State private var archive: GalaxySSIHealthRecords.Archive?
  @State private var editor: GalaxySSIHealthDraft?
  @State private var alert: Notice?
  @State private var limit = 30

  private enum Notice: String, Identifiable {
    case unavailable, invalid, stale, duplicate, delete, discardDraft
    var id: String { rawValue }
  }

  var body: some View {
    List {
      if scenePhase == .active, let archive {
        let current = archive.current
        Section {
          if let draft = archive.draft {
            Button { editor = draft } label: {
              Label(t("resume_draft", "Resume draft"), systemImage: "doc.text")
            }
          } else {
            Button { editor = GalaxySSIHealthDraft() } label: {
              Label(t("manual", "Record measurement"), systemImage: "plus.circle")
            }
          }
        }
        Section(t("recent", "Recent measurements")) {
          if current.isEmpty {
            Text(t("empty", "No measurements yet")).foregroundColor(.secondary)
          }
          ForEach(current.prefix(limit)) { reading in
            Button { edit(reading) } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(title(reading.metric)).foregroundColor(.primary)
                Text(summary(reading))
                Text(reading.measuredAt, style: .date).foregroundColor(.secondary)
              }
            }
            .disabled(archive.draft != nil)
          }
          if current.count > limit {
            Button(t("more", "Show more")) { limit += 30 }
          }
        }
      } else if scenePhase == .active {
        Text(t("unavailable", "Health records could not be accessed."))
        Button(t("retry", "Reload records"), action: reload)
      }
      NavigationLink {
        GalaxySSIWeeklyHealthReportView(records: records)
      } label: {
        Label(t("weekly.title", "Weekly Health Report"), systemImage: "calendar")
      }
    }
    .navigationTitle(t("title", "Health Center"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { if scenePhase == .active { reload() } }
    .onChange(of: scenePhase) { phase in
      if phase == .active { reload() } else {
        editor = nil
        alert = nil
        archive = nil
      }
    }
    .sheet(item: $editor) { _ in
      NavigationView { editorForm }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
        .alert(item: $alert, content: editorAlert)
    }
  }

  private func editorAlert(_ notice: Notice) -> Alert {
      switch notice {
      case .duplicate:
        return Alert(title: Text(t("duplicate", "A matching measurement already exists")),
                     primaryButton: .default(Text(t("save_duplicate", "Save separately"))) { save(allowDuplicate: true) },
                     secondaryButton: .cancel())
      case .delete:
        return Alert(title: Text(t("delete", "Remove measurement?")),
                     message: Text(t("delete_note", "The encrypted revision history is retained.")),
                     primaryButton: .destructive(Text(t("remove", "Remove"))) { save(deleted: true) },
                     secondaryButton: .cancel())
      case .discardDraft:
        return Alert(title: Text(t("discard_draft", "Discard draft?")),
                     primaryButton: .destructive(Text(t("remove", "Remove")), action: discardDraft),
                     secondaryButton: .cancel())
      case .invalid:
        return Alert(title: Text(t("invalid", "Check the measurement values and field lengths.")))
      case .stale:
        return Alert(title: Text(t("stale", "This measurement changed. Reopen it before editing.")))
      case .unavailable:
        return Alert(title: Text(t("unavailable", "Health records could not be accessed.")))
      }
  }

  private var editorForm: some View {
    Form {
      if let draft = editor, scenePhase == .active {
        Picker(t("metric", "Measurement"), selection: field(\.metric, .bloodPressure)) {
          ForEach(GalaxySSIHealthMetric.allCases) { metric in Text(title(metric)).tag(metric) }
        }
        .disabled(draft.existing != nil)
        TextField(draft.metric == .bloodPressure ? t("systolic", "Systolic (mmHg)") : draft.metric.unit,
                  text: field(\.value, "")).keyboardType(.decimalPad)
        if draft.metric == .bloodPressure {
          TextField(t("diastolic", "Diastolic (mmHg)"), text: field(\.diastolic, "")).keyboardType(.decimalPad)
          TextField(t("pulse", "Pulse (bpm, optional)"), text: field(\.pulse, "")).keyboardType(.decimalPad)
        }
        DatePicker(t("time", "Measured at"), selection: field(\.measuredAt, Date()), in: ...Date())
        TextField(t("conditions", "Conditions"), text: field(\.conditions, ""))
        TextField(t("notes", "Notes"), text: field(\.notes, ""))
        Button(t("save_draft", "Save draft"), action: saveDraft)
        if archive?.draft?.id == draft.id {
          Button(t("discard", "Discard draft"), role: .destructive) { alert = .discardDraft }
        }
        if let existing = draft.existing, let archive {
          Section(t("history", "Revision history")) {
            ForEach(Array(archive.revisions.filter { $0.id == existing.id }.suffix(50).reversed()),
                    id: \.revision) { revision in
              Text("\(revision.revision) · \(summary(revision))")
            }
          }
          Button(t("remove", "Remove"), role: .destructive) { alert = .delete }
        }
      }
    }
    .navigationTitle(t("manual", "Record measurement"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(t("cancel", "Cancel")) { editor = nil }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(t("save", "Save")) { save() }
      }
    }
  }

  private func field<Value>(_ key: WritableKeyPath<GalaxySSIHealthDraft, Value>, _ fallback: Value) -> Binding<Value> {
    Binding(get: { editor?[keyPath: key] ?? fallback }, set: { editor?[keyPath: key] = $0 })
  }

  private func edit(_ reading: GalaxySSIHealthReading) {
    editor = GalaxySSIHealthDraft(existing: reading, metric: reading.metric, measuredAt: reading.measuredAt,
                    value: number(reading.value), diastolic: reading.diastolic.map(number) ?? "",
                    pulse: reading.pulse.map(number) ?? "", conditions: reading.conditions, notes: reading.notes)
  }

  private func save(allowDuplicate: Bool = false, deleted: Bool = false) {
    guard scenePhase == .active, let draft = editor else { return }
    do {
      if deleted, var existing = draft.existing {
        existing.deleted = true
        try records.write(existing, draftId: draft.id)
      } else {
        guard let value = parse(draft.value) else { throw GalaxySSIHealthRecords.Failure.invalid }
        let pressure = draft.metric == .bloodPressure
        let pulse = pressure ? parse(draft.pulse) : nil
        if pressure && !draft.pulse.trimmingCharacters(in: .whitespaces).isEmpty && pulse == nil {
          throw GalaxySSIHealthRecords.Failure.invalid
        }
        var reading = draft.existing ?? GalaxySSIHealthReading(metric: draft.metric, value: value)
        reading.measuredAt = draft.measuredAt
        reading.value = value
        reading.diastolic = pressure ? parse(draft.diastolic) : nil
        reading.pulse = pulse
        reading.conditions = draft.conditions
        reading.notes = draft.notes
        try records.write(reading, allowDuplicate: allowDuplicate, draftId: draft.id)
      }
      editor = nil
      reload()
    } catch GalaxySSIHealthRecords.Failure.duplicate { alert = .duplicate }
      catch GalaxySSIHealthRecords.Failure.invalid { alert = .invalid }
      catch GalaxySSIHealthRecords.Failure.stale { alert = .stale }
      catch { alert = .unavailable }
  }

  private func saveDraft() {
    guard scenePhase == .active, let editor else { return }
    do {
      try records.storeDraft(editor)
      self.editor = nil
      reload()
    } catch GalaxySSIHealthRecords.Failure.invalid { alert = .invalid }
      catch { alert = .unavailable }
  }

  private func discardDraft() {
    guard scenePhase == .active, let editor else { return }
    do {
      try records.discardDraft(id: editor.id)
      self.editor = nil
      reload()
    } catch { alert = .unavailable }
  }

  private func reload() {
    do { archive = try records.load() }
    catch { archive = nil }
  }

  private func parse(_ text: String) -> Decimal? {
    try? Decimal(text.trimmingCharacters(in: .whitespaces), format: .number.locale(locale), lenient: false)
  }

  private func number(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).description(withLocale: locale)
  }

  private func summary(_ reading: GalaxySSIHealthReading) -> String {
    let value = number(reading.value) + (reading.diastolic.map { "/" + number($0) } ?? "")
    return value + " " + reading.metric.unit + (reading.pulse.map { " · " + number($0) + " bpm" } ?? "")
  }

  private func title(_ metric: GalaxySSIHealthMetric) -> String {
    switch metric {
    case .bloodPressure: return t("blood_pressure", "Blood pressure")
    case .glucose: return t("glucose", "Blood glucose")
    case .weight: return t("weight", "Weight")
    case .heartRate: return t("heart_rate", "Heart rate")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
