import CoreBluetooth
import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.locale) private var locale
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.sizeCategory) private var sizeCategory
  let records: GalaxySSIHealthRecords
  @State private var archive: GalaxySSIHealthRecords.Archive?
  @State private var editor: GalaxySSIHealthDraft?
  @State private var resumeDeletionOnForeground = false
  @State private var alert: Notice?
  @State private var limit = 30
  @State private var overviewPermissionFailed = false
  @State private var privacySaveFailed = false
  @State private var privacyLimit = 20
  @State private var sourceAttention: [GalaxySSIHealthSourceAttention.Incident] = []
  @State private var sourceCoverage: GalaxySSIHealthSourceAttention?
  @State private var sourceAttentionUnavailable = false
  @State private var initialRecordMetric: GalaxySSIHealthMetric?
  @State private var initialRecordID: UUID?
  @State private var overviewDestination: OverviewDestination?
  @State private var overviewNotice: Notice?

  private enum OverviewDestination: String, Identifiable {
    case weekly, assistant, files, sleep, reviews, records, devices, originals, pdf, profile, crop
    case export, privacy, backup, trends, catalog, recording, body, imports, photo
    var id: String { rawValue }
  }

  init(records: GalaxySSIHealthRecords, initialRecordMetric: GalaxySSIHealthMetric? = nil, initialRecordID: UUID? = nil) {
    self.records = records
    _initialRecordMetric = State(initialValue: initialRecordMetric)
    _initialRecordID = State(initialValue: initialRecordID)
  }
  @State private var sourceRecovery: GalaxySSIHealthSourceAttention.Incident?

  private enum Notice: String, Identifiable {
    case unavailable, invalid, stale, duplicate, delete, discardDraft, undoConflict
    var id: String { rawValue }
  }

  var body: some View {
    List {
      if scenePhase == .active, let archive {
        if archive.current.isEmpty {
          Section {
            Label(t("first_use.title", "No confirmed measurements yet"), systemImage: "heart.text.square")
              .font(.headline)
            Button { overviewDestination = .profile } label: {
              Label(t("profile.title", "Health Profile"), systemImage: "person.text.rectangle")
            }
            Button { overviewDestination = .devices } label: {
              Label(t("sources", "Devices & Data Sources"), systemImage: "externaldrive.connected.to.line.below")
            }
          }
        } else {
          Section {
              TimelineView(.everyMinute) { context in
                overview(archive, now: context.date)
              }
          } header: {
            HStack {
              Text(t("overview_list.heading", "Measurements"))
              Spacer()
              Button(t("overview_list.view_all", "View all")) { overviewDestination = .catalog }
                .textCase(nil)
              }
          }
        }
        GalaxySSIHealthOverviewCareSection(records: records)
      } else if scenePhase == .active {
        Text(t("unavailable", "Health records could not be accessed."))
        Button(t("retry", "Reload records"), action: reload)
      }
    }
    .listStyle(.plain)
    .privacySensitive()
    .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
    .alert(item: $overviewNotice, content: editorAlert)
    .navigationTitle(t("title", "Health Center"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
      Menu {
        overviewMenu
        Button { overviewDestination = .weekly } label: { Label(t("weekly.title", "Weekly Health Report"), systemImage: "calendar") }
        Button { overviewDestination = .assistant } label: { Label(t("assistant.title", "Health Assistant"), systemImage: "chart.bar.xaxis") }
        Button { overviewDestination = .files } label: { Label(t("data_files.title", "Data and Files"), systemImage: "folder") }
      } label: { Image(systemName: "ellipsis").accessibilityLabel(t("more_menu", "More")) }
      .help(t("more_menu", "More"))
      .disabled(scenePhase != .active)
    } }
    .background(NavigationLink(isActive: Binding(get: { overviewDestination != nil }, set: {
      if !$0 { overviewDestination = nil }
    })) {
      if let destination = overviewDestination { destinationView(destination) }
    } label: { EmptyView() }.hidden())
    .onAppear {
      guard scenePhase == .active else { return }
      reload()
      if let metric = initialRecordMetric {
        initialRecordMetric = nil
        editor = archive?.draft ?? GalaxySSIHealthDraft(metric: metric)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { notification in
      if notification.object as? String == records.owner, editor == nil, scenePhase == .active { reload() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.sourceAttentionChanged)) { notification in
      if notification.object as? String == records.owner, scenePhase == .active { reloadSourceAttention() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { notification in
      if notification.object as? String == records.owner, scenePhase == .active { reload() }
    }
    .onChange(of: timeZone) { _ in if scenePhase == .active { reload() } }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
      if scenePhase == .active { reload() }
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        reload()
        if resumeDeletionOnForeground, let archive, let removed = latestRemoval(in: archive) {
          openDeletion(removed)
        }
      } else {
        overviewDestination = nil
        overviewNotice = nil
        editor = nil
        alert = nil
        archive = nil
        sourceAttention = []
        sourceCoverage = nil
        sourceAttentionUnavailable = false
        if phase == .background { sourceRecovery = nil }
        overviewPermissionFailed = false
        privacySaveFailed = false
        privacyLimit = 20
      }
    }
    .sheet(item: $editor, onDismiss: reload) { _ in
      NavigationView { editorForm }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
        .alert(item: $alert, content: editorAlert)
    }
    .sheet(item: $sourceRecovery) { incident in
      NavigationView {
        GalaxySSIHealthKitImportView(records: records, recoveryScope: incident.scope)
      }
      .navigationViewStyle(.stack)
    }
  }

  private var privacyOverview: some View {
    List {
      if scenePhase == .active, let archive {
        NavigationLink {
          GalaxySSIHealthMetricDeletionView(records: records)
        } label: {
          Label(t("metric_deletion.title", "Delete by Measurement Type"), systemImage: "trash")
        }
        Section(t("privacy.local", "Local analysis")) {
          Toggle(t("derive_overview", "Show local measurement summary"), isOn: Binding(
            get: { self.archive?.derivesOverview == true }, set: { changePrivacy(.overview, enabled: $0) }))
          Toggle(t("weekly.permission", "Allow local weekly reports"), isOn: Binding(
            get: { self.archive?.weeklyReportAllowed == true }, set: { changePrivacy(.weeklyReport, enabled: $0) }))
          Toggle(t("assistant.profile_permission", "Allow selected profile fields in local analysis"), isOn: Binding(
            get: { self.archive?.profileAnalysisPermission != nil }, set: { changePrivacy(.profileAnalysis, enabled: $0) }))
        }
        Section(t("privacy.imports", "New imports")) {
          Toggle(t("privacy.import_originals", "Keep originals of new imports"), isOn: Binding(
            get: { self.archive?.keepsNewImportOriginals == true },
            set: { changePrivacy(.importOriginals, enabled: $0) }))
          if privacySaveFailed { Text(t("privacy.failed", "The permission change was not saved.")) }
        }
        Section(t("privacy.history", "Permission history")) {
          let events = archive.privacyEvents ?? []
          if events.isEmpty { Text(t("privacy.empty", "No permission changes")).foregroundColor(.secondary) }
          ForEach(events.reversed().prefix(privacyLimit)) { event in
            VStack(alignment: .leading, spacing: 4) {
              Text(privacyScopeTitle(event.scope))
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
        if let uses = archive.profileAnalysisAudit, !uses.isEmpty {
          Section(t("privacy.profile_analysis_history", "Local profile use")) {
            ForEach(uses.reversed().prefix(privacyLimit)) { entry in
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.at, format: .dateTime)
                if !entry.fields.isEmpty {
                  Text(GalaxySSIHealthProfile.AnalysisField.allCases.filter(entry.fields.contains)
                    .map { $0.title(language: language) }.joined(separator: ", ")).foregroundColor(.secondary)
                }
                if let count = entry.backgroundCount, count > 0 {
                  Text(String(format: t("privacy.profile_background_count", "Selected background entries: %lld"),
                              Int64(count))).foregroundColor(.secondary)
                }
              }
            }
            if uses.count > privacyLimit { Button(t("more", "Show more")) { privacyLimit += 20 } }
          }
        }
        NavigationLink {
          GalaxySSIHealthOriginalRemovalHistoryView(store: GalaxySSIHealthOriginalStore(owner: records.owner,
                                                                                         secrets: records.secrets))
        } label: {
          Label(t("originals.removal_history", "Original removal history"), systemImage: "clock.arrow.circlepath")
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

  private func privacyScopeTitle(_ scope: GalaxySSIHealthRecords.PrivacyScope) -> String {
    switch scope {
    case .overview: return t("overview", "Measurement overview")
    case .weeklyReport: return t("weekly.title", "Weekly Health Report")
    case .importOriginals: return t("privacy.import_originals", "Keep originals of new imports")
    case .reportImages: return GalaxySSIHealthReportVision.text("permission", "Allow report images in explicitly confirmed online requests", language)
    case .profileAnalysis: return t("assistant.profile_permission", "Allow selected profile fields in local analysis")
    case .localCare: return t("care.permission", "Allow local health review")
    }
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
        if !sourceAttention.isEmpty || sourceAttentionUnavailable {
          Section(t("source_attention", "Data source attention")) {
            ForEach(sourceAttention) { incident in
              Button { sourceRecovery = incident } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Label(incident.scope.metric.title(language: language), systemImage: "exclamationmark.arrow.circlepath")
                  Text(t("healthkit.recovery_failed", "The last Apple Health query failed.")).foregroundColor(.secondary)
                  Text(incident.failedAt, style: .relative).font(.caption).foregroundColor(.secondary)
                }
              }
            }
            if sourceAttentionUnavailable {
              Text(t("healthkit.recovery_unavailable", "Source recovery information is unavailable.")).foregroundColor(.secondary)
            }
          }
        }
        Section(t("device_sources", "Device sources")) {
          NavigationLink {
            GalaxySSIHealthKitSyncView(records: records)
          } label: {
            Label(t("healthkit_sync.title", "Sync and Data Coverage"), systemImage: "arrow.triangle.2.circlepath")
          }
          NavigationLink {
            GalaxySSIHealthKitImportView(records: records)
          } label: {
            VStack(alignment: .leading) {
              Text("Apple Health")
              Text(GalaxySSIHealthKitImport.available ? t("platform_available", "Available on this device") :
                t("healthkit.unavailable", "HealthKit is unavailable on this device or in this build."))
                .foregroundColor(.secondary)
            }
          }
          NavigationLink {
            GalaxySSIHealthMetricDeletionView(records: records, filter: .appleHealth)
          } label: {
            Label(t("metric_deletion.apple_health_title", "Local Apple Health Copies"), systemImage: "tray.full")
          }
          bluetoothSourceStatus
          NavigationLink {
            GalaxySSIHealthBluetoothView(records: records)
          } label: {
            Label(t("bluetooth.title", "Bluetooth Blood Pressure"), systemImage: "waveform.path.ecg")
          }
          GalaxySSIHealthBluetoothHistorySection(records: records)
        }
        Section(t("healthkit.coverage_title", "Apple Health Coverage")) {
          ForEach(GalaxySSIHealthKitImport.Scope.allCases) { scope in
            NavigationLink {
              GalaxySSIHealthKitImportView(records: records, focusedScope: scope)
            } label: {
              GalaxySSIHealthKitCoverageRow(scope: scope, ledger: sourceCoverage,
                importHistory: archive.map { $0.healthKitImportedAt ?? [:] })
            }
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
            if let latest = current.first(where: {
              $0.bluetoothReceipt == nil && $0.tableSource == nil && $0.healthKitSource == nil && $0.reportSource == nil
            }) {
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
    .onAppear(perform: reload)
  }

  private func overview(_ snapshot: GalaxySSIHealthRecords.Archive, now: Date) -> some View {
    var local = calendar
    local.timeZone = timeZone
    let ranges = (try? records.overviewRanges(expected: snapshot, now: now)) ?? [:]
    let overview = GalaxySSIHealthOverview(current: snapshot.current, now: now, calendar: local, ranges: ranges)
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(overview.metrics) { item in
        GalaxySSIHealthOverviewMetricRow(item: item, records: records, open: openOverviewReading, manual: { startManual($0) })
        Divider()
      }
    }
  }

  private var bluetoothSourceStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(t("bluetooth_devices", "Bluetooth devices"))
      Text(bluetoothAuthorization).foregroundColor(.secondary)
      Text(t("coverage_no_live_bluetooth", "No live Bluetooth session on this screen")).foregroundColor(.secondary)
      if let archive, archive.derivesOverview == true,
         let latest = archive.current.compactMap(\.bluetoothReceipt?.receivedAt).max() {
        Text(t("coverage_last_bluetooth", "Latest saved Bluetooth receipt") + ": " +
          latest.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary)
      }
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
      case .undoConflict:
        return Alert(title: Text(t("undo_conflict", "Another measurement conflicts with this removal.")))
      }
  }

  private var editorForm: some View {
    Form {
      if scenePhase == .active, let removed = editor?.existing, removed.deleted {
        Section(title(removed.metric)) {
          Text(summary(removed))
          Text(removed.measuredAt, style: .date)
          Text(t("measurement_removed", "Measurement removed")).foregroundColor(.secondary)
          Button(t("undo_removal", "Undo deletion"), action: undoRemoval)
        }
      } else if let draft = editor, scenePhase == .active {
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
          if draft.metric == .glucose {
            Picker(t("conditions", "Conditions"), selection: Binding(
              get: { GalaxySSIHealthReportQuickImport.conditionKey(editor?.conditions ?? "") }, set: { editor?.conditions = $0 })) {
              Text(GalaxySSIHealthReportQuickImport.text("unknown", "Not sure", language)).tag("")
              Text(GalaxySSIHealthReportQuickImport.text("fasting", "Fasting", language)).tag("fasting")
              Text(GalaxySSIHealthReportQuickImport.text("non_fasting", "Not fasting", language)).tag("non_fasting")
              Text(GalaxySSIHealthReportQuickImport.text("after_meal", "After a meal", language)).tag("after_meal")
              Text(GalaxySSIHealthReportBatch.conditionTitle("after_meal_1h", language: language)).tag("after_meal_1h")
              Text(GalaxySSIHealthReportBatch.conditionTitle("after_meal_2h", language: language)).tag("after_meal_2h")
              if !draft.conditions.isEmpty && !GalaxySSIHealthReportBatch.conditions.contains(draft.conditions) {
                Text(draft.conditions).tag(draft.conditions)
              }
            }
          } else { TextField(t("conditions", "Conditions"), text: field(\.conditions, "")) }
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
        Button(t("cancel", "Cancel")) { resumeDeletionOnForeground = false; editor = nil }
      }
      ToolbarItem(placement: .confirmationAction) {
        if editor?.existing?.deleted != true { Button(t("save", "Save")) { save() } }
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

  private func latestRemoval(in archive: GalaxySSIHealthRecords.Archive) -> GalaxySSIHealthReading? {
    guard let token = archive.lastMeasurementDeletion,
          let reading = archive.revisions.last(where: { $0.id == token.id }),
          reading.deleted, reading.revision == token.revision else { return nil }
    return reading
  }

  private func openDeletion(_ removed: GalaxySSIHealthReading) {
    resumeDeletionOnForeground = true
    edit(removed)
  }

  private func undoRemoval() {
    guard scenePhase == .active, let removed = editor?.existing, removed.deleted else { return }
    do {
      let restored = try records.undoMeasurementDeletion(.init(id: removed.id, revision: removed.revision))
      resumeDeletionOnForeground = false
      let editorID = editor?.id
      edit(restored)
      if let editorID { editor?.id = editorID }
      reload()
    } catch GalaxySSIHealthRecords.Failure.duplicate { alert = .undoConflict }
      catch GalaxySSIHealthRecords.Failure.stale { alert = .stale; reload() }
      catch { alert = .unavailable }
  }

  private func save(allowDuplicate: Bool = false, deleted: Bool = false) {
    guard scenePhase == .active, let draft = editor else { return }
    do {
      if deleted, var existing = draft.existing {
        existing.deleted = true
        try records.write(existing, draftId: draft.id, rememberDeletion: true)
        existing.revision += 1
        editor?.existing = existing
        resumeDeletionOnForeground = true
        reload()
        return
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
      catch GalaxySSIHealthRecords.Failure.stale { alert = .stale; reload() }
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
    if let id = initialRecordID, let archive {
      initialRecordID = nil
      if let reading = archive.current.first(where: { $0.id == id }) { edit(reading) }
      else { alert = .unavailable }
    }
    reloadSourceAttention()
  }

  private func reloadSourceAttention() {
    do {
      let state = try records.loadSourceAttention()
      sourceAttention = state.active
      sourceCoverage = state
      sourceAttentionUnavailable = false
    } catch {
      sourceAttention = []
      sourceCoverage = nil
      sourceAttentionUnavailable = true
    }
  }

  @ViewBuilder private func destinationView(_ destination: OverviewDestination) -> some View {
    switch destination {
    case .weekly: GalaxySSIWeeklyHealthReportView(records: records)
    case .files: GalaxySSIHealthDataFilesView(records: records, metrics: { metricCatalog }, review: { recordCenter })
    case .assistant:
      GalaxySSIHealthAssistantView(records: records) { metric in
        editor = (try? records.load())?.draft ?? GalaxySSIHealthDraft(metric: metric ?? .bloodPressure)
      }
    case .sleep: GalaxySSIHealthSleepReminderView(records: records)
    case .reviews: GalaxySSIHealthReviewReminderView(records: records)
    case .records: recordCenter
    case .devices: sourceOverview
    case .originals: GalaxySSIHealthOriginalsView(store: originals)
    case .pdf: GalaxySSIHealthPDFTextView(store: originals, reviewRecords: records)
    case .profile: GalaxySSIHealthProfileView(records: records)
    case .crop: GalaxySSIHealthReportCropView(store: originals)
    case .export: GalaxySSIHealthMeasurementExportView(records: records)
    case .privacy: privacyOverview
    case .backup: GalaxySSIHealthBackupView(records: records, originals: originals)
    case .trends: GalaxySSIHealthTrendView(records: records) { startManual($0) }
    case .catalog: metricCatalog
    case .recording: GalaxySSIHealthRecordingReminderView(records: records) { startManual($0) }
    case .body: GalaxySSIHealthBodyView { bloodPressureRecords }
    case .imports: GalaxySSIHealthImportView(store: originals, records: records, initialAction: .files)
    case .photo: GalaxySSIHealthPhotoCaptureView(records: records, originals: originals, initialCamera: true)
    }
  }

  private var originals: GalaxySSIHealthOriginalStore {
    GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
  }

  @ViewBuilder private var overviewMenu: some View {
    Group {
    menuEntry(.records, "record_center.title", "Health Record Center", "square.and.pencil")
    menuEntry(.catalog, "catalog.title", "Measurement Catalog", "list.bullet.rectangle")
    menuEntry(.trends, "trend.title", "Measurement Trends", "chart.xyaxis.line")
    menuEntry(.reviews, "review_reminder.title", "Health Review Reminders", "doc.text.magnifyingglass")
    menuEntry(.recording, "recording_reminder.title", "Health Recording Reminders", "bell")
    menuEntry(.sleep, "sleep_reminder.title", "Sleep Change Reminders", "moon.zzz")
    menuEntry(.body, "body.title", "Body Explorer", "figure.stand")
    }
    Group {
    menuEntry(.profile, "profile.title", "Health Profile", "person.text.rectangle")
    menuEntry(.originals, "originals.title", "Health Originals", "doc.on.doc")
    menuEntry(.pdf, "pdf_text.title", "Report PDF Text", "doc.text.magnifyingglass")
    menuEntry(.crop, "report_crop.title", "Report Crop Preview", "crop")
    menuEntry(.export, "export.title", "Export Measurements", "square.and.arrow.up")
    menuEntry(.privacy, "privacy.title", "Health Privacy", "lock.shield")
    menuEntry(.backup, "backup.title", "Health Backup", "externaldrive")
    }
    if let archive, let removed = latestRemoval(in: archive) {
      Button { openDeletion(removed) } label: { Label(t("resume_removal", "Review last removed measurement"), systemImage: "arrow.uturn.backward") }
    }
  }
  private func menuEntry(_ destination: OverviewDestination, _ key: String, _ fallback: String, _ icon: String) -> some View {
    Button { overviewDestination = destination } label: { Label(t(key, fallback), systemImage: icon) }
  }
  private var bottomActions: some View {
    VStack(spacing: 0) {
      Divider()
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count:
        sizeCategory.isAccessibilityCategory || [.extraExtraLarge, .extraExtraExtraLarge].contains(sizeCategory) ? 2 : 4), spacing: 4) {
        bottomAction("overview_list.photo", "Photo", "camera") { overviewDestination = .photo }
        bottomAction(archive?.draft == nil ? "manual" : "resume_draft", archive?.draft == nil ? "Manual entry" : "Resume draft", "square.and.pencil") { startManual() }
        bottomAction("overview_list.import", "Import file", "square.and.arrow.down") { overviewDestination = .imports }
        bottomAction("overview_list.devices", "Connect devices", "externaldrive.connected.to.line.below") { overviewDestination = .devices }
      }.padding(.horizontal, 12).padding(.vertical, 4)
    }
    .background(Color(uiColor: .systemBackground))
    .disabled(scenePhase != .active || archive == nil)
    .accessibilityIdentifier("health-overview-bottom-actions")
  }
  private func bottomAction(_ key: String, _ fallback: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon).font(.body).foregroundColor(.green)
        Text(t(key, fallback)).font(.caption.weight(.semibold)).foregroundColor(.primary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, minHeight: 54)
    }.buttonStyle(.plain).help(t(key, fallback))
  }
  private func startManual(_ metric: GalaxySSIHealthMetric? = nil) {
    guard scenePhase == .active else { return }
    do { editor = try records.load().draft ?? GalaxySSIHealthDraft(metric: metric ?? .bloodPressure) }
    catch { overviewNotice = .unavailable }
  }
  private func openOverviewReading(_ reading: GalaxySSIHealthReading) {
    guard scenePhase == .active else { return }
    do {
      let current = try records.load()
      if let draft = current.draft { editor = draft; return }
      guard current.current.contains(reading) else { reload(); overviewNotice = .stale; return }
      edit(reading)
    } catch { overviewNotice = .unavailable }
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

  private var recordCenter: some View {
    GalaxySSIHealthRecordCenterView(records: records, devices: { sourceOverview }, addManual: { metric in
      reload()
      if let draft = archive?.draft { editor = draft }
      else if let metric { editor = GalaxySSIHealthDraft(metric: metric) }
      else { editor = GalaxySSIHealthDraft() }
    }, edit: { reading in reload(); edit(reading) })
  }

  private var metricCatalog: some View {
    GalaxySSIHealthMetricCatalogView(records: records, add: { metric in
      if let draft = archive?.draft { editor = draft }
      else { editor = GalaxySSIHealthDraft(metric: metric) }
    }, edit: edit)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
