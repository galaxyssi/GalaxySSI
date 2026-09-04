import Combine
import SwiftUI

@MainActor
final class GalaxySSIAgentEvalBenchmarkModel: ObservableObject {
  @Published var session: AgentBenchmarkSession?
  @Published var scorecard: AgentBenchmarkScorecard?
  @Published var progress = AgentBenchmarkProgress(
    completedTrials: 0, expectedTrials: 0, completedCampaigns: 0, totalCampaigns: 60, terminal: true
  )
  @Published var status = ""
  @Published var isStarting = false

  let suite = AgentEvalBenchmarkCatalog.standard
  private let benchmarkStore = AgentBenchmarkStore()
  private let labStore = AgentLabStore()

  func refresh() {
    session = benchmarkStore.sessions().first
    guard let session else {
      scorecard = nil
      progress = AgentBenchmarkProgress(
        completedTrials: 0, expectedTrials: 0, completedCampaigns: 0,
        totalCampaigns: suite.cases.count, terminal: true
      )
      return
    }
    scorecard = AgentBenchmarkStatistics.scorecard(
      session: session,
      suite: suite,
      allResults: benchmarkStore.results(sessionId: session.id)
    )
    let campaigns = session.campaignIdsByCase.values.compactMap { labStore.get(id: $0) }
    let terminalCampaigns = campaigns.filter { [.readyForReview, .completed, .cancelled].contains($0.status) }.count
    progress = AgentBenchmarkProgress(
      completedTrials: campaigns.reduce(0) { value, campaign in
        value + campaign.trials.filter { [.completed, .failed, .cancelled].contains($0.status) }.count
      },
      expectedTrials: session.expectedTrials,
      completedCampaigns: terminalCampaigns,
      totalCampaigns: session.caseIds.count,
      terminal: session.status != .running ||
        (campaigns.count == session.caseIds.count && terminalCampaigns == campaigns.count)
    )
    if progress.terminal, session.status == .running {
      self.session = benchmarkStore.markStatus(id: session.id, status: .completed)
    }
  }

  func start(repetitions: Int) async {
    guard !isStarting else { return }
    guard let runtime = AgentEvolutionLabRuntimeRegistry.shared.current() else {
      status = "Agent Lab runtime is unavailable"
      return
    }
    isStarting = true
    defer { isStarting = false }
    do {
      let coordinator = AgentBenchmarkCoordinator(labRuntime: runtime)
      session = try await coordinator.startCodexDeepSeek90To10(repetitions: repetitions)
      status = "Real Agent benchmark started"
      refresh()
    } catch {
      status = error.localizedDescription
    }
  }

  func cancel() async {
    guard let session, let runtime = AgentEvolutionLabRuntimeRegistry.shared.current() else { return }
    let coordinator = AgentBenchmarkCoordinator(labRuntime: runtime)
    if await coordinator.cancel(sessionId: session.id) {
      status = "Benchmark cancelled"
      refresh()
    }
  }
}

struct GalaxySSIAgentEvalBenchmarkView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @StateObject private var model = GalaxySSIAgentEvalBenchmarkModel()
  @State private var repetitions = 3
  @State private var showsStartConfirmation = false
  private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_benchmark_title", "Real Agent benchmark"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("agent_benchmark_hero", "Codex and DeepSeek EvalOps"),
            subtitle: t("agent_benchmark_hero_subtitle", "60 fixed tasks across quality, tools, iOSWorld, memory, recovery, and collaboration"),
            systemImage: "checkmark.seal",
            tint: .galaxySSIInsightText,
            badge: "v\(model.suite.version)"
          )
          configurationSection
          progressSection
          scoreSection
          dimensionSection
          resourceSection
          if !model.status.isEmpty {
            Text(model.status).font(.system(size: 13)).foregroundColor(.galaxySSITextSecondary).padding(.horizontal, 4)
          }
        }
        .padding(12)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear { model.refresh() }
    .onReceive(refreshTimer) { _ in if model.session?.status == .running { model.refresh() } }
    .alert(t("agent_benchmark_confirm_title", "Start the complete benchmark?"), isPresented: $showsStartConfirmation) {
      Button(t("common_cancel", "Cancel"), role: .cancel) {}
      Button(t("common_start", "Start")) { Task { await model.start(repetitions: repetitions) } }
    } message: {
      Text(t("agent_benchmark_confirm_message", "This launches real Agent requests and tool calls. It can take a long time and may incur provider charges."))
    }
  }

  private var configurationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_benchmark_section_suite", "FIXED SUITE"))
      VStack(spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(t("agent_benchmark_allocation", "Resource allocation")).font(.system(size: 16, weight: .medium))
            Text(t("agent_benchmark_allocation_detail", "54 Codex tasks and 6 DeepSeek tasks; 9:1 in every dimension"))
              .font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
          }
          Spacer()
          Text("90/10").font(.system(size: 15, weight: .semibold)).foregroundColor(.galaxySSIAccent)
        }
        Picker(t("agent_benchmark_repetitions", "Repetitions"), selection: $repetitions) {
          Text("3").tag(3)
          Text("5").tag(5)
          Text("10").tag(10)
        }
        .pickerStyle(.segmented)
        Button {
          showsStartConfirmation = true
        } label: {
          HStack {
            if model.isStarting { ProgressView().tint(.white) }
            Image(systemName: "play.fill")
            Text(t("agent_benchmark_start", "Start real benchmark"))
          }
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.galaxySSIAccent)
        .disabled(model.isStarting || (model.session?.status == .running && !model.progress.terminal))
      }
      .padding(14)
      .background(Color.galaxySSICardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var progressSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_benchmark_section_progress", "RUN PROGRESS"))
      VStack(spacing: 10) {
        ProgressView(value: Double(model.progress.completedTrials), total: Double(max(model.progress.expectedTrials, 1)))
          .tint(.galaxySSIAccent)
        HStack {
          Text("\(model.progress.completedTrials)/\(model.progress.expectedTrials) " + t("agent_benchmark_trials", "trials"))
          Spacer()
          Text("\(model.progress.completedCampaigns)/\(model.progress.totalCampaigns) " + t("agent_benchmark_tasks", "tasks"))
        }
        .font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
        if model.session?.status == .running && !model.progress.terminal {
          Button(role: .destructive) { Task { await model.cancel() } } label: {
            Label(t("agent_benchmark_cancel", "Cancel benchmark"), systemImage: "stop.circle")
          }
        }
      }
      .padding(14)
      .background(Color.galaxySSICardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var scoreSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_benchmark_section_score", "EVIDENCE SCORE"))
      HStack(spacing: 1) {
        metric(model.scorecard?.overall.passAt1, "pass@1")
        metric(model.scorecard?.overall.passPowerK, "pass^k")
        metric(model.scorecard.map { Double($0.overall.verifiedTrials) / Double(max($0.overall.expectedTrials, 1)) },
          t("agent_benchmark_verified", "Verified"))
      }
      .background(Color.galaxySSICardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text(model.scorecard?.overall.qualified == true
        ? t("agent_benchmark_qualified", "Complete and qualified")
        : t("agent_benchmark_provisional", "Provisional until every assigned trial is verified"))
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(model.scorecard?.overall.qualified == true ? .galaxySSIAccent : .orange)
        .padding(.horizontal, 4)
    }
  }

  private var dimensionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_benchmark_section_dimensions", "SIX DIMENSIONS"))
      ForEach(model.scorecard?.dimensions ?? emptyDimensions) { metric in
        GalaxySSISecurityStatusRow(
          title: dimensionName(metric.dimension),
          subtitle: "\(metric.coveredTaskCount)/\(metric.taskCount) " + t("agent_benchmark_tasks_covered", "tasks covered"),
          systemImage: dimensionIcon(metric.dimension),
          tint: metric.targetMet ? .galaxySSIAccent : .blue,
          badge: percent(metric.passAt1)
        )
      }
    }
  }

  private var resourceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_benchmark_section_resources", "RESOURCE SNAPSHOTS"))
      ForEach(model.scorecard?.resources ?? []) { score in
        GalaxySSISecurityStatusRow(
          title: score.resource.displayName.ifBlank(score.resource.resourceId),
          subtitle: score.resource.modelId.ifBlank(score.resource.providerId),
          systemImage: "cpu",
          tint: .purple,
          badge: percent(score.overall.passAt1)
        )
      }
    }
  }

  private func metric(_ value: Double?, _ label: String) -> some View {
    VStack(spacing: 4) {
      Text(percent(value)).font(.system(size: 20, weight: .semibold))
      Text(label).font(.system(size: 11)).foregroundColor(.galaxySSITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 70)
  }

  private var emptyDimensions: [AgentBenchmarkMetric] {
    AgentBenchmarkDimension.allCases.map {
      AgentBenchmarkMetric(dimension: $0, taskCount: 10, coveredTaskCount: 0, expectedTrials: 0,
        completedTrials: 0, verifiedTrials: 0, passAt1: nil, passPowerK: nil, averageLatencyMillis: 0,
        averageReportedCostMicros: 0, averageBatteryDeltaPercent: 0, peakThermalStatus: -1,
        qualified: false, targetMet: false)
    }
  }

  private func dimensionName(_ dimension: AgentBenchmarkDimension?) -> String {
    switch dimension {
    case .taskQuality: return t("agent_benchmark_dimension_quality", "Task quality")
    case .planningAndTools: return t("agent_benchmark_dimension_tools", "Planning and tools")
    case .iosWorld: return "iOSWorld"
    case .longTermMemory: return t("agent_benchmark_dimension_memory", "Long-term memory")
    case .recovery: return t("agent_benchmark_dimension_recovery", "Recovery")
    case .multiAgent: return t("agent_benchmark_dimension_multi", "Multi-Agent collaboration")
    case nil: return t("agent_benchmark_overall", "Overall")
    }
  }

  private func dimensionIcon(_ dimension: AgentBenchmarkDimension?) -> String {
    switch dimension {
    case .taskQuality: return "checkmark.circle"
    case .planningAndTools: return "wrench.and.screwdriver"
    case .iosWorld: return "iphone"
    case .longTermMemory: return "brain"
    case .recovery: return "arrow.clockwise"
    case .multiAgent: return "person.2"
    case nil: return "chart.bar"
    }
  }

  private func percent(_ value: Double?) -> String {
    value.map { String(format: "%.0f%%", $0 * 100) } ?? "--"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
