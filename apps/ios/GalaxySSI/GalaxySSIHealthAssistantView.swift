import SwiftUI

@MainActor
struct GalaxySSIHealthAssistantView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
  @State private var to = Date()
  @State private var metrics: Set<GalaxySSIHealthMetric> = [.bloodPressure]
  @State private var analysis: GalaxySSIHealthAnalysis?
  @State private var evidence: GalaxySSIHealthAnalysis.Evidence?
  @State private var sourceLimit = 30
  @State private var enabled = false
  @State private var online: UUID?
  @State private var modelContactID = ""
  @State private var consent: Consent?
  @State private var confirming = false
  @State private var recommendation: GalaxySSIHealthAnalysis.Recommendation?
  @State private var task: Task<Void, Never>?
  @State private var requestID: UUID?
  @State private var error = false
  @State private var stale = false
  @State private var compare = false
  @State private var reportScope: GalaxySSIWeeklyHealthReport.Link?
  @State private var presentedReport: GalaxySSIWeeklyHealthReport.Link?

  private struct Consent {
    let contactID: String
    let model: CloudModelConfig
    let endpoint: URL
    let permission: UUID
  }

  private var providers: [GalaxySSIContact] {
    store.contacts.filter { contact in
      !contact.deleted && contact.selectedCloudModel.flatMap(GalaxySSIHealthSummaryTransport.endpoint(for:)) != nil
    }
  }

  var body: some View {
    List {
      if scene == .active {
        if enabled {
          scopeSection
          if let analysis {
            analysisSection(analysis)
            providerSection(analysis)
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
    .onAppear(perform: refreshPermissions)
    .onChange(of: from) { _ in clear() }
    .onChange(of: to) { _ in clear() }
    .onChange(of: metrics) { _ in clear() }
    .onChange(of: compare) { _ in clear() }
    .onChange(of: modelContactID) { _ in cancelRequest(); recommendation = nil }
    .onDisappear { clear() }
    .onChange(of: scene) {
      if $0 == .active { refreshPermissions() } else { clear(); enabled = false; online = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { refreshPermissions() }
    }
    .confirmationDialog(t("confirm", "Send selected aggregates to this provider?"),
                        isPresented: $confirming, titleVisibility: .visible) {
      Button(t("send", "Send aggregates"), action: send)
    } message: {
      if let consent {
        Text(consent.endpoint.absoluteString + "\n" + consent.model.modelId + "\n" +
          t("disclosure", "Only metric aggregates and coverage are sent. No records, dates, notes, profile or chat history."))
      }
    }
    .sheet(item: $presentedReport) { report in
      NavigationView {
        GalaxySSIWeeklyHealthReportView(records: records, link: report)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { presentedReport = nil }
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
  }

  private var scopeSection: some View {
    Section(t("scope", "Analysis scope")) {
      DatePicker(t("from", "From"), selection: $from, in: ...Date(), displayedComponents: .date)
      DatePicker(t("to", "Through"), selection: $to, in: ...Date(), displayedComponents: .date)
      Toggle(t("compare_previous", "Compare with the previous period in the report"), isOn: $compare)
      DisclosureGroup(t("metrics", "Measurements")) {
        ForEach(GalaxySSIHealthMetric.allCases) { metric in
          Toggle(metric.title(language: language), isOn: Binding(get: { metrics.contains(metric) }, set: {
            if $0 { metrics.insert(metric) } else { metrics.remove(metric) }
          }))
          .disabled(metrics.count >= 6 && !metrics.contains(metric))
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
          if let low = aggregate.minimum, let high = aggregate.maximum, let mean = aggregate.mean {
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

  private func providerSection(_ analysis: GalaxySSIHealthAnalysis) -> some View {
    Section(t("online", "Optional online summary")) {
      Toggle(t("online_permission", "Allow requests for online summaries"), isOn: Binding(
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
        if task != nil { ProgressView(t("working", "Waiting for provider")) }
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

  private func calculate() {
    clear()
    guard scene == .active, !metrics.isEmpty else { return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true else { refreshPermissions(); return }
      var local = calendar
      local.timeZone = timeZone
      let first = local.startOfDay(for: from), last = local.startOfDay(for: to)
      guard first <= last, let end = local.date(byAdding: .day, value: 1, to: last),
            let days = local.dateComponents([.day], from: first, to: end).day, (1...90).contains(days)
      else { error = true; return }
      let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: first, end: end), metrics: metrics)
      analysis = GalaxySSIHealthAnalysis(scope: scope, current: archive.current, calendar: local)
      reportScope = .init(interval: scope.interval, metrics: scope.metrics, calendar: local,
                          compare: compare, current: archive.current)
    } catch { error = true }
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
      if online != archive.healthOnlinePermission { cancelRequest(); recommendation = nil }
      online = archive.healthOnlinePermission
      if let analysis, !enabled || !analysis.isCurrent(archive.current) {
        clear()
        stale = true
      }
    } catch { clear(); enabled = false; online = nil; error = true }
  }

  private func prepareSend() {
    guard scene == .active, let permission = online, analysis != nil,
          let contact = providers.first(where: { $0.id == modelContactID }),
          let model = contact.selectedCloudModel, let endpoint = GalaxySSIHealthSummaryTransport.endpoint(for: model)
    else { return }
    consent = Consent(contactID: contact.id, model: model, endpoint: endpoint, permission: permission)
    confirming = true
  }

  private func send() {
    guard scene == .active, let consent, let analysis else { return }
    self.consent = nil
    do {
      guard try authorized(consent, analysis: analysis), let key = store.apiKey(for: consent.model),
            CloudModelCredentialPolicy.isStoredCredential(key) else { throw GalaxySSIHealthAnalysis.Failure.invalid }
      let request = try GalaxySSIHealthSummaryTransport.request(endpoint: consent.endpoint, model: consent.model.modelId,
                                                                apiKey: key, aggregates: analysis.requestJSON())
      let id = UUID()
      requestID = id
      error = false
      recommendation = nil
      task = Task {
        do {
          guard try authorized(consent, analysis: analysis), !Task.isCancelled else {
            throw GalaxySSIHealthAnalysis.Failure.invalid
          }
          let response = try await GalaxySSIHealthSummaryTransport.send(request)
          guard requestID == id, !Task.isCancelled else { return }
          guard try authorized(consent, analysis: analysis) else {
            refreshPermissions()
            task = nil
            stale = true
            return
          }
          recommendation = try analysis.recommendation(response)
        } catch {
          guard requestID == id, !Task.isCancelled else { return }
          error = true
        }
        task = nil
      }
    } catch { error = true }
  }

  private func authorized(_ consent: Consent, analysis: GalaxySSIHealthAnalysis) throws -> Bool {
    let archive = try records.load()
    return scene == .active && consent.contactID == modelContactID &&
      providers.first(where: { $0.id == consent.contactID })?.selectedCloudModel == consent.model &&
      archive.derivesOverview == true && archive.healthOnlinePermission == consent.permission &&
      analysis.isCurrent(archive.current)
  }

  private func cancelRequest() {
    task?.cancel(); task = nil; requestID = nil; consent = nil; confirming = false
  }

  private func clear() {
    cancelRequest()
    analysis = nil; evidence = nil; recommendation = nil; stale = false; error = false
    reportScope = nil
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
