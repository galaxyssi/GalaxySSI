import SwiftUI

struct SignalASIMemoryControlView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var archive = GlobalMemoryEvolutionArchive()

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_memory_title", "Memory & Personalization"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button(action: reload) {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 19, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          metrics
          categoriesSection
          controlsSection
          lifecycleSection
          evolutionSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: reload)
  }

  private var snapshot: SignalASIMemoryControlSnapshot {
    SignalASIMemorySnapshotBuilder.make(store: store, archive: archive)
  }

  private var hero: some View {
    SignalASISecurityHeroView(
      title: t("cc_memory_overview_title", "Your private memory"),
      subtitle: t(
        "cc_memory_overview_subtitle",
        "Encrypted on this device, organized by purpose, and always under your control"
      ),
      systemImage: "brain",
      tint: store.agentSafetySettings.memoryCapture ? .signalASIAccent : .orange,
      badge: store.agentSafetySettings.memoryCapture
        ? t("cc_memory_capture_on", "Automatic memory on")
        : t("cc_memory_capture_off", "Automatic memory off")
    )
  }

  private var metrics: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
      ],
      spacing: 8
    ) {
      SignalASIMemoryMetricCard(
        title: t("cc_memory_metric_current", "Current"),
        value: "\(snapshot.temporal.count(.current))",
        systemImage: "checkmark.circle",
        tint: .signalASIAccent
      )
      SignalASIMemoryMetricCard(
        title: t("cc_memory_metric_planned", "Planned"),
        value: "\(snapshot.temporal.count(.planned))",
        systemImage: "calendar.badge.clock",
        tint: .blue
      )
      SignalASIMemoryMetricCard(
        title: t("cc_memory_metric_pending", "Review"),
        value: "\(snapshot.temporal.count(.pending))",
        systemImage: "exclamationmark.shield",
        tint: snapshot.temporal.count(.pending) == 0 ? .signalASIAccent : .orange
      )
    }
  }

  private var categoriesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_categories", "Memory Categories"))
      SignalASISecurityNavigationRow(
        title: t("cc_memory_identity_preferences_title", "Identity & Preferences"),
        subtitle: t("cc_memory_identity_preferences_subtitle", "Language, response style, defaults, and personal preferences"),
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: "\(snapshot.count(kinds: [.identity, .preference]))"
      ) {
        SignalASIMemoryKindView(
          title: t("cc_memory_identity_preferences_title", "Identity & Preferences"),
          subtitle: t("cc_memory_identity_preferences_subtitle", "Language, response style, defaults, and personal preferences"),
          kinds: [.identity, .preference],
          systemImage: "person.crop.circle",
          tint: .blue
        )
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_people_title", "People & Relationships"),
        subtitle: t("cc_memory_people_subtitle", "Trusted contacts, roles, names, and relationship context"),
        systemImage: "person.2",
        tint: .signalASIAccent,
        badge: "\(snapshot.count(kinds: [.contact]))"
      ) {
        SignalASIMemoryKindView(
          title: t("cc_memory_people_title", "People & Relationships"),
          subtitle: t("cc_memory_people_subtitle", "Trusted contacts, roles, names, and relationship context"),
          kinds: [.contact],
          systemImage: "person.2",
          tint: .signalASIAccent
        )
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_work_title", "Projects & Workflows"),
        subtitle: t("cc_memory_work_subtitle", "Tasks, project context, recurring procedures, and decisions"),
        systemImage: "clock.arrow.circlepath",
        tint: .purple,
        badge: "\(snapshot.count(kinds: [.task, .workflow]))"
      ) {
        SignalASIMemoryKindView(
          title: t("cc_memory_work_title", "Projects & Workflows"),
          subtitle: t("cc_memory_work_subtitle", "Tasks, project context, recurring procedures, and decisions"),
          kinds: [.task, .workflow],
          systemImage: "clock.arrow.circlepath",
          tint: .purple
        )
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_knowledge_title", "Knowledge & Safety"),
        subtitle: t("cc_memory_knowledge_subtitle", "Learned facts, safety boundaries, and trusted operating rules"),
        systemImage: "book.closed",
        tint: .orange,
        badge: "\(snapshot.count(kinds: [.knowledge, .safety]))"
      ) {
        SignalASIMemoryKindView(
          title: t("cc_memory_knowledge_title", "Knowledge & Safety"),
          subtitle: t("cc_memory_knowledge_subtitle", "Learned facts, safety boundaries, and trusted operating rules"),
          kinds: [.knowledge, .safety],
          systemImage: "book.closed",
          tint: .orange
        )
      }
    }
  }

  private var controlsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_controls", "Memory Controls"))
      SignalASISecurityActionRow(
        title: t("cc_memory_capture_title", "Remember useful context"),
        subtitle: t("cc_memory_capture_subtitle", "Only durable, low-risk context is eligible for long-term memory"),
        systemImage: "lock.shield",
        tint: store.agentSafetySettings.memoryCapture ? .signalASIAccent : .orange,
        badge: store.agentSafetySettings.memoryCapture
          ? t("signalasi.status.on", "On")
          : t("signalasi.status.off", "Off")
      ) {
        store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
        reload()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_manage_title", "Manage all memories"),
        subtitle: t("cc_memory_manage_subtitle", "Review, edit, pin, resolve conflicts, or delete individual memories"),
        systemImage: "archivebox",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        SignalASIAgentMemoryView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.memory_control.telemetry_title", "Memory telemetry"),
        subtitle: t("signalasi.memory_control.telemetry_subtitle", "Inspect capture counts, retention, and local memory activity"),
        systemImage: "chart.xyaxis.line",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        SignalASIAgentMemoryTelemetryView()
      }
    }
  }

  private var lifecycleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_lifecycle", "Memory Lifecycle"))
      lifecycleRow(
        state: .current,
        title: t("cc_memory_state_current_title", "Current state"),
        subtitle: t("cc_memory_state_current_subtitle", "Facts and decisions SignalASI currently treats as true"),
        systemImage: "checkmark.circle",
        tint: .signalASIAccent
      )
      lifecycleRow(
        state: .planned,
        title: t("cc_memory_state_planned_title", "Planned state"),
        subtitle: t("cc_memory_state_planned_subtitle", "Goals and future changes that are not current facts yet"),
        systemImage: "calendar.badge.clock",
        tint: .blue
      )
      lifecycleRow(
        state: .historical,
        title: t("cc_memory_state_historical_title", "Historical state"),
        subtitle: t("cc_memory_state_historical_subtitle", "Past observations and completed state retained as evidence"),
        systemImage: "clock.arrow.circlepath",
        tint: .signalASITextSecondary
      )
      lifecycleRow(
        state: .deprecated,
        title: t("cc_memory_state_deprecated_title", "Deprecated state"),
        subtitle: t("cc_memory_state_deprecated_subtitle", "Facts and decisions replaced by newer accepted evidence"),
        systemImage: "archivebox",
        tint: .signalASITextSecondary
      )
      lifecycleRow(
        state: .pending,
        title: t("cc_memory_state_review_title", "Waiting for review"),
        subtitle: t("cc_memory_state_pending_subtitle", "Identity, preference, and safety changes waiting for your decision"),
        systemImage: "exclamationmark.shield",
        tint: snapshot.temporal.count(.pending) == 0 ? .signalASIAccent : .orange
      )
      lifecycleRow(
        state: .conflicted,
        title: t("cc_memory_state_conflicted_title", "Conflicted state"),
        subtitle: t("cc_memory_state_conflicted_subtitle", "Competing evidence that has not been resolved"),
        systemImage: "shield.lefthalf.filled",
        tint: snapshot.temporal.count(.conflicted) == 0 ? .signalASIAccent : .orange
      )
    }
  }

  private var evolutionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_evolution", "Memory Evolution"))
      SignalASISecurityNavigationRow(
        title: t("cc_memory_inbox_title", "Memory inbox"),
        subtitle: t("cc_memory_inbox_subtitle", "Review identity, preference, safety, and conflicting memory candidates"),
        systemImage: "tray",
        tint: snapshot.pendingCandidates.isEmpty ? .signalASIAccent : .orange,
        badge: "\(snapshot.pendingCandidates.count)"
      ) {
        SignalASIMemoryInboxView(statusFilter: nil)
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_evolution_history_title", "Memory evolution history"),
        subtitle: t("cc_memory_evolution_history_subtitle", "Review why durable memory was added, strengthened, replaced, or gated"),
        systemImage: "clock.arrow.circlepath",
        tint: .purple,
        badge: "\(snapshot.archive.records.count)"
      ) {
        SignalASIMemoryEvolutionHistoryView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_graph_title", "Relationship graph"),
        subtitle: t("cc_memory_graph_subtitle", "Explore current entities, states, and multi-hop relationships"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .blue,
        badge: String(
          format: t("cc_memory_graph_status", "%d entities · %d relations"),
          snapshot.world.items.count,
          snapshot.relations.count
        )
      ) {
        SignalASIMemoryGraphView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_audit_title", "Memory health"),
        subtitle: t("cc_memory_audit_subtitle", "Find stale, conflicting, repeated, and promotable knowledge"),
        systemImage: "checkmark.shield",
        tint: snapshot.archive.audit.findings.isEmpty ? .signalASIAccent : .orange,
        badge: "\(snapshot.archive.audit.findings.count)"
      ) {
        SignalASIMemoryAuditView()
      }
    }
  }

  private func lifecycleRow(
    state: GlobalMemoryTemporalState,
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    SignalASISecurityNavigationRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: "\(snapshot.temporal.count(state))"
    ) {
      SignalASIMemoryLifecycleView(state: state)
    }
  }

  private func reload() {
    archive = evolutionStore.exportArchive()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIMemoryControlSnapshot {
  var agent: AgentMemorySnapshot
  var archive: GlobalMemoryEvolutionArchive
  var world: PersonalWorldModel
  var temporal: GlobalMemoryTemporalSnapshot
  var relations: [SignalASIMemoryGraphRelation]

  var pendingCandidates: [GlobalMemoryCandidate] {
    archive.inbox.pending()
  }

  func count(kinds: Set<AgentMemoryKind>) -> Int {
    agent.activeItems.filter { kinds.contains($0.kind) }.count
  }
}

struct SignalASIMemoryGraphRelation: Identifiable, Equatable {
  var id: String
  var title: String
  var subtitle: String
  var badge: String
  var lastSeenAtMillis: Int64
}

enum SignalASIMemorySnapshotBuilder {
  static func make(store: SignalASIStore, archive: GlobalMemoryEvolutionArchive) -> SignalASIMemoryControlSnapshot {
    let agent = store.agentMemorySnapshot()
    let world = personalWorld(from: agent)
    let temporal = GlobalMemoryTemporalPolicy.snapshot(world: world, inbox: archive.inbox)
    return SignalASIMemoryControlSnapshot(
      agent: agent,
      archive: archive,
      world: world,
      temporal: temporal,
      relations: graphRelations(world: world)
    )
  }

  static func personalWorld(from snapshot: AgentMemorySnapshot) -> PersonalWorldModel {
    var itemsById: [String: GlobalWorldItem] = [:]
    for item in snapshot.historyItems {
      itemsById[item.id] = globalItem(from: item, status: .superseded, temporalState: .deprecated)
    }
    for conflict in snapshot.conflicts {
      for item in conflict.candidates {
        itemsById[item.id] = globalItem(from: item, status: .conflicted, temporalState: .conflicted)
      }
    }
    for item in snapshot.activeItems {
      itemsById[item.id] = globalItem(
        from: item,
        status: item.status == .conflicted ? .conflicted : .active,
        temporalState: item.status == .conflicted ? .conflicted : .current
      )
    }
    let items = itemsById.values.sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }
    return PersonalWorldModel(items: items, updatedAtMillis: GlobalMemoryClock.nowMillis())
  }

  static func graphRelations(world: PersonalWorldModel) -> [SignalASIMemoryGraphRelation] {
    let itemsById = Dictionary(uniqueKeysWithValues: world.items.map { ($0.id, $0) })
    var relations: [SignalASIMemoryGraphRelation] = []
    var seen = Set<String>()

    for item in world.items {
      for previousId in item.supersedesItemIds {
        guard let previous = itemsById[previousId] else { continue }
        let id = "supersedes:\(previous.id):\(item.id)"
        guard seen.insert(id).inserted else { continue }
        relations.append(SignalASIMemoryGraphRelation(
          id: id,
          title: "\(previous.topic.ifBlank(previous.kind.rawValue)) -> \(item.topic.ifBlank(item.kind.rawValue))",
          subtitle: "supersedes",
          badge: item.temporalState.rawValue,
          lastSeenAtMillis: max(item.lastSeenAtMillis, previous.lastSeenAtMillis)
        ))
      }
      if !item.supersededByItemId.isEmpty, let replacement = itemsById[item.supersededByItemId] {
        let id = "replaced:\(item.id):\(replacement.id)"
        guard seen.insert(id).inserted else { continue }
        relations.append(SignalASIMemoryGraphRelation(
          id: id,
          title: "\(item.topic.ifBlank(item.kind.rawValue)) -> \(replacement.topic.ifBlank(replacement.kind.rawValue))",
          subtitle: "replaced by",
          badge: replacement.temporalState.rawValue,
          lastSeenAtMillis: max(item.lastSeenAtMillis, replacement.lastSeenAtMillis)
        ))
      }
    }

    let conflictGroups = Dictionary(grouping: world.items.filter { !$0.conflictGroupId.isEmpty }, by: \.conflictGroupId)
    for group in conflictGroups.values where group.count > 1 {
      let sorted = group.sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }
      for pair in zip(sorted, sorted.dropFirst()) {
        let id = "conflict:\(pair.0.id):\(pair.1.id)"
        guard seen.insert(id).inserted else { continue }
        relations.append(SignalASIMemoryGraphRelation(
          id: id,
          title: "\(pair.0.topic.ifBlank(pair.0.kind.rawValue)) -> \(pair.1.topic.ifBlank(pair.1.kind.rawValue))",
          subtitle: "conflicts with",
          badge: GlobalMemoryTemporalState.conflicted.rawValue,
          lastSeenAtMillis: max(pair.0.lastSeenAtMillis, pair.1.lastSeenAtMillis)
        ))
      }
    }

    return relations.sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }
  }

  static func reviewRecord(
    candidate: GlobalMemoryCandidate,
    outcome: GlobalMemoryEvolutionOutcome,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> GlobalMemoryEvolutionRecord {
    GlobalMemoryEvolutionRecord(
      id: "memory-review:\(candidate.id):\(outcome.rawValue):\(nowMillis)",
      sourceEventId: candidate.sourceEventId,
      conversationId: candidate.conversationId,
      candidateId: candidate.id,
      kind: candidate.kind,
      action: candidate.action,
      outcome: outcome,
      temporalState: candidate.temporalState,
      subject: candidate.item.value.ifBlank(candidate.item.topic),
      targetItemIds: candidate.targetItemIds,
      resultingItemId: candidate.item.id,
      evidenceCount: candidate.item.evidenceCount,
      createdAtMillis: nowMillis
    )
  }

  private static func globalItem(
    from item: AgentMemoryItem,
    status: GlobalWorldItemStatus,
    temporalState: GlobalMemoryTemporalState
  ) -> GlobalWorldItem {
    GlobalWorldItem(
      id: item.id,
      stableKey: item.key.ifBlank("\(item.kind.rawValue.lowercased()):\(item.id)"),
      kind: worldKind(for: item.kind),
      layer: worldLayer(for: item.kind),
      namespace: namespace(for: item.kind),
      namespaceId: item.scopeId,
      topic: item.key.ifBlank(kindTopic(for: item.kind)),
      value: item.value,
      confidence: item.confidence,
      evidenceCount: item.evidenceCount,
      conversationIds: item.scope == .conversation && !item.scopeId.isEmpty ? [item.scopeId] : [],
      evidenceEventIds: item.source.isEmpty ? [] : [item.source],
      status: status,
      temporalState: temporalState,
      conflictGroupId: item.conflictGroupId,
      supersedesItemIds: item.supersedesId.isEmpty ? [] : [item.supersedesId],
      supersededByItemId: "",
      firstSeenAtMillis: item.timestampMillis,
      lastSeenAtMillis: max(item.lastConfirmedAtMillis, item.timestampMillis),
      expiresAtMillis: item.expiresAtMillis
    )
  }

  private static func worldKind(for kind: AgentMemoryKind) -> GlobalWorldItemKind {
    switch kind {
    case .identity: return .state
    case .contact: return .topic
    case .task: return .task
    case .preference: return .preference
    case .workflow: return .decision
    case .knowledge: return .fact
    case .safety: return .risk
    }
  }

  private static func worldLayer(for kind: AgentMemoryKind) -> GlobalWorldLayer {
    switch kind {
    case .identity, .preference, .safety: return .user
    case .contact, .task, .workflow, .knowledge: return .topic
    }
  }

  private static func namespace(for kind: AgentMemoryKind) -> GlobalMemoryNamespace {
    switch kind {
    case .identity, .preference, .contact: return .user
    case .task, .workflow: return .project
    case .knowledge: return .general
    case .safety: return .security
    }
  }

  private static func kindTopic(for kind: AgentMemoryKind) -> String {
    kind.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
  }
}

struct SignalASIMemoryMetricCard: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(tint)
        Spacer(minLength: 0)
      }
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
