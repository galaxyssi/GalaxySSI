import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GalaxySSIAgentEvolutionLabModel: ObservableObject {
  @Published var campaigns: [AgentLabCampaign] = []
  @Published var agents: [AgentRegistration] = []
  @Published var dashboard = AgentEvalStatistics.dashboard(samples: [])
  @Published var settings = AgentEvalOpsSettings()
  @Published var attention: [AgentAttentionDecisionRecord] = []
  @Published var worldTasks: [AgentIOSWorldTask] = []
  @Published var worldResults: [AgentIOSWorldResult] = []
  @Published var protocolGrants: [AgentProtocolEndpointGrant] = []
  @Published var shadowReleases: [AgentShadowRelease] = []
  @Published var status = ""

  private let labStore = AgentLabStore()
  private let evalStore = AgentEvalOpsStore()
  private let attentionStore = AgentAttentionDecisionStore()
  private let worldStore = AgentIOSWorldStore()
  private let grantStore = AgentProtocolEndpointGrantStore()
  private let releaseStore = AgentShadowReleaseStore()

  func refresh() {
    campaigns = labStore.list()
    dashboard = evalStore.dashboard()
    settings = evalStore.settings()
    attention = attentionStore.list(limit: 20)
    worldTasks = worldStore.tasks(limit: 50)
    worldResults = worldStore.results(limit: 50)
    protocolGrants = grantStore.list()
    shadowReleases = releaseStore.list()
    Task {
      do {
        agents = try await AgentEvolutionLabRuntimeRegistry.shared.current()?.availableAgents() ?? []
      } catch {
        status = error.localizedDescription
      }
    }
  }

  func updateSettings(_ transform: (inout AgentEvalOpsSettings) -> Void) {
    settings = evalStore.updateSettings { current in
      var current = current
      transform(&current)
      return current
    }
  }

  func create(task: String, agentIds: [String], repetitions: Int) async -> Bool {
    guard let runtime = AgentEvolutionLabRuntimeRegistry.shared.current() else {
      status = "Agent Lab runtime is unavailable"
      return false
    }
    do {
      _ = try await runtime.createAndStart(task: task, agentIds: agentIds, repetitions: repetitions)
      status = "Campaign started"
      refresh()
      return true
    } catch {
      status = error.localizedDescription
      return false
    }
  }

  func cancel(_ campaign: AgentLabCampaign) {
    Task {
      _ = await AgentEvolutionLabRuntimeRegistry.shared.current()?.cancel(campaignId: campaign.id)
      refresh()
    }
  }

  func selectWinner(campaignId: String, trialId: String) {
    _ = labStore.selectWinner(campaignId: campaignId, trialId: trialId)
    refresh()
  }

  func blindResults(_ campaign: AgentLabCampaign) -> [AgentLabBlindResult] {
    labStore.blindResults(campaignId: campaign.id, evalStore: evalStore)
  }

  func importWorldTasks(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let tasks = try AgentIOSWorldCodec.decodeTasks(Data(contentsOf: url), source: url.lastPathComponent)
      let count = worldStore.importTasks(tasks)
      status = "Imported \(count) iOSWorld tasks"
      refresh()
    } catch {
      status = error.localizedDescription
    }
  }
}

struct GalaxySSIAgentEvolutionLabView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @StateObject private var model = GalaxySSIAgentEvolutionLabModel()
  @State private var showsNewCampaign = false
  @State private var showsImporter = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_lab_title", "Personal Agent Lab"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Button { showsNewCampaign = true } label: {
            Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
          }
          .accessibilityLabel(t("agent_lab_new_campaign", "New campaign"))
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("agent_lab_hero_title", "Test Agents before trusting them"),
            subtitle: t("agent_lab_hero_subtitle", "Blind trials, programmatic verification, recovery tests, and shadow releases"),
            systemImage: "flask",
            tint: .galaxySSIInsightText,
            badge: t("agent_lab_badge", "On device")
          )
          metricsSection
          campaignsSection
          evaluationSettingsSection
          governanceSection
          worldSection
          protocolSection
          releaseSection
          if !model.status.isEmpty {
            Text(model.status)
              .font(.system(size: 13))
              .foregroundColor(.galaxySSITextSecondary)
              .padding(.horizontal, 4)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $showsNewCampaign) {
      AgentLabNewCampaignSheet(model: model, language: interfaceLanguage)
    }
    .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
      model.importWorldTasks(result)
    }
    .onAppear { model.refresh() }
  }

  private var metricsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_evidence", "EVALUATION EVIDENCE"))
      HStack(spacing: 1) {
        AgentLabMetric(value: "\(model.dashboard.verifiedRuns)", label: t("agent_lab_verified_runs", "Verified runs"))
        AgentLabMetric(value: percent(model.dashboard.passAt1), label: "pass@1")
        AgentLabMetric(value: percent(model.dashboard.passPowerK), label: "pass^k")
        AgentLabMetric(value: percent(model.dashboard.recoveryRate), label: t("agent_lab_recovery", "Recovery"))
      }
      .background(Color.galaxySSICardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var campaignsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_campaigns", "BLIND CAMPAIGNS"))
      if model.campaigns.isEmpty {
        GalaxySSISecurityActionRow(
          title: t("agent_lab_no_campaigns", "No campaigns yet"),
          subtitle: t("agent_lab_no_campaigns_subtitle", "Compare at least two available Agents on the same task"),
          systemImage: "plus.circle",
          tint: .galaxySSIAccent,
          badge: t("common_add", "Add")
        ) { showsNewCampaign = true }
      } else {
        ForEach(model.campaigns) { campaign in
          NavigationLink {
            AgentLabCampaignDetailView(campaignId: campaign.id, model: model, language: interfaceLanguage)
          } label: {
            AgentLabCampaignRow(campaign: campaign, cancel: { model.cancel(campaign) })
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var evaluationSettingsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_runtime", "EVALUATION AND ROUTING"))
      AgentLabToggleRow(
        title: t("agent_lab_capture_runs", "Capture real Agent runs"),
        subtitle: t("agent_lab_capture_runs_subtitle", "Store encrypted outcome contracts and evidence"),
        isOn: model.settings.captureRealRuns
      ) { value in model.updateSettings { $0.captureRealRuns = value } }
      AgentLabToggleRow(
        title: t("agent_lab_continuous_eval", "Continuous evaluation"),
        subtitle: t("agent_lab_continuous_eval_subtitle", "Measure completed runs in the background"),
        isOn: model.settings.continuousEvaluationEnabled
      ) { value in model.updateSettings { $0.continuousEvaluationEnabled = value } }
      AgentLabToggleRow(
        title: t("agent_lab_shadow_routing", "Shadow routing"),
        subtitle: t("agent_lab_shadow_routing_subtitle", "Compare candidates without changing the live answer"),
        isOn: model.settings.shadowRoutingEnabled
      ) { value in model.updateSettings { $0.shadowRoutingEnabled = value } }
      AgentLabToggleRow(
        title: t("agent_lab_quality_routing", "Automatic quality routing"),
        subtitle: t("agent_lab_quality_routing_subtitle", "Route only after enough verified samples"),
        isOn: model.settings.automaticQualityRoutingEnabled
      ) { value in model.updateSettings { $0.automaticQualityRoutingEnabled = value } }
      AgentLabStepperRow(
        title: t("agent_lab_repetitions", "Repeated trials"),
        value: model.settings.repeatedTrials,
        range: 2...10
      ) { value in model.updateSettings { $0.repeatedTrials = value } }
      AgentLabSliderRow(
        title: t("agent_lab_attention_threshold", "Attention threshold"),
        value: model.settings.attentionThreshold
      ) { value in model.updateSettings { $0.attentionThreshold = value } }
    }
  }

  private var governanceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_governance", "COGNITIVE GOVERNANCE"))
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_attention_history", "Attention decisions"),
        subtitle: t("agent_lab_attention_history_subtitle", "Why a proactive insight notified, digested, or stayed silent"),
        systemImage: "bell.badge",
        tint: .orange,
        badge: "\(model.attention.count)"
      )
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_failure_memory", "Failure memory"),
        subtitle: t("agent_lab_failure_memory_subtitle", "Verified failures guide future planning without copying private content"),
        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
        tint: .red,
        badge: "\(AgentFailureMemoryStore().list(activeOnly: true).count)"
      )
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_knowledge_gaps", "Knowledge gaps"),
        subtitle: t("agent_lab_knowledge_gaps_subtitle", "Missing evidence is tracked for later research"),
        systemImage: "questionmark.diamond",
        tint: .galaxySSIInsightText,
        badge: "\(AgentCognitiveGovernanceStore().gaps(status: .open).count)"
      )
    }
  }

  private var worldSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_iosworld", "IOSWORLD VERIFIERS"))
      GalaxySSISecurityActionRow(
        title: t("agent_lab_import_iosworld", "Import verification tasks"),
        subtitle: t("agent_lab_import_iosworld_subtitle", "JSON tasks verify screens, text, app files, and app settings"),
        systemImage: "square.and.arrow.down",
        tint: .blue,
        badge: "\(model.worldTasks.count)"
      ) { showsImporter = true }
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_iosworld_results", "Programmatic results"),
        subtitle: t("agent_lab_iosworld_results_subtitle", "Deterministic evidence linked to Agent runs"),
        systemImage: "checkmark.seal",
        tint: .galaxySSIAccent,
        badge: "\(model.worldResults.filter(\.passed).count)/\(model.worldResults.count)"
      )
    }
  }

  private var protocolSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_protocols", "PROTOCOL TRUST BOUNDARIES"))
      AgentLabToggleRow(
        title: t("agent_lab_protocol_adapters", "ACP and A2A adapters"),
        subtitle: t("agent_lab_protocol_adapters_subtitle", "Require an endpoint fingerprint and capability grant"),
        isOn: model.settings.protocolAdaptersEnabled
      ) { value in model.updateSettings { $0.protocolAdaptersEnabled = value } }
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_authorized_endpoints", "Authorized endpoints"),
        subtitle: t("agent_lab_authorized_endpoints_subtitle", "Encrypted grants with explicit capability scopes"),
        systemImage: "lock.shield",
        tint: .galaxySSIAccent,
        badge: "\(model.protocolGrants.filter(\.enabled).count)"
      )
    }
  }

  private var releaseSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_lab_section_releases", "SHADOW RELEASES"))
      AgentLabToggleRow(
        title: t("agent_lab_shadow_release", "Shadow release gate"),
        subtitle: t("agent_lab_shadow_release_subtitle", "Require evidence and approval before promotion"),
        isOn: model.settings.shadowReleaseEnabled
      ) { value in model.updateSettings { $0.shadowReleaseEnabled = value } }
      GalaxySSISecurityStatusRow(
        title: t("agent_lab_release_candidates", "Release candidates"),
        subtitle: t("agent_lab_release_candidates_subtitle", "Device shadow metrics, rollback rules, and approval state"),
        systemImage: "shippingbox",
        tint: .purple,
        badge: "\(model.shadowReleases.count)"
      )
    }
  }

  private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentLabMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value).font(.system(size: 20, weight: .semibold))
      Text(label).font(.system(size: 11)).foregroundColor(.galaxySSITextSecondary).lineLimit(1).minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, minHeight: 70)
  }
}

private struct AgentLabCampaignRow: View {
  let campaign: AgentLabCampaign
  let cancel: () -> Void

  private var finished: Int {
    campaign.trials.filter { [.completed, .failed, .cancelled].contains($0.status) }.count
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: campaign.status == .running ? "hourglass" : "flask")
        .foregroundColor(.galaxySSIInsightText)
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 4) {
        Text(campaign.task).font(.system(size: 16, weight: .medium)).lineLimit(2)
        Text("\(finished)/\(campaign.trials.count) · \(campaign.status.rawValue.replacingOccurrences(of: "_", with: " "))")
          .font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
      }
      Spacer()
      if campaign.status == .running {
        Button(action: cancel) { Image(systemName: "stop.circle") }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel")
      }
      Image(systemName: "chevron.right").foregroundColor(.galaxySSITextSecondary)
    }
    .padding(14)
    .background(Color.galaxySSICardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentLabToggleRow: View {
  let title: String
  let subtitle: String
  let isOn: Bool
  let update: (Bool) -> Void

  var body: some View {
    Toggle(isOn: Binding(get: { isOn }, set: update)) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 16))
        Text(subtitle).font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
      }
    }
    .tint(.galaxySSIAccent)
    .padding(14)
    .background(Color.galaxySSICardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentLabStepperRow: View {
  let title: String
  let value: Int
  let range: ClosedRange<Int>
  let update: (Int) -> Void

  var body: some View {
    Stepper(value: Binding(get: { value }, set: update), in: range) {
      HStack { Text(title); Spacer(); Text("\(value)").foregroundColor(.galaxySSIAccent) }
    }
    .padding(14)
    .background(Color.galaxySSICardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentLabSliderRow: View {
  let title: String
  let value: Double
  let update: (Double) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack { Text(title); Spacer(); Text(String(format: "%.2f", value)).foregroundColor(.galaxySSIAccent) }
      Slider(value: Binding(get: { value }, set: update), in: 0...1, step: 0.01)
        .tint(.galaxySSIAccent)
    }
    .padding(14)
    .background(Color.galaxySSICardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentLabNewCampaignSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: GalaxySSIAgentEvolutionLabModel
  let language: String
  @State private var task = ""
  @State private var selected = Set<String>()
  @State private var repetitions = 3

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text(t("agent_lab_task", "Task"))) {
          TextEditor(text: $task).frame(minHeight: 100)
        }
        Section(header: Text(t("agent_lab_agents", "Agents"))) {
          ForEach(model.agents) { agent in
            Button {
              if selected.contains(agent.agentId) { selected.remove(agent.agentId) } else { selected.insert(agent.agentId) }
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text(agent.displayName.ifBlank(agent.agentId))
                  Text(agent.agentId).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected.contains(agent.agentId) { Image(systemName: "checkmark.circle.fill").foregroundColor(.galaxySSIAccent) }
              }
            }
          }
        }
        Section {
          Stepper(
            String(format: t("agent_lab_trial_count", "Repetitions: %d"), repetitions),
            value: $repetitions,
            in: 1...10
          )
        }
      }
      .navigationTitle(t("agent_lab_new_campaign", "New campaign"))
      .navigationBarItems(
        leading: Button(t("common_cancel", "Cancel")) { dismiss() },
        trailing: Button(t("common_start", "Start")) {
          Task { if await model.create(task: task, agentIds: Array(selected), repetitions: repetitions) { dismiss() } }
        }.disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.count < 2)
      )
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct AgentLabCampaignDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let campaignId: String
  @ObservedObject var model: GalaxySSIAgentEvolutionLabModel
  let language: String

  private var campaign: AgentLabCampaign? { model.campaigns.first { $0.id == campaignId } }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(title: t("agent_lab_blind_review", "Blind review"), leading: { GalaxySSIBackButton() }, trailing: { Color.clear })
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if let campaign {
            Text(campaign.task).font(.system(size: 18, weight: .semibold)).padding(.horizontal, 4)
            ForEach(model.blindResults(campaign)) { result in
              Button { model.selectWinner(campaignId: campaign.id, trialId: result.trialId) } label: {
                VStack(alignment: .leading, spacing: 7) {
                  HStack {
                    Text(result.label).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(result.verdict.rawValue).foregroundColor(result.verdict == .passed ? .galaxySSIAccent : .orange)
                  }
                  if !result.outputPreview.isEmpty { Text(result.outputPreview).font(.system(size: 13)).lineLimit(8) }
                  Text("\(result.durationMillis) ms · tools \(result.toolEvidenceCount) · artifacts \(result.artifactEvidenceCount)")
                    .font(.caption).foregroundColor(.galaxySSITextSecondary)
                  if campaign.winnerTrialId == result.trialId {
                    Label(t("agent_lab_selected_winner", "Selected winner"), systemImage: "checkmark.seal.fill")
                      .font(.caption).foregroundColor(.galaxySSIAccent)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.galaxySSICardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(12)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear { model.refresh() }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
