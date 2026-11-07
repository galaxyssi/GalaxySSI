import CryptoKit
import SwiftUI

@MainActor
struct GalaxySSIHealthAssistantView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  let trendScope: GalaxySSIHealthTrendAnalysis?
  let openRecord: (GalaxySSIHealthMetric?) -> Void
  @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
  @State private var to = Date()
  @State private var metrics: Set<GalaxySSIHealthMetric> = [.bloodPressure]
  @State private var analysis: GalaxySSIHealthAnalysis?
  @State private var evidence: GalaxySSIHealthAnalysis.Evidence?
  @State private var sourceLimit = 30
  @State private var enabled = false
  @State private var online: UUID?
  @State private var modelContactID = ""
  @State private var consent: SummaryReview?
  @State private var recommendation: GalaxySSIHealthAnalysis.Recommendation?
  @State private var task: Task<Void, Never>?
  @State private var requestID: UUID?
  @State private var error = false
  @State private var stale = false
  @State private var compareInReport = false
  @State private var reportScope: GalaxySSIHealthAnalysis.ReportScope?
  @State private var presentedReport: GalaxySSIHealthAnalysis.ReportScope?
  @State private var profileAllowed = false
  @State private var profilePermission: UUID?
  @State private var profileFields: Set<GalaxySSIHealthProfile.AnalysisField> = []
  @State private var profileContext: GalaxySSIHealthProfile.AnalysisContext?
  @State private var backgroundSelection: [UUID: UUID] = [:]
  @State private var choosingBackground = false
  @State private var comparison: GalaxySSIHealthAnalysis?
  @State private var followUpDraft = ""
  @State private var followUpProvider = ""
  @State private var followUpReview: FollowUpReview?
  @State private var followUpRequest: Consent?
  @State private var followUpResult: FollowUpResult?
  @State private var followUpNotice: FollowUpNotice?
  @State private var followUpReminder = false
  @State private var reminderRecord: GalaxySSIHealthMetric?

  private struct Consent: Equatable {
    let contactID: String
    let model: CloudModelConfig
    let endpoint: URL
    let permission: UUID
  }

  private struct SummaryReview: Identifiable {
    let id = UUID()
    let target: Consent
    let analysisID: UUID
    let payload: Data
    let credentialDigest: SHA256.Digest
  }

  init(records: GalaxySSIHealthRecords, trendScope: GalaxySSIHealthTrendAnalysis? = nil,
       openRecord: @escaping (GalaxySSIHealthMetric?) -> Void) {
    self.records = records
    self.trendScope = trendScope
    self.openRecord = openRecord
  }

  private struct FollowUpReview: Identifiable {
    let id = UUID()
    let target: Consent
    let packet: GalaxySSIHealthFollowUp
    let credentialDigest: SHA256.Digest
  }

  private struct FollowUpResult {
    let target: Consent
    let analysisID: UUID
    let comparisons: [String: GalaxySSIHealthFollowUp.Comparison]
    let answer: GalaxySSIHealthFollowUp.Answer
  }

  private enum FollowUpNotice { case unavailable, blocked, invalidated }

  private var followUpContacts: [GalaxySSIContact] {
    store.contacts.filter {
      !$0.deleted && $0.deliveryMode == .cloudAPI &&
        $0.selectedCloudModel.flatMap(GalaxySSIHealthFollowUpTransport.endpoint(for:)) != nil
    }
  }

  private var followUpModels: [String: CloudModelConfig] {
    followUpContacts.reduce(into: [:]) { $0[$1.id] = $1.selectedCloudModel }
  }

  private var providers: [GalaxySSIContact] {
    store.contacts.filter { contact in
      !contact.deleted && contact.selectedCloudModel.flatMap(GalaxySSIHealthSummaryTransport.endpoint(for:)) != nil
    }
  }

  private var assistantList: some View {
    List {
      if scene == .active {
        if enabled {
          scopeSection
          if trendScope == nil { profileSelection }
          if let analysis {
            analysisSection(analysis)
            if let profileContext { profileResult(profileContext) }
            providerSection(analysis)
            followUpSection(analysis)
          }
        } else {
          Text(t("permission", "Enable the local measurement summary in Health Privacy."))
        }
        if stale { Text(t("stale", "Measurements or permissions changed. Run the analysis again.")) }
        if error { Text(t("failed", "The analysis could not be completed.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Health Assistant"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var activeAssistant: some View {
    assistantList
    .onAppear {
      refreshPermissions()
      if trendScope != nil, enabled { calculate() }
    }
    .onChange(of: from) { _ in clear() }
    .onChange(of: to) { _ in clear() }
    .onChange(of: calendar) { _ in clear() }
    .onChange(of: timeZone) { _ in clear() }
    .onChange(of: metrics) { _ in clear() }
    .onChange(of: compareInReport) { _ in clear() }
    .onChange(of: profileFields) { _ in clear() }
    .onChange(of: backgroundSelection) { _ in clear() }
    .onChange(of: modelContactID) { _ in cancelRequest(); recommendation = nil }
    .onChange(of: followUpModels) { _ in invalidateChangedFollowUpTarget() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onDisappear { clear() }
    .onChange(of: scene) {
      if $0 == .active { refreshPermissions() }
      else {
        clear(); enabled = false; online = nil
        profileAllowed = false; profilePermission = nil; profileFields = []
        clearBackgroundSelection()
        if $0 == .background { presentedReport = nil }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { refreshPermissions() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
      if $0.object as? String == records.owner { refreshPermissions() }
    }
  }

  var body: some View {
    activeAssistant
    .sheet(item: $consent) { review in
      NavigationView {
        List {
          if scene == .active {
            Text(review.target.model.modelId)
            Text(review.target.endpoint.absoluteString).font(.footnote)
            Text(t("disclosure", "Only metric aggregates and coverage are sent. No records, dates, notes, profile or chat history."))
            Text(String(decoding: review.payload, as: UTF8.self))
              .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            Button(t("send", "Send aggregates")) { send(review) }
          }
        }
        .navigationTitle(t("confirm", "Send selected aggregates to this provider?"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("close", "Close")) { consent = nil }
        } }
      }.navigationViewStyle(.stack)
    }
    .sheet(isPresented: $choosingBackground) {
      GalaxySSIHealthBackgroundPicker(records: records, selection: backgroundSelection) { selected in
        backgroundSelection = selected
      }
    }
    .sheet(item: $followUpReview, content: followUpDisclosure)
    .sheet(isPresented: $followUpReminder, onDismiss: {
      if let metric = reminderRecord { reminderRecord = nil; openRecord(metric) }
    }) {
      NavigationView {
        GalaxySSIHealthRecordingReminderView(records: records) { metric in
          reminderRecord = metric
          followUpReminder = false
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("close", "Close")) { followUpReminder = false }
        } }
      }
      .navigationViewStyle(.stack)
    }
    .sheet(item: $evidence) { item in
      NavigationView {
        List {
          if scene == .active {
            ForEach(item.readings.prefix(sourceLimit)) { reading in
              VStack(alignment: .leading, spacing: 3) {
                Text(reading.measuredAt.formatted(date: .abbreviated, time: .shortened))
                if let value = sourceValue(item.aggregate.component, reading: reading) {
                  Text(NSDecimalNumber(decimal: value).stringValue + " " + item.aggregate.unit)
                }
                Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision)))
                  .font(.caption).foregroundColor(.secondary)
              }
            }
            if item.readings.count > sourceLimit { Button(t("more", "Show more")) { sourceLimit += 30 } }
          }
        }
        .navigationTitle(t("sources", "Source records"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button(t("close", "Close")) { evidence = nil }
        } }
      }
      .navigationViewStyle(.stack)
    }
    .sheet(item: $presentedReport) { scope in
      NavigationView {
        GalaxySSIWeeklyHealthReportView(records: records, assistantScope: scope)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { presentedReport = nil }
          } }
      }
      .navigationViewStyle(.stack)
    }
  }

  private var scopeSection: some View {
    Section(t("scope", "Analysis scope")) {
      if let trendScope {
        Text(trendScope.spec.metric.title(language: language))
        Text(trendScope.sourceTitle).foregroundColor(.secondary)
        Text(trendScope.spec.interval.start, style: .date)
        Text(trendScope.spec.through, style: .date)
        Text(trendScope.spec.calendar.timeZone.identifier).font(.caption).foregroundColor(.secondary)
      } else {
        DatePicker(t("from", "From"), selection: $from, in: ...Date(), displayedComponents: .date)
        DatePicker(t("to", "Through"), selection: $to, in: ...Date(), displayedComponents: .date)
        Toggle(t("compare_previous", "Include the previous period for comparison"), isOn: $compareInReport)
        DisclosureGroup(t("metrics", "Measurements")) {
          ForEach(GalaxySSIHealthMetric.allCases) { metric in
            Toggle(metric.title(language: language), isOn: Binding(get: { metrics.contains(metric) }, set: {
              if $0 { metrics.insert(metric) } else { metrics.remove(metric) }
            }))
            .disabled(metrics.count >= 6 && !metrics.contains(metric))
          }
        }
      }
      Button(t("calculate", "Calculate on this device"), action: calculate).disabled(metrics.isEmpty)
    }
  }

  private func analysisSection(_ analysis: GalaxySSIHealthAnalysis) -> some View {
    Section(t("local", "Local results")) {
      if let reportScope {
        Button(t("open_weekly_report", "Open scoped weekly report")) { presentedReport = reportScope }
      }
      ForEach(analysis.evidence) { item in
        let aggregate = item.aggregate
        VStack(alignment: .leading, spacing: 4) {
          Text(item.metric.title(language: language) + component(aggregate.component))
          if let fact = analysis.trendFact {
            trendDetails(analysis, fact: fact)
          } else if let low = aggregate.minimum, let high = aggregate.maximum, let mean = aggregate.mean {
            Text(String(format: t("range", "Min %@, max %@, mean %@"), low, high, mean) + " " + aggregate.unit)
            Text(String(format: t("coverage", "%lld / %lld days with readings"), Int64(aggregate.observedDays),
                        Int64(analysis.requestedDays))).foregroundColor(.secondary)
            Button(t("sources", "Source records")) { sourceLimit = 30; evidence = item }
              .buttonStyle(.borderless)
          } else { Text(t("missing", "No comparable numeric readings")).foregroundColor(.secondary) }
        }
      }
    }
  }

  private func trendDetails(_ analysis: GalaxySSIHealthAnalysis, fact: GalaxySSIHealthTrendAnalysis.Fact) -> some View {
    Group {
      let unit = analysis.trend?.spec.unit ?? ""
      let label: String = fact.aggregation == "min" ? t("trend_min", "Minimum") :
        (fact.aggregation == "max" ? t("trend_max", "Maximum") : t("trend_mean", "Mean"))
      Text(label + " / " + unit)
      Text(String(format: t("coverage", "%lld / %lld days with readings"), Int64(fact.pointCount),
        Int64(analysis.requestedDays))).foregroundColor(.secondary)
      Text(String(format: t("trend_missing", "Days without records: %lld; nonnumeric: %lld; other units: %lld"),
        Int64(fact.missingDays), Int64(fact.excludedNonNumeric), Int64(fact.excludedOtherUnits)))
        .font(.caption).foregroundColor(.secondary)
      if let delta = fact.delta { Text(String(format: t("trend_delta", "First-to-last change: %@"), delta) + " " + unit) }
      if let first = analysis.trendFirst {
        trendSource(first, title: t("trend_first", "First point"), value: fact.first.value, analysis: analysis)
      }
      if let last = analysis.trendLast, let bucket = fact.last {
        trendSource(last, title: t("trend_last", "Last point"), value: bucket.value, analysis: analysis)
      }
    }
  }

  private func trendSource(_ item: GalaxySSIHealthAnalysis.Evidence, title: String, value: String,
                           analysis: GalaxySSIHealthAnalysis) -> some View {
    Button {
      refreshPermissions()
      guard self.analysis?.id == analysis.id else { return }
      sourceLimit = 30
      evidence = item
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text(title + ": " + value + " " + item.aggregate.unit)
        if let date = item.readings.first?.measuredAt { Text(date, style: .date).font(.caption) }
      }
    }.buttonStyle(.borderless)
  }

  private var profileSelection: some View {
    Section(t("profile_context", "Local profile context")) {
      Toggle(t("profile_permission", "Allow selected profile fields in local analysis"), isOn: Binding(
        get: { profileAllowed }, set: { value in
          do { try records.setProfileAnalysisAllowed(value); refreshPermissions() }
          catch { error = true }
        }))
      if profileAllowed {
        ForEach(GalaxySSIHealthProfile.AnalysisField.allCases) { field in
          Toggle(field.title(language: language), isOn: Binding(get: { profileFields.contains(field) }, set: {
            if $0 { profileFields.insert(field) } else { profileFields.remove(field) }
            clear()
          }))
        }
        Button { choosingBackground = true } label: {
          HStack {
            Text(t("background_title", "Saved health background"))
            Spacer()
            Text(String(backgroundSelection.count)).foregroundColor(.secondary)
          }
        }
      }
    }
  }

  private func profileResult(_ context: GalaxySSIHealthProfile.AnalysisContext) -> some View {
    Section(t("profile_self_reported", "Self-reported profile context")) {
      ForEach(GalaxySSIHealthProfile.AnalysisField.allCases.filter { context.fields.contains($0) }) { field in
        VStack(alignment: .leading, spacing: 4) {
          Text(field.title(language: language))
          Text(profileValue(context.values[field])).foregroundColor(.secondary)
        }
      }
      ForEach(context.background) { entry in
        VStack(alignment: .leading, spacing: 4) {
          Text(GalaxySSIHealthBackgroundPicker.title(entry.kind, language: language)).foregroundColor(.secondary)
          Text(entry.title)
          if !entry.notes.isEmpty { Text(entry.notes).foregroundColor(.secondary) }
        }
      }
    }
  }

  private func profileValue(_ value: GalaxySSIHealthProfile.AnalysisValue?) -> String {
    switch value {
    case .date(let date)?: return date.formatted(date: .abbreviated, time: .omitted)
    case .sex(.female)?: return t("profile_female", "Female")
    case .sex(.male)?: return t("profile_male", "Male")
    case .sex(.other)?: return t("profile_other", "Other")
    case .height(let height, let unit)?: return height.formatted() + (unit == .cm ? " cm" : " in")
    case .context(let text)?: return text
    default: return t("profile_missing", "Not recorded")
    }
  }

  private func providerSection(_ analysis: GalaxySSIHealthAnalysis) -> some View {
    Section(t("online", "Optional online summary")) {
      Toggle(t("online_permission", "Allow online summaries and follow-up requests"), isOn: Binding(
        get: { online != nil }, set: setOnline))
      if online != nil {
        Picker(t("provider", "Provider"), selection: $modelContactID) {
          Text(t("none", "Not selected")).tag("")
          ForEach(providers) { contact in
            Text(contact.selectedCloudModel?.displayName ?? "").tag(contact.id)
          }
        }
        Button(t("prepare_send", "Review and send aggregates"), action: prepareSend)
          .disabled(task != nil || modelContactID.isEmpty || analysis.evidence.allSatisfy { $0.aggregate.count == 0 })
        if task != nil && followUpRequest == nil { ProgressView(t("working", "Waiting for provider")) }
        if let recommendation {
          Text(nextStep(recommendation.nextStep))
          ForEach(analysis.evidence.filter { recommendation.evidence.contains($0.id) }) { item in
            Button(item.metric.title(language: language) + component(item.aggregate.component)) {
              sourceLimit = 30; evidence = item
            }.buttonStyle(.borderless)
          }
        }
      }
    }
  }

  private func followUpSection(_ analysis: GalaxySSIHealthAnalysis) -> some View {
    Section(t("follow_up.title", "Ask about this analysis")) {
      if online != nil && analysis.evidence.contains(where: { $0.aggregate.count > 0 }) {
        if followUpContacts.isEmpty {
          Text(t("follow_up.no_provider", "No compatible cloud model is configured."))
        } else {
          VStack(alignment: .leading, spacing: 4) {
            Text(t("follow_up.question", "Follow-up question")).font(.subheadline)
            TextEditor(text: $followUpDraft)
              .frame(minHeight: 64, maxHeight: 112)
              .accessibilityLabel(t("follow_up.question", "Follow-up question"))
              .disabled(task != nil)
            if !followUpDraft.isEmpty && GalaxySSIHealthFollowUp.question(followUpDraft) == nil {
              Text(t("follow_up.invalid_question", "Enter up to 600 characters without unsupported control characters."))
                .font(.caption).foregroundColor(.secondary)
            }
          }
          Picker(t("provider", "Provider"), selection: $followUpProvider) {
            Text(t("none", "Not selected")).tag("")
            ForEach(followUpContacts) { contact in
              Text(contact.selectedCloudModel?.displayName ?? "").tag(contact.id)
            }
          }.disabled(task != nil)
          Button(t("follow_up.review", "Review request"), action: prepareFollowUp)
            .disabled(task != nil || followUpModels[followUpProvider] == nil ||
                      GalaxySSIHealthFollowUp.question(followUpDraft) == nil)
        }
        if followUpRequest != nil {
          ProgressView(t("working", "Waiting for provider"))
          Button(t("follow_up.cancel", "Cancel request"), action: cancelRequest)
        }
        if let followUpResult { followUpAnswer(followUpResult, analysis: analysis) }
        if let followUpNotice { Text(notice(followUpNotice)).foregroundColor(.secondary) }
      } else {
        Text(t("follow_up.requires_online", "Follow-up requires online permission and numeric readings in this analysis."))
          .foregroundColor(.secondary)
      }
    }
  }

  private func followUpDisclosure(_ review: FollowUpReview) -> some View {
    NavigationView {
      List {
        if scene == .active && followUpReview?.id == review.id {
          Section(t("provider", "Provider")) {
            Text(verbatim: review.target.model.displayName)
            Text(verbatim: review.target.model.modelId)
            Text(verbatim: review.target.endpoint.absoluteString)
          }
          Section(t("follow_up.payload", "Exact analysis data to send")) {
            Text(verbatim: String(decoding: review.packet.payload, as: UTF8.self))
              .font(.system(.footnote, design: .monospaced))
              .textSelection(.enabled)
          }
          Text(t("follow_up.disclosure", "Only this question, scoped facts and any previous verified selections are sent. Do not include private details in your question."))
          Button(t("follow_up.send", "Send this question")) { sendFollowUp(review) }
        }
      }
      .navigationTitle(t("follow_up.review", "Review request"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) {
        Button(t("close", "Close")) { followUpReview = nil }
      } }
    }
    .navigationViewStyle(.stack)
  }

  private func followUpAnswer(_ result: FollowUpResult, analysis: GalaxySSIHealthAnalysis) -> some View {
    Group {
      if result.answer.status == .outOfScope {
        Text(t("follow_up.out_of_scope", "This question is outside the selected analysis."))
      } else if result.answer.status == .partial {
        Text(t("follow_up.partial", "Only part of the question is supported by this analysis."))
      }
      ForEach(result.answer.sections) { section in
        Text(topicTitle(section.topic)).font(.headline).accessibilityAddTraits(.isHeader)
        ForEach(section.factIDs, id: \.self) { id in
          if let item = analysis.evidence.first(where: { $0.id == id }) {
            followUpFact(item, topic: section.topic, result: result, days: analysis.requestedDays)
          }
        }
      }
      ForEach(result.answer.actions) { action in
        Button(actionTitle(action)) {
          guard validateFollowUpResult(result) else { return }
          switch action {
          case .addRecord: openRecord(trendScope?.spec.metric ?? (metrics.count == 1 ? metrics.first : nil))
          case .recordReminder: followUpReminder = true
          case .weeklyReport: presentedReport = reportScope
          }
        }
      }
    }
  }

  private func followUpFact(_ item: GalaxySSIHealthAnalysis.Evidence, topic: GalaxySSIHealthFollowUp.Topic,
                            result: FollowUpResult, days: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(item.metric.title(language: language) + component(item.aggregate.component))
      if let analysis, let fact = analysis.trendFact, topic == .changes {
        trendDetails(analysis, fact: fact)
      } else if topic == .changes, let delta = result.comparisons[item.id], let mean = item.aggregate.mean {
        Text(String(format: t("follow_up.delta", "Mean %@ vs %@; change %@"),
                    mean, delta.mean, delta.delta) + " " + item.aggregate.unit)
        Button(t("follow_up.previous_sources", "Previous period source records")) {
          if validateFollowUpResult(result) { sourceLimit = 30; evidence = delta.evidence }
        }.buttonStyle(.borderless)
      }
      Text(String(format: t("coverage", "%lld / %lld days with readings"), Int64(item.aggregate.observedDays),
                  Int64(days))).foregroundColor(.secondary)
      if !item.readings.isEmpty {
        Button(t("sources", "Source records")) {
          if validateFollowUpResult(result) { sourceLimit = 30; evidence = item }
        }.buttonStyle(.borderless)
      }
    }
  }

  private func topicTitle(_ topic: GalaxySSIHealthFollowUp.Topic) -> String {
    switch topic {
    case .changes: return t("follow_up.changes", "Changes")
    case .coverage: return t("follow_up.coverage", "Coverage")
    case .sources: return t("sources", "Source records")
    }
  }

  private func actionTitle(_ action: GalaxySSIHealthFollowUp.Action) -> String {
    switch action {
    case .addRecord: return t("follow_up.add_record", "Record measurement")
    case .recordReminder: return t("follow_up.reminder", "Recording reminders")
    case .weeklyReport: return t("open_weekly_report", "Open scoped weekly report")
    }
  }

  private func notice(_ value: FollowUpNotice) -> String {
    switch value {
    case .unavailable: return t("follow_up.unavailable", "This provider could not complete the follow-up.")
    case .blocked: return t("follow_up.blocked", "Sharing with this provider is blocked in the Privacy Dashboard.")
    case .invalidated: return t("follow_up.invalidated", "The analysis, permission, or provider changed. Review a new request.")
    }
  }

  private func calculate() {
    clear()
    guard scene == .active, !metrics.isEmpty else { return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true else { refreshPermissions(); return }
      if let trendScope {
        guard trendScope.spec.calendar.timeZone == timeZone,
              let filtered = GalaxySSIHealthAnalysis(trend: trendScope, current: archive.current)
        else { stale = true; return }
        analysis = filtered
        return
      }
      var local = calendar
      local.timeZone = timeZone
      let first = local.startOfDay(for: from), last = local.startOfDay(for: to)
      guard first <= last, let end = local.date(byAdding: .day, value: 1, to: last),
            let days = local.dateComponents([.day], from: first, to: end).day, (1...90).contains(days)
      else { error = true; return }
      let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: first, end: end), metrics: metrics)
      profileContext = try records.captureProfileAnalysis(profileFields, background: backgroundSelection)
      let current = archive.current
      analysis = GalaxySSIHealthAnalysis(scope: scope, current: current, calendar: local)
      reportScope = .init(scope: scope, calendar: local, compare: compareInReport, current: current)
      if let interval = reportScope?.comparison {
        comparison = GalaxySSIHealthAnalysis(scope: .init(interval: interval, metrics: metrics),
                                             current: current, calendar: local)
      }
    } catch GalaxySSIHealthRecords.Failure.stale { stale = true }
    catch { error = true }
  }

  private func setOnline(_ allowed: Bool) {
    guard scene == .active else { return }
    do { try records.setHealthOnlinePermission(allowed); refreshPermissions() }
    catch { error = true }
  }

  private func refreshPermissions() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      enabled = archive.derivesOverview == true
      let permission = enabled ? archive.profileAnalysisPermission : nil
      profileAllowed = permission != nil
      if !profileAllowed || profilePermission != permission { profileFields = []; clearBackgroundSelection() }
      profilePermission = permission
      if online != archive.healthOnlinePermission {
        cancelRequest(); recommendation = nil; clearFollowUp(); evidence = nil
      }
      online = archive.healthOnlinePermission
      let profileCurrent = try profileIsCurrent(archive)
      if let analysis, !enabled || !analysis.isCurrent(archive.current) ||
          comparison?.isCurrent(archive.current) == false || !profileCurrent {
        clear()
        stale = true
      }
    } catch {
      clear(); enabled = false; online = nil; profileAllowed = false; profilePermission = nil; profileFields = []
      clearBackgroundSelection(); error = true
    }
  }

  private func prepareSend() {
    guard scene == .active, let permission = online, let analysis,
          let contact = providers.first(where: { $0.id == modelContactID }),
          let model = contact.selectedCloudModel, let endpoint = GalaxySSIHealthSummaryTransport.endpoint(for: model),
          let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key),
          let payload = try? analysis.requestJSON()
    else { return }
    let target = Consent(contactID: contact.id, model: model, endpoint: endpoint, permission: permission)
    guard (try? authorized(target, analysis: analysis)) == true else { refreshPermissions(); return }
    consent = SummaryReview(target: target, analysisID: analysis.id, payload: payload,
      credentialDigest: SHA256.hash(data: Data(key.utf8)))
  }

  private func send(_ review: SummaryReview) {
    guard scene == .active, consent?.id == review.id, let analysis, analysis.id == review.analysisID else { return }
    self.consent = nil
    let consent = review.target
    do {
      guard try authorized(consent, analysis: analysis), let key = store.apiKey(for: consent.model),
            CloudModelCredentialPolicy.isStoredCredential(key),
            SHA256.hash(data: Data(key.utf8)) == review.credentialDigest,
            let contact = providers.first(where: { $0.id == consent.contactID })
      else { throw GalaxySSIHealthAnalysis.Failure.invalid }
      let request = try GalaxySSIHealthSummaryTransport.request(endpoint: consent.endpoint, model: consent.model.modelId,
                                                                apiKey: key, aggregates: review.payload)
      let ledger = coordinator.healthDisclosureStore
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: analysis.trend == nil ? "Explicit health summary" : "Explicit filtered health trend summary",
        textSummary: .init(characters: String(decoding: review.payload, as: UTF8.self).count,
          kinds: [.systemInstructions, .toolOutput]))
      guard ticket.allowed else { error = true; return }
      let id = UUID()
      requestID = id
      error = false
      recommendation = nil
      task = Task {
        var disclosure: AgentDisclosureStatus = .failed
        defer {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: disclosure,
            failureReason: disclosure == .failed ? "health_request_not_completed" : "")
          if requestID == id { task = nil; requestID = nil }
        }
        do {
          guard try authorized(consent, analysis: analysis), store.apiKey(for: consent.model) == key, !Task.isCancelled else {
            throw GalaxySSIHealthAnalysis.Failure.invalid
          }
          let response = try await GalaxySSIHealthSummaryTransport.send(request)
          disclosure = .sent
          guard requestID == id, !Task.isCancelled else { return }
          guard try authorized(consent, analysis: analysis), store.apiKey(for: consent.model) == key else {
            refreshPermissions()
            stale = true
            return
          }
          recommendation = try analysis.recommendation(response)
        } catch {
          guard requestID == id, !Task.isCancelled else { return }
          error = true
        }
      }
    } catch { error = true }
  }

  private func authorized(_ consent: Consent, analysis: GalaxySSIHealthAnalysis) throws -> Bool {
    let archive = try records.load()
    let profileCurrent = try profileIsCurrent(archive)
    return scene == .active && store.profile.identityFingerprint == records.owner &&
      !coordinator.healthDisclosureStore.blockedDestinationIds().contains(consent.contactID) &&
      (trendScope == nil || trendScope?.spec.calendar.timeZone == timeZone) && consent.contactID == modelContactID &&
      providers.first(where: { $0.id == consent.contactID })?.selectedCloudModel == consent.model &&
      archive.derivesOverview == true && archive.healthOnlinePermission == consent.permission &&
      analysis.isCurrent(archive.current) && profileCurrent
  }

  private func prepareFollowUp() {
    guard task == nil, let analysis, let permission = online,
          let model = followUpModels[followUpProvider],
          let endpoint = GalaxySSIHealthFollowUpTransport.endpoint(for: model) else { return }
    let target = Consent(contactID: followUpProvider, model: model, endpoint: endpoint, permission: permission)
    do {
      let ledger = coordinator.healthDisclosureStore
      if let result = followUpResult,
         followUpModels[result.target.contactID] != result.target.model ||
           ledger.blockedDestinationIds().contains(result.target.contactID) {
        followUpResult = nil
      }
      let packet = try GalaxySSIHealthFollowUp(analysis: analysis, baseline: comparison, question: followUpDraft,
                                               previous: followUpResult?.answer)
      guard try authorizedFollowUp(target, analysisID: packet.analysisID) else { invalidateFollowUp(); return }
      guard let key = store.apiKey(for: model), CloudModelCredentialPolicy.isStoredCredential(key) else {
        followUpNotice = .unavailable; return
      }
      followUpNotice = nil
      followUpReview = FollowUpReview(target: target, packet: packet, credentialDigest: SHA256.hash(data: Data(key.utf8)))
    } catch { followUpNotice = .unavailable }
  }

  private func sendFollowUp(_ review: FollowUpReview) {
    guard task == nil, followUpReview?.id == review.id else { return }
    followUpReview = nil
    let target = review.target
    let ledger = coordinator.healthDisclosureStore
    do {
      guard try authorizedFollowUp(target, analysisID: review.packet.analysisID) else { invalidateFollowUp(); return }
      guard let contact = followUpContacts.first(where: { $0.id == target.contactID }),
            let key = store.apiKey(for: target.model), CloudModelCredentialPolicy.isStoredCredential(key)
      else { followUpNotice = .unavailable; return }
      guard SHA256.hash(data: Data(key.utf8)) == review.credentialDigest else { invalidateFollowUp(); return }
      let request = try GalaxySSIHealthFollowUpTransport.request(model: target.model, key: key, packet: review.packet)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Explicit health analysis follow-up",
        textSummary: .init(characters: String(decoding: review.packet.payload, as: UTF8.self).count,
                           kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { followUpNotice = .blocked; return }
      let id = UUID()
      requestID = id
      followUpRequest = target
      followUpDraft = ""
      followUpProvider = ""
      followUpNotice = nil
      task = Task {
        var disclosure: AgentDisclosureStatus = .failed
        defer {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: disclosure,
            failureReason: disclosure == .failed ? "health_request_not_completed" : "")
          if requestID == id { task = nil; requestID = nil; followUpRequest = nil }
        }
        do {
          guard requestID == id, !Task.isCancelled else { return }
          guard try authorizedFollowUp(target, analysisID: review.packet.analysisID), store.apiKey(for: target.model) == key
          else { invalidateFollowUp(); return }
          guard !ledger.blockedDestinationIds().contains(target.contactID) else {
            disclosure = .blocked; followUpNotice = .blocked; return
          }
          let bytes = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 65_536)
          disclosure = .sent
          guard requestID == id, !Task.isCancelled else { return }
          guard try authorizedFollowUp(target, analysisID: review.packet.analysisID), store.apiKey(for: target.model) == key
          else { invalidateFollowUp(); return }
          guard !ledger.blockedDestinationIds().contains(target.contactID) else {
            followUpResult = nil; followUpNotice = .blocked; return
          }
          let output = try GalaxySSIHealthFollowUpTransport.output(bytes, style: target.model.apiStyle)
          let answer = try review.packet.answer(output)
          followUpResult = FollowUpResult(target: target, analysisID: review.packet.analysisID,
                                          comparisons: review.packet.comparisons, answer: answer)
        } catch {
          if requestID == id, !Task.isCancelled { followUpNotice = .unavailable }
        }
      }
    } catch { followUpNotice = .unavailable }
  }

  private func authorizedFollowUp(_ target: Consent, analysisID: UUID) throws -> Bool {
    guard scene == .active, store.profile.identityFingerprint == records.owner,
          let analysis, analysis.id == analysisID, followUpModels[target.contactID] == target.model
    else { return false }
    let archive = try records.load()
    let profileCurrent = try profileIsCurrent(archive)
    return archive.derivesOverview == true && archive.healthOnlinePermission == target.permission &&
      (trendScope == nil || trendScope?.spec.calendar.timeZone == timeZone) &&
      analysis.isCurrent(archive.current) && comparison?.isCurrent(archive.current) != false &&
      profileCurrent
  }

  private func validateFollowUpResult(_ result: FollowUpResult) -> Bool {
    guard (try? authorizedFollowUp(result.target, analysisID: result.analysisID)) == true else {
      invalidateFollowUp()
      return false
    }
    guard !coordinator.healthDisclosureStore.blockedDestinationIds().contains(result.target.contactID) else {
      followUpResult = nil; followUpNotice = .blocked
      return false
    }
    return true
  }

  private func invalidateChangedFollowUpTarget() {
    let targets = [followUpRequest, followUpReview?.target, followUpResult?.target].compactMap { $0 }
    if targets.contains(where: { followUpModels[$0.contactID] != $0.model }) { invalidateFollowUp() }
  }

  private func invalidateFollowUp() {
    if followUpRequest != nil { cancelRequest() }
    clearFollowUp()
    evidence = nil
    followUpNotice = .invalidated
  }

  private func profileIsCurrent(_ archive: GalaxySSIHealthRecords.Archive) throws -> Bool {
    guard let profileContext else { return true }
    return profileContext.isCurrent(profile: try records.loadProfile(), permission: archive.profileAnalysisPermission)
  }

  private func cancelRequest() {
    task?.cancel(); task = nil; requestID = nil; consent = nil
    followUpRequest = nil; followUpReview = nil
  }

  private func clear() {
    cancelRequest()
    analysis = nil; evidence = nil; recommendation = nil; stale = false; error = false
    reportScope = nil
    profileContext = nil
    comparison = nil
    clearFollowUp()
  }

  private func clearFollowUp() {
    followUpDraft = ""; followUpProvider = ""; followUpReview = nil; followUpResult = nil; followUpNotice = nil
    reminderRecord = nil; followUpReminder = false
  }

  private func clearBackgroundSelection() {
    backgroundSelection = [:]
    choosingBackground = false
  }

  private func sourceValue(_ component: String, reading: GalaxySSIHealthReading) -> Decimal? {
    switch component {
    case "diastolic": return reading.diastolic
    case "pulse": return reading.pulse
    default: return reading.value
    }
  }

  private func component(_ name: String) -> String {
    switch name {
    case "systolic": return " · " + t("systolic", "Systolic")
    case "diastolic": return " · " + t("diastolic", "Diastolic")
    case "pulse": return " · " + t("pulse", "Pulse")
    default: return ""
    }
  }

  private func nextStep(_ value: GalaxySSIHealthAnalysis.Recommendation.NextStep) -> String {
    switch value {
    case .reviewSources: return t("step_review", "Review the source records")
    case .collectMore: return t("step_collect", "Review coverage gaps")
    case .comparePeriods: return t("step_compare", "Compare another period")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.assistant." + key, fallback: fallback, language: language)
  }
}
