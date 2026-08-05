import SwiftUI

struct SignalASIMemoryKindView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var title: String
  var subtitle: String
  var kinds: Set<AgentMemoryKind>
  var systemImage: String
  var tint: Color

  var body: some View {
    SignalASIMemoryPageScaffold(title: title) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: title,
          subtitle: subtitle,
          systemImage: systemImage,
          tint: tint,
          badge: "\(items.count)"
        )
        SignalASISecurityNavigationRow(
          title: t("cc_memory_manage_title", "Manage all memories"),
          subtitle: t("cc_memory_manage_subtitle", "Review, edit, pin, resolve conflicts, or delete individual memories"),
          systemImage: "archivebox",
          tint: .blue,
          badge: t("common_view", "View")
        ) {
          SignalASIAgentMemoryView()
        }
        SignalASISecuritySectionTitle(title: t("cc_memory_temporal_items", "Accepted memory"))
        if items.isEmpty {
          SignalASISecurityStatusRow(
            title: t("signalasi.agent_memory.empty", "No saved memory"),
            subtitle: t("signalasi.agent_memory.empty_subtitle", "Use an explicit remember command to add long-term memory"),
            systemImage: "brain",
            tint: tint,
            badge: ""
          )
        } else {
          VStack(spacing: 8) {
            ForEach(Array(items.prefix(120))) { item in
              SignalASISecurityStatusRow(
                title: SignalASIMemoryText.compact(item.value, limit: 96),
                subtitle: itemSubtitle(item),
                systemImage: item.important ? "pin.fill" : "brain",
                tint: item.important ? .orange : tint,
                badge: item.important ? t("signalasi.agent_memory.pinned", "Pinned") : "v\(item.version)"
              )
            }
          }
        }

        if !conflicts.isEmpty {
          SignalASISecuritySectionTitle(title: t("signalasi.agent_memory.section_conflicts", "Needs Review"))
          VStack(spacing: 8) {
            ForEach(conflicts) { conflict in
              SignalASISecurityStatusRow(
                title: conflict.key.ifBlank(SignalASIMemoryText.agentKindLabel(conflict.kind, language: interfaceLanguage)),
                subtitle: String(
                  format: t("signalasi.agent_memory.conflict_subtitle", "%@ / %d versions disagree"),
                  SignalASIMemoryText.agentKindLabel(conflict.kind, language: interfaceLanguage),
                  conflict.candidates.count
                ),
                systemImage: "exclamationmark.shield",
                tint: .orange,
                badge: t("signalasi.agent_memory.review", "Review")
              )
            }
          }
        }
      }
    }
  }

  private var snapshot: AgentMemorySnapshot {
    store.agentMemorySnapshot()
  }

  private var items: [AgentMemoryItem] {
    snapshot.activeItems
      .filter { kinds.contains($0.kind) }
      .sorted { $0.timestampMillis > $1.timestampMillis }
  }

  private var conflicts: [AgentMemoryConflict] {
    snapshot.conflicts.filter { kinds.contains($0.kind) }
  }

  private func itemSubtitle(_ item: AgentMemoryItem) -> String {
    String(
      format: t("signalasi.agent_memory.item_subtitle", "%@ / v%d / %@"),
      SignalASIMemoryText.agentKindLabel(item.kind, language: interfaceLanguage),
      item.version,
      item.key.ifBlank(t("signalasi.agent_memory.key_none", "Unkeyed"))
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryLifecycleView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var archive = GlobalMemoryEvolutionArchive()

  var state: GlobalMemoryTemporalState
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    SignalASIMemoryPageScaffold(title: stateLabel) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: stateLabel,
          subtitle: String(
            format: t("cc_memory_temporal_page_subtitle", "%@ memory remains separate from other lifecycle states."),
            stateLabel
          ),
          systemImage: "clock.arrow.circlepath",
          tint: tint,
          badge: "\(temporal.count(state))"
        )

        SignalASISecuritySectionTitle(title: t("cc_memory_temporal_items", "Accepted memory"))
        if items.isEmpty && candidates.isEmpty {
          SignalASISecurityStatusRow(
            title: String(format: t("cc_memory_temporal_empty", "No %@ memory"), stateLabel),
            subtitle: t(
              "cc_memory_temporal_empty_subtitle",
              "SignalASI will place durable evidence here when it reaches this state."
            ),
            systemImage: "brain",
            tint: tint,
            badge: ""
          )
        } else {
          VStack(spacing: 8) {
            ForEach(Array(items.prefix(200))) { item in
              SignalASISecurityStatusRow(
                title: item.topic.ifBlank(item.kind.rawValue.lowercased()),
                subtitle: itemSubtitle(item),
                systemImage: "brain",
                tint: tint,
                badge: SignalASIMemoryText.timeLabel(item.lastSeenAtMillis, language: interfaceLanguage)
              )
            }
            ForEach(Array(candidates.prefix(100))) { candidate in
              SignalASISecurityStatusRow(
                title: SignalASIMemoryText.compact(candidate.item.value.ifBlank(candidate.item.topic), limit: 90),
                subtitle: candidateSubtitle(candidate),
                systemImage: "exclamationmark.shield",
                tint: .orange,
                badge: SignalASIMemoryText.statusLabel(candidate.status)
              )
            }
          }
        }
      }
    }
    .onAppear(perform: reload)
  }

  private var controlSnapshot: SignalASIMemoryControlSnapshot {
    SignalASIMemorySnapshotBuilder.make(store: store, archive: archive)
  }

  private var temporal: GlobalMemoryTemporalSnapshot {
    controlSnapshot.temporal
  }

  private var items: [GlobalWorldItem] {
    temporal.accepted(state)
  }

  private var candidates: [GlobalMemoryCandidate] {
    switch state {
    case .pending:
      return temporal.pendingCandidates
    case .conflicted:
      return temporal.conflictedCandidates
    default:
      return []
    }
  }

  private var stateLabel: String {
    SignalASIMemoryText.temporalStateLabel(state, language: interfaceLanguage)
  }

  private var tint: Color {
    switch state {
    case .current: return .signalASIAccent
    case .planned: return .blue
    case .historical, .deprecated: return .signalASITextSecondary
    case .pending, .conflicted: return temporal.count(state) == 0 ? .signalASIAccent : .orange
    }
  }

  private func itemSubtitle(_ item: GlobalWorldItem) -> String {
    String(
      format: t("cc_memory_temporal_item_subtitle", "%@ · %@ · %d evidence references"),
      SignalASIMemoryText.temporalStateLabel(GlobalMemoryTemporalPolicy.classify(item), language: interfaceLanguage),
      SignalASIMemoryText.namespaceLabel(item, language: interfaceLanguage),
      item.evidenceCount
    )
  }

  private func candidateSubtitle(_ candidate: GlobalMemoryCandidate) -> String {
    String(
      format: t("cc_memory_candidate_subtitle_detailed", "%@ · %@ · %@ · %d evidence"),
      "\(SignalASIMemoryText.candidateKindLabel(candidate.kind, language: interfaceLanguage)) · \(SignalASIMemoryText.namespaceLabel(candidate.item, language: interfaceLanguage))",
      SignalASIMemoryText.temporalStateLabel(candidate.temporalState, language: interfaceLanguage),
      SignalASIMemoryText.actionLabel(candidate.action, language: interfaceLanguage),
      candidate.item.evidenceCount
    )
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryInboxView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var archive = GlobalMemoryEvolutionArchive()
  @State private var selectedCandidate: GlobalMemoryCandidate?
  @State private var statusText = ""

  var statusFilter: GlobalMemoryCandidateStatus?
  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    SignalASIMemoryPageScaffold(title: t("cc_memory_inbox_title", "Memory inbox")) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: t("cc_memory_inbox_hero_title", "Candidate memory gate"),
          subtitle: t(
            "cc_memory_inbox_hero_subtitle",
            "Low-risk facts merge automatically; sensitive or conflicting changes wait for you"
          ),
          systemImage: "tray",
          tint: candidates.isEmpty ? .signalASIAccent : .orange,
          badge: "\(candidates.count)"
        )
        if !statusText.isEmpty {
          Text(statusText)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .padding(.horizontal, 4)
        }
        SignalASISecuritySectionTitle(title: t("cc_memory_inbox_pending_section", "Waiting for Review"))
        if candidates.isEmpty {
          SignalASISecurityStatusRow(
            title: t("cc_memory_inbox_empty", "No memory candidates need review"),
            subtitle: t("cc_memory_inbox_empty_subtitle", "The durable world model is not waiting on a decision"),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: t("cc_status_ready", "Ready")
          )
        } else {
          VStack(spacing: 8) {
            ForEach(candidates) { candidate in
              SignalASISecurityActionRow(
                title: SignalASIMemoryText.compact(candidate.item.value.ifBlank(candidate.item.topic), limit: 90),
                subtitle: candidateSubtitle(candidate),
                systemImage: "brain",
                tint: candidate.status == .conflicted ? .orange : .blue,
                badge: t("signalasi.agent_memory.review", "Review")
              ) {
                selectedCandidate = candidate
              }
            }
          }
        }
      }
    }
    .onAppear(perform: reload)
    .alert(item: $selectedCandidate) { candidate in
      Alert(
        title: Text(t("cc_memory_candidate_dialog_title", "Review memory candidate")),
        message: Text(candidateDialogMessage(candidate)),
        primaryButton: .default(Text(t("cc_memory_candidate_approve", "Approve"))) {
          update(candidate: candidate, status: .approved, outcome: .approved)
        },
        secondaryButton: .destructive(Text(t("common_reject", "Reject"))) {
          update(candidate: candidate, status: .rejected, outcome: .rejected)
        }
      )
    }
  }

  private var candidates: [GlobalMemoryCandidate] {
    archive.inbox.pending()
      .filter { statusFilter == nil || $0.status == statusFilter }
  }

  private func update(
    candidate: GlobalMemoryCandidate,
    status: GlobalMemoryCandidateStatus,
    outcome: GlobalMemoryEvolutionOutcome
  ) {
    let now = GlobalMemoryClock.nowMillis()
    var inbox = archive.inbox
    guard let index = inbox.candidates.firstIndex(where: { $0.id == candidate.id }) else {
      statusText = t("cc_memory_candidate_unchanged", "Memory candidate was not changed")
      return
    }
    var updated = candidate
    updated.status = status
    updated.reviewedAtMillis = now
    inbox.candidates[index] = updated
    evolutionStore.saveInbox(inbox)
    evolutionStore.appendEvolutionRecords([
      SignalASIMemorySnapshotBuilder.reviewRecord(candidate: updated, outcome: outcome, nowMillis: now)
    ])
    archive = evolutionStore.exportArchive()
    statusText = status == .approved
      ? t("cc_memory_candidate_approved", "Memory candidate approved")
      : t("cc_memory_candidate_rejected", "Memory candidate rejected")
  }

  private func candidateSubtitle(_ candidate: GlobalMemoryCandidate) -> String {
    String(
      format: t("cc_memory_candidate_subtitle_detailed", "%@ · %@ · %@ · %d evidence"),
      "\(SignalASIMemoryText.candidateKindLabel(candidate.kind, language: interfaceLanguage)) · \(SignalASIMemoryText.namespaceLabel(candidate.item, language: interfaceLanguage))",
      SignalASIMemoryText.temporalStateLabel(candidate.temporalState, language: interfaceLanguage),
      SignalASIMemoryText.actionLabel(candidate.action, language: interfaceLanguage),
      candidate.item.evidenceCount
    )
  }

  private func candidateDialogMessage(_ candidate: GlobalMemoryCandidate) -> String {
    String(
      format: t(
        "cc_memory_candidate_dialog_message_detailed",
        "Type: %@\nTopic: %@\nRisk: %@\nState: %@\nEvolution: %@\nAffected memories: %d\nEvidence references: %d\nReason: %@\n\n%@"
      ),
      "\(SignalASIMemoryText.candidateKindLabel(candidate.kind, language: interfaceLanguage)) · \(SignalASIMemoryText.namespaceLabel(candidate.item, language: interfaceLanguage))",
      candidate.item.topic.ifBlank(t("signalasi.agent_memory.key_none", "Unkeyed")),
      SignalASIMemoryText.riskLabel(candidate.risk, language: interfaceLanguage),
      SignalASIMemoryText.temporalStateLabel(candidate.temporalState, language: interfaceLanguage),
      SignalASIMemoryText.actionLabel(candidate.action, language: interfaceLanguage),
      candidate.targetItemIds.count,
      candidate.item.evidenceCount,
      candidate.reason.ifBlank(t("cc_memory_candidate_reason_default", "Durable context passed the memory gate")),
      candidate.item.value.ifBlank(t("cc_memory_candidate_private_value", "Private content was not retained"))
    )
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryEvolutionHistoryView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var archive = GlobalMemoryEvolutionArchive()

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    SignalASIMemoryPageScaffold(title: t("cc_memory_evolution_history_title", "Memory evolution history")) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: t("cc_memory_evolution_history_hero_title", "Evidence-backed evolution"),
          subtitle: t(
            "cc_memory_evolution_history_hero_subtitle",
            "Encrypted, bounded records explain state changes without copying sensitive content"
          ),
          systemImage: "clock.arrow.circlepath",
          tint: .purple,
          badge: "\(records.count)"
        )
        SignalASISecuritySectionTitle(title: t("cc_memory_evolution_history_recent", "Recent Changes"))
        if records.isEmpty {
          SignalASISecurityStatusRow(
            title: t("cc_memory_evolution_history_empty", "No memory changes recorded"),
            subtitle: t("cc_memory_evolution_history_empty_subtitle", "New durable events will appear here after they pass the memory gate"),
            systemImage: "clock.arrow.circlepath",
            tint: .purple,
            badge: ""
          )
        } else {
          VStack(spacing: 8) {
            ForEach(Array(records.prefix(100))) { record in
              SignalASISecurityStatusRow(
                title: record.subject.ifBlank(record.kind.rawValue),
                subtitle: recordSubtitle(record),
                systemImage: "clock.arrow.circlepath",
                tint: .purple,
                badge: SignalASIMemoryText.timeLabel(record.createdAtMillis, language: interfaceLanguage)
              )
            }
          }
        }
      }
    }
    .onAppear(perform: reload)
  }

  private var records: [GlobalMemoryEvolutionRecord] {
    archive.records.sorted { $0.createdAtMillis > $1.createdAtMillis }
  }

  private func recordSubtitle(_ record: GlobalMemoryEvolutionRecord) -> String {
    String(
      format: t("cc_memory_evolution_history_item_subtitle", "%@ / %@ / %d evidence references"),
      SignalASIMemoryText.actionLabel(record.action, language: interfaceLanguage),
      SignalASIMemoryText.outcomeLabel(record.outcome, language: interfaceLanguage),
      record.evidenceCount
    )
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryGraphView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var archive = GlobalMemoryEvolutionArchive()

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    SignalASIMemoryPageScaffold(title: t("cc_memory_graph_title", "Relationship graph")) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: t("cc_memory_graph_hero_title", "Temporal entity graph"),
          subtitle: t(
            "cc_memory_graph_hero_subtitle",
            "Current, historical, planned, and superseded relationships remain distinguishable"
          ),
          systemImage: "point.3.connected.trianglepath.dotted",
          tint: .blue,
          badge: String(
            format: t("cc_memory_graph_status", "%d entities · %d relations"),
            snapshot.world.items.count,
            snapshot.relations.count
          )
        )
        SignalASISecuritySectionTitle(title: t("cc_memory_graph_current_entities", "Current Entities"))
        if snapshot.world.items.isEmpty {
          SignalASISecurityStatusRow(
            title: t("cc_memory_graph_empty", "No relationships learned yet"),
            subtitle: t("cc_memory_graph_empty_subtitle", "Durable low-risk events will form the graph over time"),
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: .blue,
            badge: ""
          )
        } else {
          VStack(spacing: 8) {
            ForEach(Array(snapshot.world.items.prefix(40))) { item in
              SignalASISecurityStatusRow(
                title: item.topic.ifBlank(item.kind.rawValue.lowercased()),
                subtitle: String(
                  format: t("cc_memory_graph_node_subtitle", "%@ · %@"),
                  item.kind.rawValue.lowercased().replacingOccurrences(of: "_", with: " "),
                  SignalASIMemoryText.temporalStateLabel(item.temporalState, language: interfaceLanguage)
                ),
                systemImage: "circle.hexagongrid",
                tint: item.status == .conflicted ? .orange : .blue,
                badge: SignalASIMemoryText.namespaceLabel(item, language: interfaceLanguage)
              )
            }
          }
        }
        if !snapshot.relations.isEmpty {
          SignalASISecuritySectionTitle(title: t("cc_memory_graph_relations", "Relationships"))
          VStack(spacing: 8) {
            ForEach(Array(snapshot.relations.prefix(40))) { relation in
              SignalASISecurityStatusRow(
                title: relation.title,
                subtitle: relation.subtitle,
                systemImage: "link",
                tint: .blue,
                badge: relation.badge
              )
            }
          }
        }
      }
    }
    .onAppear(perform: reload)
  }

  private var snapshot: SignalASIMemoryControlSnapshot {
    SignalASIMemorySnapshotBuilder.make(store: store, archive: archive)
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryAuditView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var archive = GlobalMemoryEvolutionArchive()
  @State private var statusText = ""

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    SignalASIMemoryPageScaffold(title: t("cc_memory_audit_title", "Memory health")) {
      VStack(alignment: .leading, spacing: 12) {
        SignalASISecurityHeroView(
          title: t("cc_memory_audit_hero_title", "Memory critic"),
          subtitle: t("cc_memory_audit_hero_subtitle", "Tap to run an encrypted on-device consistency audit now"),
          systemImage: "checkmark.shield",
          tint: report.findings.isEmpty ? .signalASIAccent : .orange,
          badge: "\(report.findings.count)"
        )
        SignalASISecurityPrimaryButton(
          title: t("signalasi.memory_control.audit_run_now", "Run audit now"),
          systemImage: "arrow.clockwise",
          tint: .signalASIAccent
        ) {
          runAudit()
        }
        if !statusText.isEmpty {
          Text(statusText)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .padding(.horizontal, 4)
        }
        SignalASISecuritySectionTitle(title: t("cc_memory_audit_findings", "Findings"))
        if report.findings.isEmpty {
          SignalASISecurityStatusRow(
            title: t("cc_memory_audit_clean", "Memory is healthy"),
            subtitle: t("cc_memory_audit_clean_subtitle", "No stale or unresolved durable state was found"),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: t("cc_status_ready", "Ready")
          )
        } else {
          VStack(spacing: 8) {
            ForEach(report.findings) { finding in
              SignalASISecurityStatusRow(
                title: SignalASIMemoryText.auditFindingLabel(finding.kind, language: interfaceLanguage),
                subtitle: String(
                  format: t("cc_memory_audit_evidence_count", "%d evidence references"),
                  finding.evidenceCount
                ),
                systemImage: "checkmark.shield",
                tint: .orange,
                badge: finding.stableKey
              )
            }
          }
        }

        if !report.themes.isEmpty {
          SignalASISecuritySectionTitle(title: t("cc_memory_audit_themes", "Long-term themes"))
          VStack(spacing: 8) {
            ForEach(report.themes) { theme in
              SignalASISecurityStatusRow(
                title: theme.title,
                subtitle: String(
                  format: t("cc_memory_theme_subtitle", "%d memories · %d conversations · %d evidence references"),
                  theme.itemCount,
                  theme.conversationCount,
                  theme.evidenceCount
                ),
                systemImage: "book.closed",
                tint: .blue,
                badge: "\(Int((theme.confidence * 100).rounded()))%"
              )
            }
          }
        }
      }
    }
    .onAppear(perform: reload)
  }

  private var report: GlobalMemoryAuditReport {
    archive.audit
  }

  private func runAudit() {
    let current = SignalASIMemorySnapshotBuilder.make(store: store, archive: archive)
    let audited = GlobalMemoryCritic.audit(world: current.world, inbox: archive.inbox)
    evolutionStore.saveAudit(audited.report)
    evolutionStore.appendEvolutionRecords(GlobalMemoryEvolutionPolicy.auditRecords(
      worldBefore: current.world,
      worldAfter: audited.world,
      nowMillis: GlobalMemoryClock.nowMillis()
    ))
    archive = evolutionStore.exportArchive()
    statusText = t("signalasi.memory_control.audit_finished", "Audit finished on this device")
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryPageScaffold<Content: View>: View {
  var title: String
  private let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: title,
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        content
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }
}

enum SignalASIMemoryText {
  static func agentKindLabel(_ kind: AgentMemoryKind, language: String) -> String {
    switch kind {
    case .identity:
      return t("signalasi.agent_memory.kind_identity", "Profile", language)
    case .contact:
      return t("signalasi.agent_memory.kind_contact", "Contact", language)
    case .task:
      return t("signalasi.agent_memory.kind_task", "Task", language)
    case .preference:
      return t("signalasi.agent_memory.kind_preference", "Preference", language)
    case .workflow:
      return t("signalasi.agent_memory.kind_workflow", "Workflow", language)
    case .knowledge:
      return t("signalasi.agent_memory.kind_knowledge", "Knowledge", language)
    case .safety:
      return t("signalasi.agent_memory.kind_safety", "Security", language)
    }
  }

  static func candidateKindLabel(_ kind: GlobalMemoryCandidateKind, language: String) -> String {
    switch kind {
    case .identity:
      return t("signalasi.agent_memory.kind_identity", "Profile", language)
    case .preference:
      return t("signalasi.agent_memory.kind_preference", "Preference", language)
    case .goal, .projectState:
      return t("signalasi.agent_memory.kind_task", "Task", language)
    case .decision, .skillOpportunity:
      return t("signalasi.agent_memory.kind_workflow", "Workflow", language)
    case .relation:
      return t("signalasi.agent_memory.kind_contact", "Contact", language)
    case .fact:
      return t("signalasi.agent_memory.kind_knowledge", "Knowledge", language)
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

  static func namespaceLabel(_ item: GlobalWorldItem, language: String) -> String {
    let label: String
    switch item.namespace {
    case .general:
      label = t("cc_memory_namespace_general", "General", language)
    case .user:
      label = t("cc_memory_namespace_user", "User", language)
    case .project:
      label = t("cc_memory_namespace_project", "Project", language)
    case .device:
      label = t("cc_memory_namespace_device", "Device", language)
    case .security:
      label = t("cc_memory_namespace_security", "Security", language)
    }
    let genericIds: Set<String> = ["", "default", "self", "local", "policy"]
    return genericIds.contains(item.namespaceId) ? label : "\(label) · \(String(item.namespaceId.prefix(32)))"
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

  static func actionLabel(_ action: GlobalMemoryEvolutionAction, language: String) -> String {
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

  static func outcomeLabel(_ outcome: GlobalMemoryEvolutionOutcome, language: String) -> String {
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

  static func statusLabel(_ status: GlobalMemoryCandidateStatus) -> String {
    status.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
  }

  static func compact(_ value: String, limit: Int) -> String {
    String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(limit))
  }

  static func timeLabel(_ millis: Int64, language: String) -> String {
    guard millis > 0 else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1_000))
  }

  private static func t(_ key: String, _ fallback: String, _ language: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: language)
  }
}
