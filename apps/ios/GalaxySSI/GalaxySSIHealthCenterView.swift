import CoreBluetooth
import HealthKit
import SwiftUI

@MainActor
struct GalaxySSIHealthCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  @State private var archive: GalaxySSIHealthRecords.Archive?
  @State private var editor: GalaxySSIHealthDraft?
  @State private var alert: Notice?
  @State private var limit = 30
  @State private var overviewPermissionFailed = false
  @State private var privacySaveFailed = false
  @State private var privacyLimit = 20

  private enum Notice: String, Identifiable {
    case unavailable, invalid, stale, duplicate, delete, discardDraft
    var id: String { rawValue }
  }

  var body: some View {
    List {
      Section {
        if scenePhase == .active, let archive {
          if archive.current.isEmpty {
            Label(t("first_use.title", "No confirmed measurements yet"), systemImage: "heart.text.square")
              .font(.headline)
          }
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
        NavigationLink {
          GalaxySSIHealthImportView(store: GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets),
                                    records: records)
        } label: {
          Label(t("import.title", "Import Health Data"), systemImage: "square.and.arrow.down")
        }
      }
      NavigationLink {
        GalaxySSIHealthBodyView { bloodPressureRecords }
      } label: {
        Label(GalaxySSIHealthBodyText.string("title", language: language), systemImage: "figure.stand")
      }
      Section {
        NavigationLink {
          sourceOverview
        } label: {
          Label(t("sources", "Devices & Data Sources"), systemImage: "externaldrive.connected.to.line.below")
        }
        NavigationLink {
          GalaxySSIHealthOriginalsView(store: GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets))
        } label: {
          Label(t("originals.title", "Health Originals"), systemImage: "doc.on.doc")
        }
        NavigationLink {
          GalaxySSIHealthPDFTextView(store: GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets))
        } label: {
          Label(t("pdf_text.title", "Report PDF Text"), systemImage: "doc.text.magnifyingglass")
        }
        NavigationLink {
          GalaxySSIHealthProfileView(records: records)
        } label: {
          Label(t("profile.title", "Health Profile"), systemImage: "person.text.rectangle")
        }
        NavigationLink {
          GalaxySSIHealthReportCropView(store: GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets))
        } label: {
          Label(t("report_crop.title", "Report Crop Preview"), systemImage: "crop")
        }
      }
      if scenePhase == .active, let archive {
        let current = archive.current
        if !current.isEmpty {
          Section(t("overview", "Measurement overview")) {
            Toggle(t("derive_overview", "Show local measurement summary"), isOn: Binding(
              get: { self.archive?.derivesOverview == true }, set: setOverviewPermission))
            if overviewPermissionFailed {
              Text(t("overview_permission_error", "Could not update the summary setting."))
                .foregroundColor(.secondary)
            }
            if archive.derivesOverview == true {
              TimelineView(.everyMinute) { context in
                overview(current, now: context.date)
              }
            }
          }
          Section(t("recent", "Recent measurements")) {
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
        }
      } else if scenePhase == .active {
        Text(t("unavailable", "Health records could not be accessed."))
        Button(t("retry", "Reload records"), action: reload)
      }
      NavigationLink {
        GalaxySSIHealthMeasurementExportView(records: records)
      } label: {
        Label(t("export.title", "Export Measurements"), systemImage: "square.and.arrow.up")
      }
      NavigationLink {
        GalaxySSIWeeklyHealthReportView(records: records)
      } label: {
        Label(t("weekly.title", "Weekly Health Report"), systemImage: "calendar")
      }
      NavigationLink {
        privacyOverview
      } label: {
        Label(t("privacy.title", "Health Privacy"), systemImage: "lock.shield")
      }
      NavigationLink {
        GalaxySSIHealthBackupView(records: records, originals:
          GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets))
      } label: {
        Label(t("backup.title", "Health Backup"), systemImage: "externaldrive")
      }
      NavigationLink {
        GalaxySSIHealthTrendView(records: records)
      } label: {
        Label(t("trend.title", "Measurement Trends"), systemImage: "chart.xyaxis.line")
      }
      NavigationLink {
        GalaxySSIHealthMetricCatalogView(records: records, add: { metric in
          if let draft = archive?.draft { editor = draft }
          else { editor = GalaxySSIHealthDraft(metric: metric) }
        }, edit: edit)
      } label: {
        Label(t("catalog.title", "Measurement Catalog"), systemImage: "list.bullet.rectangle")
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
        overviewPermissionFailed = false
        privacySaveFailed = false
        privacyLimit = 20
      }
    }
    .sheet(item: $editor) { _ in
      NavigationView { editorForm }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
        .alert(item: $alert, content: editorAlert)
    }
  }

  private var privacyOverview: some View {
    List {
      if scenePhase == .active, let archive {
        Section(t("privacy.local", "Local analysis")) {
          Toggle(t("derive_overview", "Show local measurement summary"), isOn: Binding(
            get: { self.archive?.derivesOverview == true }, set: { changePrivacy(.overview, enabled: $0) }))
          Toggle(t("weekly.permission", "Allow local weekly reports"), isOn: Binding(
            get: { self.archive?.weeklyReportAllowed == true }, set: { changePrivacy(.weeklyReport, enabled: $0) }))
          if privacySaveFailed {
            Text(t("privacy.failed", "The permission change was not saved.")).foregroundColor(.secondary)
          }
        }
        Section(t("privacy.history", "Permission history")) {
          let events = archive.privacyEvents ?? []
          if events.isEmpty { Text(t("privacy.empty", "No permission changes")).foregroundColor(.secondary) }
          ForEach(events.reversed().prefix(privacyLimit)) { event in
            VStack(alignment: .leading, spacing: 4) {
              Text(event.scope == .overview ? t("overview", "Measurement overview") : t("weekly.title", "Weekly Health Report"))
              Text(event.enabled ? t("privacy.allowed", "Allowed") : t("privacy.revoked", "Revoked"))
                .foregroundColor(.secondary)
              Text(event.at, style: .date).foregroundColor(.secondary)
              Text(event.at, style: .time).foregroundColor(.secondary)
            }
          }
          if events.count > privacyLimit { Button(t("more", "Show more")) { privacyLimit += 20 } }
        }
        Section(t("privacy.export_history", "PDF export requests")) {
          let requests = Array((archive.weeklyExportRequests ?? []).reversed())
          if requests.isEmpty { Text(t("privacy.no_exports", "No PDF export requests")).foregroundColor(.secondary) }
          ForEach(Array(requests.prefix(privacyLimit).enumerated()), id: \.offset) { entry in
            let request = entry.element
            VStack(alignment: .leading, spacing: 4) {
              Text(t("privacy.export_prepared", "Prepared for export"))
              Text(request.includeRows ? t("privacy.export_values", "Includes measurement values")
                : t("privacy.export_counts", "Counts only")).foregroundColor(.secondary)
              Text(request.at, style: .date).foregroundColor(.secondary)
              Text(request.at, style: .time).foregroundColor(.secondary)
            }
          }
          if requests.count > privacyLimit { Button(t("more", "Show more")) { privacyLimit += 20 } }
        }
        if let events = archive.bluetoothErasureLog, !events.isEmpty {
          Section(t("privacy.bluetooth_erasure", "Bluetooth history erasures")) {
            ForEach(events.reversed().prefix(privacyLimit)) { event in
              VStack(alignment: .leading, spacing: 4) {
                Text(String(format: t("bluetooth_history.erased", "%lld saved measurements erased"), Int64(event.records)))
                Text(event.at, style: .date).foregroundColor(.secondary)
              }
            }
            if events.count > privacyLimit { Button(t("more", "Show more")) { privacyLimit += 20 } }
          }
        }
      } else if scenePhase == .active {
        Text(t("unavailable", "Health records could not be accessed."))
        Button(t("retry", "Reload records"), action: reload)
      }
    }
    .navigationTitle(t("privacy.title", "Health Privacy"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
  }

  private func changePrivacy(_ scope: GalaxySSIHealthRecords.PrivacyScope, enabled: Bool) {
    guard scenePhase == .active else { return }
    do {
      try records.setPrivacy(scope, enabled: enabled)
      privacySaveFailed = false
      reload()
    } catch { privacySaveFailed = true }
  }

  private var bloodPressureRecords: some View {
    List {
      if scenePhase == .active, let archive {
        let pressure = archive.current.filter { $0.metric == .bloodPressure }
        if pressure.isEmpty { Text(t("empty", "No measurements yet")) }
        ForEach(pressure.prefix(limit)) { reading in
          Button { edit(reading) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(summary(reading))
              Text(reading.measuredAt, style: .date).foregroundColor(.secondary)
            }
          }
          .disabled(archive.draft != nil)
        }
        if pressure.count > limit { Button(t("more", "Show more")) { limit += 30 } }
        if archive.draft == nil {
          Button(t("manual", "Record measurement")) { editor = GalaxySSIHealthDraft(metric: .bloodPressure) }
        }
      }
    }
    .navigationTitle(t("blood_pressure", "Blood pressure"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var sourceOverview: some View {
    List {
      if scenePhase == .active {
        Section(t("device_sources", "Device sources")) {
          sourceStatus("HealthKit", detail: HKHealthStore.isHealthDataAvailable()
            ? t("platform_available", "Available on this device")
            : t("platform_unavailable", "Not available on this device"))
          sourceStatus(t("bluetooth_devices", "Bluetooth devices"), detail: bluetoothAuthorization)
          NavigationLink {
            GalaxySSIHealthBluetoothView(records: records)
          } label: {
            Label(t("bluetooth.title", "Bluetooth Blood Pressure"), systemImage: "waveform.path.ecg")
          }
          NavigationLink {
            GalaxySSIHealthBluetoothHistoryView(records: records)
          } label: {
            Label(t("bluetooth_history.title", "Saved Bluetooth Devices"), systemImage: "clock.arrow.circlepath")
          }
        }
        Section(t("local_sources", "On this device")) {
          if let archive {
            let current = archive.current
            HStack {
              Text(t("confirmed_count", "Confirmed measurements"))
              Spacer()
              Text(current.count.formatted(.number.locale(locale))).foregroundColor(.secondary)
            }
            if let latest = current.first(where: { $0.bluetoothReceipt == nil && $0.tableSource == nil }) {
              VStack(alignment: .leading, spacing: 4) {
                Text(t("latest_manual", "Latest manual measurement"))
                Text(title(latest.metric)).foregroundColor(.secondary)
                Text(latest.measuredAt.formatted(date: .abbreviated, time: .shortened))
                  .foregroundColor(.secondary)
              }
            }
            Button(archive.draft == nil ? t("manual", "Record measurement") : t("resume_draft", "Resume draft")) {
              editor = archive.draft ?? GalaxySSIHealthDraft()
            }
          } else {
            Text(t("unavailable", "Health records could not be accessed."))
            Button(t("retry", "Reload records"), action: reload)
          }
        }
      }
    }
    .navigationTitle(t("sources", "Devices & Data Sources"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func overview(_ current: [GalaxySSIHealthReading], now: Date) -> some View {
    var local = calendar
    local.timeZone = timeZone
    let overview = GalaxySSIHealthOverview(current: current, now: now, calendar: local)
    return VStack(alignment: .leading, spacing: 12) {
      Text(String(format: t("coverage", "%lld of %lld tracked metrics recorded in the last 7 days"),
                  locale: locale, Int64(overview.recentCount), Int64(overview.metrics.count)))
        .font(.footnote).foregroundColor(.secondary)
      ForEach(overview.metrics) { item in
        if let reading = item.reading {
          Button { edit(reading) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(title(item.metric)).foregroundColor(.primary)
              Text(summary(reading))
              Text(item.freshness == .recent ? t("fresh", "Recent") : t("stale_reading", "Older"))
                .foregroundColor(.secondary)
              Text(reading.tableSource != nil ? t("table.source", "Imported table") :
                (reading.bluetoothReceipt == nil ? t("manual_source", "Entered manually") :
                  t("bluetooth.source", "Bluetooth monitor"))).foregroundColor(.secondary)
              Text(reading.measuredAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundColor(.secondary)
            }
          }
          .buttonStyle(.borderless)
          .disabled(archive?.draft != nil)
        } else {
          VStack(alignment: .leading, spacing: 4) {
            Text(title(item.metric))
            Text(t("missing_reading", "Not recorded")).foregroundColor(.secondary)
          }
        }
      }
    }
  }

  private func sourceStatus(_ name: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(name)
      Text(detail).foregroundColor(.secondary)
      Text(t("source_not_connected", "Not connected to Health Center")).foregroundColor(.secondary)
    }
  }

  private var bluetoothAuthorization: String {
    switch CBManager.authorization {
    case .allowedAlways: return t("bluetooth_allowed", "System Bluetooth permission granted")
    case .denied, .restricted: return t("bluetooth_denied", "System Bluetooth permission unavailable")
    case .notDetermined: return t("bluetooth_not_requested", "System Bluetooth permission not requested")
    @unknown default: return t("bluetooth_unknown", "System Bluetooth permission unknown")
    }
  }

  private func setOverviewPermission(_ enabled: Bool) {
    guard scenePhase == .active else { return }
    do {
      try records.setOverviewPermission(enabled)
      overviewPermissionFailed = false
      reload()
    } catch {
      overviewPermissionFailed = true
      if !enabled { archive?.derivesOverview = false }
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
        Picker(t("metric", "Measurement"), selection: Binding(
          get: { editor?.metric ?? .bloodPressure }, set: { editor?.metric = $0; editor?.unitOverride = nil })) {
          ForEach(GalaxySSIHealthMetric.allCases) { metric in Text(title(metric)).tag(metric) }
        }
        .disabled(draft.existing != nil)
        let qualitative = GalaxySSIHealthReportedResult.parse(draft.value, metric: draft.metric)?.kind == .qualitative
        if draft.metric.units.count > 1 && !qualitative {
          Picker(t("catalog.unit", "Unit"), selection: Binding(
            get: { editor?.unitOverride ?? draft.metric.unit }, set: { editor?.unitOverride = $0 })) {
            ForEach(draft.metric.units, id: \.self) { Text($0).tag($0) }
          }
          .disabled(draft.existing?.bluetoothReceipt != nil || draft.existing?.tableSource != nil)
        }
        let unit = draft.unitOverride ?? draft.metric.unit
        TextField(draft.metric == .bloodPressure ? t("catalog.systolic", "Systolic") + " (" + unit + ")" :
                    t("catalog.result", "Reported value"),
                  text: field(\.value, "")).keyboardType(draft.metric.laboratory ? .default : .decimalPad)
        if draft.metric == .bloodPressure {
          TextField(t("catalog.diastolic", "Diastolic") + " (" + unit + ")",
                    text: field(\.diastolic, "")).keyboardType(.decimalPad)
          TextField(t("pulse", "Pulse (bpm, optional)"), text: field(\.pulse, "")).keyboardType(.decimalPad)
        }
        if draft.metric.laboratory {
          TextField(t("catalog.reference", "Report reference interval (optional)"), text: Binding(
            get: { editor?.referenceInterval ?? "" }, set: { editor?.referenceInterval = $0 }))
        }
        Group {
          DatePicker(t("time", "Measured at"), selection: field(\.measuredAt, Date()), in: ...Date())
          TextField(t("conditions", "Conditions"), text: field(\.conditions, ""))
          TextField(t("notes", "Notes"), text: field(\.notes, ""))
        }
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
                    value: reading.reported?.raw ?? reading.reportedNotation ?? reading.value.map(number) ?? "",
                    diastolic: reading.diastolic.map(number) ?? "", pulse: reading.pulse.map(number) ?? "",
                    conditions: reading.conditions, notes: reading.notes, unitOverride: reading.unitOverride,
                    referenceInterval: reading.referenceInterval)
  }

  private func save(allowDuplicate: Bool = false, deleted: Bool = false) {
    guard scenePhase == .active, let draft = editor else { return }
    do {
      if deleted, var existing = draft.existing {
        existing.deleted = true
        try records.write(existing, draftId: draft.id)
      } else {
        let reported = GalaxySSIHealthReportedResult.parse(draft.value, metric: draft.metric)
        let value = reported == nil ? GalaxySSIHealthReportedResult.number(draft.value) : nil
        guard value != nil || reported != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
        let pressure = draft.metric == .bloodPressure
        let pulse = pressure ? parse(draft.pulse) : nil
        if pressure && !draft.pulse.trimmingCharacters(in: .whitespaces).isEmpty && pulse == nil {
          throw GalaxySSIHealthRecords.Failure.invalid
        }
        var reading = draft.existing ?? GalaxySSIHealthReading(metric: draft.metric, value: value)
        reading.measuredAt = draft.measuredAt
        reading.value = value
        reading.reported = reported
        reading.reportedNotation = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
        reading.unitOverride = reported?.kind == .qualitative ? "" :
          (draft.unitOverride?.isEmpty == false ? draft.unitOverride : nil)
        reading.referenceInterval = draft.metric.laboratory ? draft.referenceInterval : nil
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
    guard scenePhase == .active else { return }
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
    let value = (reading.reported?.raw ?? reading.value.map(number) ?? "") +
      (reading.diastolic.map { "/" + number($0) } ?? "")
    return value + (reading.unit.isEmpty ? "" : " " + reading.unit) +
      (reading.pulse.map { " · " + number($0) + " bpm" } ?? "")
  }

  private func title(_ metric: GalaxySSIHealthMetric) -> String {
    metric.title(language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
