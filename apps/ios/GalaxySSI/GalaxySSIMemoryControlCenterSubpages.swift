import SwiftUI

struct GalaxySSIMemoryCategoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  var category: GalaxySSIMemoryCategoryDescriptor

  var body: some View {
    GalaxySSIMemoryListPage(
      title: t(category.titleKey, category.titleFallback),
      heroTitle: t(category.titleKey, category.titleFallback),
      heroSubtitle: t(category.subtitleKey, category.subtitleFallback),
      heroIcon: category.systemImage,
      heroTint: color(category.tone),
      heroBadge: "\(items.count)"
    ) {
      GalaxySSISecuritySectionTitle(title: t("cc_memory_section_categories", "Memory Categories"))
      if items.isEmpty {
        emptyRow(
          title: t("cc_memory_category_empty", "No saved memory in this category"),
          subtitle: t("cc_memory_category_empty_subtitle", "New durable context will appear here after capture or manual review"),
          icon: category.systemImage,
          tint: color(category.tone)
        )
      } else {
        ForEach(items) { item in
          memoryRow(item)
        }
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_memory_manage_title", "Manage all memories"),
        subtitle: t("cc_memory_manage_subtitle", "Review, edit, pin, resolve conflicts, or delete individual memories"),
        systemImage: "brain",
        tint: .purple,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIAgentMemoryView()
      }
    }
  }

  private var items: [AgentMemoryItem] {
    store.agentMemorySnapshot().activeItems
      .filter { category.kinds.contains($0.kind) }
      .sorted { $0.timestampMillis > $1.timestampMillis }
  }

  private func memoryRow(_ item: AgentMemoryItem) -> some View {
    GalaxySSISecurityStatusRow(
      title: compact(item.value),
      subtitle: memorySubtitle(item),
      systemImage: item.important ? "pin.fill" : category.systemImage,
      tint: item.important ? .orange : color(category.tone),
      badge: item.important ? t("galaxyssi.agent_memory.pinned", "Pinned") : memoryKindLabel(item.kind)
    )
  }

  private func memorySubtitle(_ item: AgentMemoryItem) -> String {
    String(
      format: t("galaxyssi.agent_memory.item_subtitle", "%@ / v%d / %@"),
      memoryKindLabel(item.kind),
      item.version,
      item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? t("galaxyssi.agent_memory.key_none", "Unkeyed")
        : item.key
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func memoryKindLabel(_ kind: AgentMemoryKind) -> String {
    GalaxySSIMemoryText.kindLabel(kind, language: interfaceLanguage)
  }
}

struct GalaxySSIMemoryLifecycleView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var inbox = GlobalMemoryInbox()
  @State private var auditReport = GlobalMemoryAuditReport()
  @State private var records: [GlobalMemoryEvolutionRecord] = []

  var state: GalaxySSIMemoryLifecycleState
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    GalaxySSIMemoryListPage(
      title: stateTitle,
      heroTitle: stateTitle,
      heroSubtitle: stateSubtitle,
      heroIcon: stateIcon,
      heroTint: color(stateTone),
      heroBadge: "\(items.count + candidates.count)"
    ) {
      GalaxySSISecuritySectionTitle(title: t("cc_memory_section_lifecycle", "Memory Lifecycle"))
      if items.isEmpty && candidates.isEmpty {
        emptyRow(
          title: t("cc_memory_lifecycle_empty", "No memory in this state"),
          subtitle: t("cc_memory_lifecycle_empty_subtitle", "The long-term model has no matching local records right now"),
          icon: stateIcon,
          tint: color(stateTone)
        )
      } else {
        ForEach(items) { item in
          GalaxySSISecurityStatusRow(
            title: compact(item.value),
            subtitle: memorySubtitle(item),
            systemImage: item.important ? "pin.fill" : stateIcon,
            tint: color(stateTone),
            badge: memoryKindLabel(item.kind)
          )
        }
        ForEach(candidates) { candidate in
          GalaxySSISecurityStatusRow(
            title: candidateTitle(candidate),
            subtitle: candidateSubtitle(candidate),
            systemImage: "tray",
            tint: candidate.status == .conflicted ? .orange : color(stateTone),
            badge: candidateRiskLabel(candidate.risk)
          )
        }
      }
    }
    .onAppear(perform: refresh)
  }

  private var snapshot: GalaxySSIMemoryControlSnapshot {
    GalaxySSIMemoryControlSnapshot.make(
      agentMemory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      inbox: inbox,
      evolutionRecords: records,
      auditReport: auditReport
    )
  }

  private var items: [AgentMemoryItem] {
    snapshot.items(for: state)
  }

  private var candidates: [GlobalMemoryCandidate] {
    snapshot.candidates(for: state)
  }

  private var stateTitle: String {
    switch state {
    case .current:
      return t("cc_memory_state_current_title", "Current state")
    case .planned:
      return t("cc_memory_state_planned_title", "Planned state")
    case .historical:
      return t("cc_memory_state_history_title", "Historical and replaced")
    case .deprecated:
      return t("cc_memory_state_deprecated_title", "Superseded state")
    case .pending:
      return t("cc_memory_state_review_title", "Waiting for review")
    case .conflicted:
      return t("cc_memory_state_conflicted_title", "Conflicted state")
    }
  }

  private var stateSubtitle: String {
    switch state {
    case .current:
      return t("cc_memory_state_current_subtitle", "Facts and decisions GalaxySSI currently treats as true")
    case .planned:
      return t("cc_memory_state_planned_subtitle", "Goals and future changes that are not current facts yet")
    case .historical:
      return t("cc_memory_state_history_subtitle", "Previous facts remain distinguishable from the current world model")
    case .deprecated:
      return t("cc_memory_state_deprecated_subtitle", "Expired or replaced memory is kept out of current grounding")
    case .pending:
      return t("cc_memory_state_review_subtitle", "Identity, preference, safety, and conflicting changes require a decision")
    case .conflicted:
      return t("cc_memory_state_conflicted_subtitle", "Contradictory long-term state is isolated until resolved")
    }
  }

  private var stateIcon: String {
    switch state {
    case .current: return "brain"
    case .planned: return "calendar.badge.clock"
    case .historical: return "clock.arrow.circlepath"
    case .deprecated: return "archivebox"
    case .pending: return "tray"
    case .conflicted: return "exclamationmark.shield"
    }
  }

  private var stateTone: GalaxySSIMemoryTone {
    switch state {
    case .current, .pending: return .green
    case .planned: return .blue
    case .historical, .deprecated: return .neutral
    case .conflicted: return .amber
    }
  }

  private func refresh() {
    inbox = evolutionStore.inbox()
    auditReport = evolutionStore.auditReport()
    records = evolutionStore.evolutionRecords()
  }

  private func memorySubtitle(_ item: AgentMemoryItem) -> String {
    let label = item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? t("galaxyssi.agent_memory.key_none", "Unkeyed")
      : item.key
    return String(format: t("galaxyssi.agent_memory.item_subtitle", "%@ / v%d / %@"), memoryKindLabel(item.kind), item.version, label)
  }

  private func candidateTitle(_ candidate: GlobalMemoryCandidate) -> String {
    candidate.item.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? GalaxySSIMemoryText.candidateKindLabel(candidate.kind, language: interfaceLanguage)
      : candidate.item.topic
  }

  private func candidateSubtitle(_ candidate: GlobalMemoryCandidate) -> String {
    String(
      format: t("cc_memory_candidate_subtitle_detailed", "%@ / %@ / %@ / %d evidence"),
      GalaxySSIMemoryText.candidateKindLabel(candidate.kind, language: interfaceLanguage),
      GalaxySSIMemoryText.temporalStateLabel(candidate.temporalState, language: interfaceLanguage),
      GalaxySSIMemoryText.evolutionActionLabel(candidate.action, language: interfaceLanguage),
      candidate.item.evidenceCount
    )
  }

  private func candidateRiskLabel(_ risk: GlobalMemoryCandidateRisk) -> String {
    GalaxySSIMemoryText.riskLabel(risk, language: interfaceLanguage)
  }

  private func memoryKindLabel(_ kind: AgentMemoryKind) -> String {
    GalaxySSIMemoryText.kindLabel(kind, language: interfaceLanguage)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMemoryInboxView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var inbox = GlobalMemoryInbox()
  @State private var statusMessage = ""

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    GalaxySSIMemoryListPage(
      title: t("cc_memory_inbox_title", "Memory inbox"),
      heroTitle: t("cc_memory_inbox_hero_title", "Candidate memory gate"),
      heroSubtitle: t("cc_memory_inbox_hero_subtitle", "Low-risk facts merge automatically; sensitive or conflicting changes wait for you"),
      heroIcon: "tray.full",
      heroTint: pending.isEmpty ? .galaxySSIAccent : .orange,
      heroBadge: "\(pending.count)"
    ) {
      if !statusMessage.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_memory_status_title", "Memory status"),
          subtitle: statusMessage,
          systemImage: "checkmark.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.status.ready", "Ready")
        )
      }
      GalaxySSISecuritySectionTitle(title: t("cc_memory_inbox_pending_section", "Waiting for Review"))
      if pending.isEmpty {
        emptyRow(
          title: t("cc_memory_inbox_empty", "No memory candidates need review"),
          subtitle: t("cc_memory_inbox_empty_subtitle", "The durable world model is not waiting on a decision"),
          icon: "checkmark.shield",
          tint: .galaxySSIAccent
        )
      } else {
        ForEach(pending) { candidate in
          GalaxySSIMemoryCandidateCard(
            candidate: candidate,
            language: interfaceLanguage,
            approveTitle: t("cc_memory_candidate_approve", "Approve"),
            rejectTitle: t("galaxyssi.common.reject", "Reject"),
            onApprove: { approve(candidate) },
            onReject: { reject(candidate) }
          )
        }
      }
    }
    .onAppear(perform: refresh)
  }

  private var pending: [GlobalMemoryCandidate] {
    inbox.pending()
  }

  private var snapshot: GalaxySSIMemoryControlSnapshot {
    GalaxySSIMemoryControlSnapshot.make(
      agentMemory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      inbox: inbox,
      evolutionRecords: evolutionStore.evolutionRecords(),
      auditReport: evolutionStore.auditReport()
    )
  }

  private func refresh() {
    inbox = evolutionStore.inbox()
  }

  private func approve(_ candidate: GlobalMemoryCandidate) {
    let result = GlobalMemoryEvolutionPolicy.approve(
      world: snapshot.world,
      inbox: inbox,
      candidateId: candidate.id
    )
    inbox = result.inbox
    evolutionStore.saveInbox(result.inbox)
    evolutionStore.appendEvolutionRecords([
      GlobalMemoryEvolutionPolicy.reviewRecord(candidate: candidate, outcome: .approved)
    ])
    statusMessage = t("cc_memory_candidate_approved", "Memory candidate approved")
  }

  private func reject(_ candidate: GlobalMemoryCandidate) {
    inbox = GlobalMemoryEvolutionPolicy.reject(inbox: inbox, candidateId: candidate.id)
    evolutionStore.saveInbox(inbox)
    evolutionStore.appendEvolutionRecords([
      GlobalMemoryEvolutionPolicy.reviewRecord(candidate: candidate, outcome: .rejected)
    ])
    statusMessage = t("cc_memory_candidate_rejected", "Memory candidate rejected")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMemoryEvolutionHistoryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var records: [GlobalMemoryEvolutionRecord] = []
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    GalaxySSIMemoryListPage(
      title: t("cc_memory_evolution_history_title", "Memory evolution history"),
      heroTitle: t("cc_memory_evolution_history_hero_title", "Evidence-backed evolution"),
      heroSubtitle: t("cc_memory_evolution_history_hero_subtitle", "Encrypted, bounded records explain state changes without copying sensitive content"),
      heroIcon: "clock.badge.checkmark",
      heroTint: .purple,
      heroBadge: "\(records.count)"
    ) {
      GalaxySSISecuritySectionTitle(title: t("cc_memory_evolution_history_recent", "Recent Changes"))
      if records.isEmpty {
        emptyRow(
          title: t("cc_memory_evolution_history_empty", "No memory changes recorded"),
          subtitle: t("cc_memory_evolution_history_empty_subtitle", "New durable events will appear here after they pass the memory gate"),
          icon: "clock",
          tint: .purple
        )
      } else {
        ForEach(records.reversed()) { record in
          GalaxySSISecurityStatusRow(
            title: compact(record.subject),
            subtitle: String(
              format: t("cc_memory_evolution_history_item_subtitle", "%@ / %@ / %d evidence references"),
              GalaxySSIMemoryText.evolutionActionLabel(record.action, language: interfaceLanguage),
              GalaxySSIMemoryText.evolutionOutcomeLabel(record.outcome, language: interfaceLanguage),
              record.evidenceCount
            ),
            systemImage: "arrow.triangle.branch",
            tint: GalaxySSIMemoryText.outcomeTint(record.outcome),
            badge: GalaxySSIMemoryText.temporalStateLabel(record.temporalState, language: interfaceLanguage)
          )
        }
      }
    }
    .onAppear {
      records = evolutionStore.evolutionRecords()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMemoryGraphView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var inbox = GlobalMemoryInbox()
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    GalaxySSIMemoryListPage(
      title: t("cc_memory_graph_title", "Relationship graph"),
      heroTitle: t("cc_memory_graph_hero_title", "Temporal entity graph"),
      heroSubtitle: t("cc_memory_graph_hero_subtitle", "Current, historical, planned, and superseded relationships remain distinguishable"),
      heroIcon: "point.3.connected.trianglepath.dotted",
      heroTint: .blue,
      heroBadge: String(format: t("cc_memory_graph_status", "%d entities / %d relations"), graph.nodes.count, graph.relations.count)
    ) {
      GalaxySSISecuritySectionTitle(title: t("cc_memory_graph_current_entities", "Current Entities"))
      if graph.nodes.isEmpty {
        emptyRow(
          title: t("cc_memory_graph_empty", "No relationships learned yet"),
          subtitle: t("cc_memory_graph_empty_subtitle", "Durable low-risk events will form the graph over time"),
          icon: "point.3.connected.trianglepath.dotted",
          tint: .blue
        )
      } else {
        ForEach(graph.nodes) { node in
          GalaxySSISecurityStatusRow(
            title: compact(node.title),
            subtitle: compact(node.subtitle),
            systemImage: node.systemImage,
            tint: color(node.tone),
            badge: node.badge
          )
        }
      }

      GalaxySSISecuritySectionTitle(title: t("cc_memory_graph_relations", "Relationships"))
      if graph.relations.isEmpty {
        emptyRow(
          title: t("cc_memory_graph_no_relations", "No explicit relationships"),
          subtitle: t("cc_memory_graph_no_relations_subtitle", "Supersession, conflict, and candidate-target links will appear here"),
          icon: "link",
          tint: .gray
        )
      } else {
        ForEach(graph.relations) { relation in
          GalaxySSISecurityStatusRow(
            title: compact(relation.title),
            subtitle: compact(relation.subtitle),
            systemImage: "link",
            tint: color(relation.tone),
            badge: ""
          )
        }
      }
    }
    .onAppear {
      inbox = evolutionStore.inbox()
    }
  }

  private var graph: GalaxySSIMemoryGraphSnapshot {
    GalaxySSIMemoryControlSnapshot.make(
      agentMemory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      inbox: inbox,
      evolutionRecords: evolutionStore.evolutionRecords(),
      auditReport: evolutionStore.auditReport()
    ).graph
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMemoryAuditView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var inbox = GlobalMemoryInbox()
  @State private var report = GlobalMemoryAuditReport()
  @State private var statusMessage = ""
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    GalaxySSIMemoryListPage(
      title: t("cc_memory_audit_title", "Memory health"),
      heroTitle: t("cc_memory_audit_hero_title", "Memory critic"),
      heroSubtitle: t("cc_memory_audit_hero_subtitle", "Tap to run an encrypted on-device consistency audit now"),
      heroIcon: "checkmark.shield",
      heroTint: report.findings.isEmpty ? .galaxySSIAccent : .orange,
      heroBadge: "\(report.findings.count)"
    ) {
      GalaxySSISecurityPrimaryButton(
        title: t("cc_memory_audit_run_now", "Run memory audit"),
        systemImage: "arrow.clockwise",
        tint: .galaxySSIAccent,
        action: runAudit
      )
      if !statusMessage.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_memory_status_title", "Memory status"),
          subtitle: statusMessage,
          systemImage: "checkmark.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.status.ready", "Ready")
        )
      }

      GalaxySSISecuritySectionTitle(title: t("cc_memory_audit_findings", "Findings"))
      if report.findings.isEmpty {
        emptyRow(
          title: t("cc_memory_audit_clean", "Memory is healthy"),
          subtitle: t("cc_memory_audit_clean_subtitle", "No stale or unresolved durable state was found"),
          icon: "checkmark.seal",
          tint: .galaxySSIAccent
        )
      } else {
        ForEach(report.findings) { finding in
          GalaxySSISecurityStatusRow(
            title: GalaxySSIMemoryText.auditFindingLabel(finding.kind, language: interfaceLanguage),
            subtitle: finding.summary,
            systemImage: "exclamationmark.shield",
            tint: .orange,
            badge: String(
              format: t("cc_memory_audit_evidence_count", "%d evidence references"),
              finding.evidenceCount
            )
          )
        }
      }

      if !report.themes.isEmpty {
        GalaxySSISecuritySectionTitle(title: t("cc_memory_audit_themes", "Long-term themes"))
        ForEach(report.themes) { theme in
          GalaxySSISecurityStatusRow(
            title: compact(theme.title),
            subtitle: String(
              format: t("cc_memory_theme_subtitle", "%d memories / %d conversations / %d evidence references"),
              theme.itemCount,
              theme.conversationCount,
              theme.evidenceCount
            ),
            systemImage: "rectangle.3.group",
            tint: .blue,
            badge: "\(Int(theme.confidence * 100))%"
          )
        }
      }
    }
    .onAppear(perform: refresh)
  }

  private var snapshot: GalaxySSIMemoryControlSnapshot {
    GalaxySSIMemoryControlSnapshot.make(
      agentMemory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      inbox: inbox,
      evolutionRecords: evolutionStore.evolutionRecords(),
      auditReport: report
    )
  }

  private func refresh() {
    inbox = evolutionStore.inbox()
    report = evolutionStore.auditReport()
  }

  private func runAudit() {
    let now = GlobalMemoryClock.nowMillis()
    let worldBefore = snapshot.world
    let result = GlobalMemoryCritic.audit(world: worldBefore, inbox: inbox, nowMillis: now)
    report = result.report
    evolutionStore.saveAudit(result.report)
    evolutionStore.appendEvolutionRecords(
      GlobalMemoryEvolutionPolicy.auditRecords(worldBefore: worldBefore, worldAfter: result.world, nowMillis: now)
    )
    statusMessage = report.findings.isEmpty
      ? t("cc_memory_audit_clean", "Memory is healthy")
      : String(format: t("cc_memory_audit_result", "%d findings recorded"), report.findings.count)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIMemoryCandidateCard: View {
  var candidate: GlobalMemoryCandidate
  var language: String
  var approveTitle: String
  var rejectTitle: String
  var onApprove: () -> Void
  var onReject: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: "tray")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Text(GalaxySSIMemoryText.riskLabel(candidate.risk, language: language))
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      HStack(spacing: 8) {
        Button(action: onApprove) {
          Label(approveTitle, systemImage: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .background(Color.galaxySSIAccent)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        Button(action: onReject) {
          Label(rejectTitle, systemImage: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(.orange)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var title: String {
    candidate.item.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? GalaxySSIMemoryText.candidateKindLabel(candidate.kind, language: language)
      : candidate.item.topic
  }

  private var subtitle: String {
    let detail = candidate.risk == .privateBlocked ? "Private content blocked" : candidate.item.value
    return [
      GalaxySSIMemoryText.evolutionActionLabel(candidate.action, language: language),
      GalaxySSIMemoryText.temporalStateLabel(candidate.temporalState, language: language),
      compact(detail)
    ].filter { !$0.isEmpty }.joined(separator: " / ")
  }

  private var tint: Color {
    candidate.status == .conflicted || candidate.risk != .low ? .orange : .blue
  }
}

struct GalaxySSIMemoryListPage<Content: View>: View {
  var title: String
  var heroTitle: String
  var heroSubtitle: String
  var heroIcon: String
  var heroTint: Color
  var heroBadge: String
  let content: () -> Content

  init(
    title: String,
    heroTitle: String,
    heroSubtitle: String,
    heroIcon: String,
    heroTint: Color,
    heroBadge: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.heroTitle = heroTitle
    self.heroSubtitle = heroSubtitle
    self.heroIcon = heroIcon
    self.heroTint = heroTint
    self.heroBadge = heroBadge
    self.content = content
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: title,
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: heroTitle,
            subtitle: heroSubtitle,
            systemImage: heroIcon,
            tint: heroTint,
            badge: heroBadge
          )
          content()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }
}

private enum GalaxySSIMemoryText {
  static func kindLabel(_ kind: AgentMemoryKind, language: String) -> String {
    switch kind {
    case .identity:
      return t("galaxyssi.agent_memory.kind_identity", "Identity", language)
    case .contact:
      return t("galaxyssi.agent_memory.kind_contact", "Contact", language)
    case .task:
      return t("galaxyssi.agent_memory.kind_task", "Task", language)
    case .preference:
      return t("galaxyssi.agent_memory.kind_preference", "Preference", language)
    case .workflow:
      return t("galaxyssi.agent_memory.kind_workflow", "Workflow", language)
    case .knowledge:
      return t("galaxyssi.agent_memory.kind_knowledge", "Knowledge", language)
    case .safety:
      return t("galaxyssi.agent_memory.kind_safety", "Safety", language)
    }
  }

  static func temporalStateLabel(_ state: GlobalMemoryTemporalState, language: String) -> String {
    switch state {
    case .historical:
      return t("cc_memory_state_historical", "Historical", language)
    case .current:
      return t("cc_memory_state_current", "Current", language)
    case .planned:
      return t("cc_memory_state_planned", "Planned", language)
    case .deprecated:
      return t("cc_memory_state_deprecated", "Superseded", language)
    case .pending:
      return t("cc_memory_state_pending", "Pending", language)
    case .conflicted:
      return t("cc_memory_state_conflicted", "Conflicted", language)
    }
  }

  static func candidateKindLabel(_ kind: GlobalMemoryCandidateKind, language: String) -> String {
    switch kind {
    case .fact: return t("cc_memory_candidate_kind_fact", "Fact", language)
    case .preference: return t("cc_memory_candidate_kind_preference", "Preference", language)
    case .identity: return t("cc_memory_candidate_kind_identity", "Identity", language)
    case .decision: return t("cc_memory_candidate_kind_decision", "Decision", language)
    case .projectState: return t("cc_memory_candidate_kind_project_state", "Project state", language)
    case .goal: return t("cc_memory_candidate_kind_goal", "Goal", language)
    case .relation: return t("cc_memory_candidate_kind_relation", "Relation", language)
    case .skillOpportunity: return t("cc_memory_candidate_kind_skill_opportunity", "Skill opportunity", language)
    }
  }

  static func riskLabel(_ risk: GlobalMemoryCandidateRisk, language: String) -> String {
    switch risk {
    case .low:
      return t("cc_memory_risk_low", "Low risk", language)
    case .reviewRequired:
      return t("cc_memory_risk_review", "Review required", language)
    case .privateBlocked:
      return t("cc_memory_risk_private", "Private content blocked", language)
    }
  }

  static func evolutionActionLabel(_ action: GlobalMemoryEvolutionAction, language: String) -> String {
    switch action {
    case .create:
      return t("cc_memory_action_create", "Add", language)
    case .strengthen:
      return t("cc_memory_action_strengthen", "Strengthen", language)
    case .supersede:
      return t("cc_memory_action_supersede", "Replace current", language)
    case .link:
      return t("cc_memory_action_link", "Create relationship", language)
    case .consolidate:
      return t("cc_memory_action_consolidate", "Consolidate", language)
    case .reviewConflict:
      return t("cc_memory_action_review_conflict", "Resolve conflict", language)
    case .blockPrivate:
      return t("cc_memory_action_block_private", "Private content blocked", language)
    }
  }

  static func evolutionOutcomeLabel(_ outcome: GlobalMemoryEvolutionOutcome, language: String) -> String {
    switch outcome {
    case .applied:
      return t("cc_memory_evolution_outcome_applied", "Applied", language)
    case .waitingReview:
      return t("cc_memory_evolution_outcome_waiting", "Waiting for review", language)
    case .conflicted:
      return t("cc_memory_evolution_outcome_conflicted", "Conflicted", language)
    case .privateBlocked:
      return t("cc_memory_evolution_outcome_private_blocked", "Private content blocked", language)
    case .approved:
      return t("cc_memory_evolution_outcome_approved", "Approved", language)
    case .rejected:
      return t("cc_memory_evolution_outcome_rejected", "Rejected", language)
    }
  }

  static func auditFindingLabel(_ kind: GlobalMemoryAuditFindingKind, language: String) -> String {
    switch kind {
    case .expired:
      return t("cc_memory_audit_expired", "Expired state retired", language)
    case .duplicate:
      return t("cc_memory_audit_duplicate", "Duplicate memory", language)
    case .lowConfidenceReused:
      return t("cc_memory_audit_low_confidence", "Low-confidence memory needs review", language)
    case .staleCandidate:
      return t("cc_memory_audit_stale_candidate", "Memory candidate awaiting review", language)
    case .unresolvedConflict:
      return t("cc_memory_audit_conflict", "Unresolved memory conflict", language)
    case .skillCandidate:
      return t("cc_memory_audit_skill_candidate", "Workflow may become a Skill", language)
    case .completedGoal:
      return t("cc_memory_audit_completed_goal", "Completed goal can be archived", language)
    }
  }

  static func outcomeTint(_ outcome: GlobalMemoryEvolutionOutcome) -> Color {
    switch outcome {
    case .applied, .approved:
      return .galaxySSIAccent
    case .waitingReview, .conflicted, .privateBlocked:
      return .orange
    case .rejected:
      return .gray
    }
  }

  private static func t(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private func emptyRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
  GalaxySSISecurityStatusRow(
    title: title,
    subtitle: subtitle,
    systemImage: icon,
    tint: tint,
    badge: ""
  )
}

private func compact(_ value: String, limit: Int = 120) -> String {
  let clean = value
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  if clean.count <= limit { return clean }
  return String(clean.prefix(max(limit - 1, 1))) + "..."
}

private func color(_ tone: GalaxySSIMemoryTone) -> Color {
  switch tone {
  case .accent:
    return .galaxySSIAccent
  case .blue:
    return .blue
  case .green:
    return .galaxySSIAccent
  case .purple:
    return .purple
  case .amber:
    return .orange
  case .neutral:
    return .gray
  }
}
