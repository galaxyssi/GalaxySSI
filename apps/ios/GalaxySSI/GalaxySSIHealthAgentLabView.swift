import SwiftUI

@MainActor
struct GalaxySSIHealthAgentLabSheet: ViewModifier {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Binding var launch: GalaxySSIHealthAgentLab.Launch?
  func body(content: Content) -> some View {
    content.sheet(item: $launch) { item in GalaxySSIHealthAgentLabView(launch: item) }
      .onChange(of: scene) { if $0 != .active { launch = nil } }
      .onChange(of: store.activeAgentConversationId) { if launch?.conversation != $0 { launch = nil } }
      .onChange(of: store.profile.identityFingerprint) { _ in launch = nil }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in launch = nil }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in launch = nil }
  }
}

@MainActor
struct GalaxySSIHealthAgentLabView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.dismiss) private var dismiss
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let launch: GalaxySSIHealthAgentLab.Launch
  @State private var snapshot: GalaxySSIHealthAgentLab.Snapshot?
  @State private var blocked: GalaxySSIHealthAgentLab.Policy?
  @State private var failed = false
  @State private var status = ""
  @State private var dates: [Date] = []
  @State private var limit = 30
  @State private var abnormalOnly = false
  @State private var selected: GalaxySSIHealthReading?
  @State private var editingReminder = false
  @State private var note = ""
  @State private var condition = ""
  @State private var due = Date().addingTimeInterval(86_400)
  @State private var reminders: [String: GalaxySSIHealthCareFollowUp.Reminder] = [:]
  @State private var replacing: UUID?
  @State private var confirming = false
  private var records: GalaxySSIHealthRecords { .init(owner: launch.owner, secrets: store.secrets) }
  private var through: Date { dates.last ?? launch.through }
  private var localCalendar: Calendar { var value = calendar; value.timeZone = timeZone; return value }
  private var available: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.canReadAgentTranscript &&
      store.profile.identityFingerprint == launch.owner && store.activeAgentConversationId == launch.conversation &&
      store.agentSession(id: launch.conversation).map { $0.status == .active && $0.collaborationRoster == nil &&
        $0.mergedIntoConversationId.isBlank && $0.globalTopicKey.isBlank } == true
  }
  var body: some View {
    NavigationView {
      List {
        if available {
          if let blocked {
            Text(t("blocked", "Local health analysis is off."))
            Button(t("once", "Allow one local read")) {
              reload(once: .init(owner: launch.owner, policy: blocked, through: through))
            }.accessibilityIdentifier("health-lab-once")
            NavigationLink(t("privacy", "Health privacy")) { GalaxySSIHealthCenterView(records: records, initialPrivacy: true) }
          }
          if failed { Text(t("unavailable", "Saved results are unavailable.")); Button(t("retry", "Retry")) { reload() } }
          if let snapshot { results(snapshot) }
          if let row = selected, snapshot?.policy.allowed == true { editor(row) }
          if !status.isEmpty { Text(status).font(.footnote).foregroundColor(.secondary) }
        }
      }
      .navigationTitle(t("title", "Saved lab results"))
      .galaxySSIHealthTheme()
      .toolbar { ToolbarItem(placement: .cancellationAction) {
        Button(t("close", "Close")) { dismiss() }
      } }
      .alert(t("confirm", "Confirm recheck reminder"), isPresented: $confirming) {
        Button(t("save", "Save")) { saveReminder() }
        Button(t("cancel", "Cancel"), role: .cancel) { }
      } message: {
        if let selected { Text(selected.metric.title(language: language) + "\n" + due.formatted(date: .abbreviated, time: .shortened)) }
      }
    }.navigationViewStyle(.stack)
    .privacySensitive()
    .onAppear { abnormalOnly = launch.mode == .abnormal; reload() }
    .onDisappear(perform: clear)
    .onChange(of: scene) { if $0 != .active { clear() } else { reload() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clear(); dismiss() }
    .onChange(of: store.activeAgentConversationId) { _ in if !available { clear(); dismiss() } }
    .onChange(of: timeZone) { _ in dates = []; reload() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clear(); dismiss() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { event in
      if event.object as? String == launch.owner { reload() }
    }
  }
  @ViewBuilder private func results(_ value: GalaxySSIHealthAgentLab.Snapshot) -> some View {
    if let day = value.day {
      Section {
        Text(t(value.imported ? "report_day" : "manual_day", value.imported ? "Saved report" : "Manually entered results") + " \u{00B7} " + day.formatted(date: .abbreviated, time: .omitted))
        Text(String(format: t("counts", "%lld results / %lld outside the report range / %lld unknown"),
          Int64(value.rows.count), Int64(value.abnormal.count), Int64(value.unknown)))
          .accessibilityIdentifier("health-lab-summary")
        Picker(t("filter", "Results"), selection: $abnormalOnly) {
          Text(t("all", "All")).tag(false); Text(t("abnormal", "Outside range")).tag(true)
        }.pickerStyle(.segmented)
        HStack {
          Button { if let older = value.olderUntil { dates.append(older); reload() } } label: {
            Label(t("older", "Older report"), systemImage: "chevron.left")
          }.disabled(value.olderUntil == nil)
          Spacer()
          Button { if !dates.isEmpty { dates.removeLast(); reload() } } label: {
            Label(t("newer", "Newer report"), systemImage: "chevron.right")
          }.disabled(dates.isEmpty)
        }.buttonStyle(.borderless)
        if launch.mode == .note || launch.mode == .remind { Text(t("choose", "Select the measurement")) }
      }
      let rows = abnormalOnly ? value.abnormal : value.rows
      if rows.isEmpty { Text(t("no_flag", "No comparable result is outside the report reference range.")) }
      ForEach(Array(rows.prefix(limit))) { row in
        Section {
          VStack(alignment: .leading, spacing: 5) {
            Text(row.metric.title(language: language)).font(.headline)
            Text(GalaxySSIHealthOverviewHistoryView.amount(row))
            let range = GalaxySSIHealthOverviewRange.report(row)
            Text(t(range?.position == .notComparable ? "unknown" : range?.position.rawValue ?? "unknown", direction(range?.position)) + " \u{00B7} " + (row.referenceInterval.flatMap { $0.isBlank ? nil : $0 } ?? t("unknown", "Unknown")))
              .font(.footnote).foregroundColor(.secondary)
          }.accessibilityIdentifier("health-lab-record")
          NavigationLink { GalaxySSIHealthCenterView(records: records, initialRecordMetric: row.metric, initialRecordID: row.id) } label: {
            Label(t("source", "Record and source history"), systemImage: "doc.text.magnifyingglass")
          }.disabled(!value.policy.allowed)
          HStack {
            Button { edit(row, reminder: false) } label: { Label(t("note", "Add personal note"), systemImage: "square.and.pencil") }
            Spacer()
            Button { edit(row, reminder: true) } label: { Label(t("remind", "Recheck reminder"), systemImage: "bell.badge") }
          }.buttonStyle(.borderless).disabled(!value.policy.allowed)
          if let reminder = reminders["local-lab-review:" + row.id.uuidString] {
            Text(reminder.requestedAt, style: .date)
            Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) {
              do { guard available else { return }; try records.cancelLocalCareFollowUp(reminder); reload() }
              catch { status = t("changed", "The record or permission changed. Reopen the result.") }
            }.disabled(!value.policy.allowed)
          }
        }
      }
      if rows.count > limit { Button(t("more", "Show more")) { limit += 30 } }
    } else { Text(t("empty", "No confirmed lab measurements are saved in Health Center.")) }
  }
  @ViewBuilder private func editor(_ row: GalaxySSIHealthReading) -> some View {
    Section(row.metric.title(language: language)) {
      if editingReminder {
        DatePicker(t("due", "Recheck time"), selection: $due, in: Date()..., displayedComponents: [.date, .hourAndMinute])
        Button { confirming = true } label: { Label(t("confirm", "Confirm recheck reminder"), systemImage: "bell.badge") }
        NavigationLink(t("notification_settings", "Health review notification settings")) { GalaxySSIHealthReviewReminderView(records: records) }
      } else {
        TextEditor(text: $note).frame(minHeight: 100, maxHeight: 160).accessibilityLabel(t("note", "Add personal note"))
        Picker(t("condition", "Collection condition"), selection: $condition) {
          Text(t("keep_condition", "Keep existing condition")).tag("")
          ForEach(["fasting", "non_fasting", "after_meal", "after_meal_1h", "after_meal_2h"], id: \.self) { code in
            Text(t(code, code.replacingOccurrences(of: "_", with: " "))).tag(code)
          }
        }
        Button { saveNote() } label: { Label(t("save", "Save"), systemImage: "checkmark") }
          .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || note.count > 500)
      }
      Button(t("cancel", "Cancel"), role: .cancel) { selected = nil; note = ""; condition = "" }
    }
  }
  private func edit(_ row: GalaxySSIHealthReading, reminder: Bool) {
    guard available, snapshot?.policy.allowed == true else { return }
    selected = row; editingReminder = reminder; condition = ""
    note = launch.mode == .note ? launch.supplement : ""
    replacing = reminders["local-lab-review:" + row.id.uuidString]?.id
    due = reminders["local-lab-review:" + row.id.uuidString]?.requestedAt ??
      GalaxySSIHealthAgentLab.suggestedDay(launch.supplement, now: Date(), calendar: localCalendar) ?? Date().addingTimeInterval(86_400)
    status = ""
  }
  private func saveNote() {
    guard available, let row = selected, let policy = snapshot?.policy else { return }
    do { try records.annotateLocalLab(row, policy: policy, note: note, condition: condition.isEmpty ? nil : condition); reload() }
    catch { status = t("changed", "The record or permission changed. Reopen the result.") }
  }
  private func saveReminder() {
    guard available, let row = selected, let policy = snapshot?.policy else { return }
    do {
      try records.scheduleLocalLabRecheck(row, policy: policy, conversation: launch.conversation, through: through,
        replacing: replacing, at: due, confirmed: true)
      reload()
    } catch { status = t("reminder_failed", "The record changed, local care is off, or review notifications are not enabled.") }
  }
  private func reload(once: GalaxySSIHealthAgentLab.Once? = nil) {
    clear()
    guard available else { return }
    do {
      snapshot = try records.localLabMeasurements(through: through, once: once, calendar: localCalendar)
      let archive = try records.load()
      reminders = (archive.localCareFollowUps ?? [:]).filter { records.localLabRecheckIsCurrent($0.value, archive: archive) }
    } catch GalaxySSIHealthRecords.Failure.permission {
      if let archive = try? records.load() { blocked = .init(archive) } else { failed = true }
    } catch { failed = true }
  }
  private func clear() {
    snapshot = nil; blocked = nil; failed = false; selected = nil; note = ""; condition = ""; status = ""
    reminders = [:]; replacing = nil; confirming = false; limit = 30
  }
  private func direction(_ value: GalaxySSIHealthOverviewRange.Position?) -> String {
    switch value { case .above: return "Above range"; case .below: return "Below range"; case .within: return "Within range"; default: return "Unknown" }
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthAgentLab.text(key, fallback, language) }
}

@MainActor
struct GalaxySSIHealthAgentLabOpenButton: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let message: ChatMessage
  @State private var launch: GalaxySSIHealthAgentLab.Launch?
  var body: some View {
    if let mode = GalaxySSIHealthAgentLab.mode(message) {
      Button {
        guard store.activeAgentConversationId == message.conversationId, store.canReadAgentTranscript,
          UIApplication.shared.isProtectedDataAvailable else { return }
        launch = .init(owner: store.profile.identityFingerprint, conversation: message.conversationId, mode: mode,
          through: min(message.createdAt, Date()))
      } label: { Label(GalaxySSIHealthAgentLab.text("open", "Open saved lab results", language), systemImage: "list.bullet.rectangle") }
        .modifier(GalaxySSIHealthAgentLabSheet(launch: $launch))
    }
  }
}
