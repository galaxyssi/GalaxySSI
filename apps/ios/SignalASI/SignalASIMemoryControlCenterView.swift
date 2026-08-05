import SwiftUI

struct SignalASIMemoryControlCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var inbox = GlobalMemoryInbox()
  @State private var auditReport = GlobalMemoryAuditReport()
  @State private var evolutionRecords: [GlobalMemoryEvolutionRecord] = []
  @State private var statusMessage = ""

  private let evolutionStore = GlobalMemoryEvolutionStore()

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_memory_title", "Memory & Personalization"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_memory_overview_title", "Your private memory"),
            subtitle: t(
              "cc_memory_overview_subtitle",
              "Encrypted on this device, organized by purpose, and always under your control"
            ),
            systemImage: "brain.head.profile",
            tint: .purple,
            badge: store.agentSafetySettings.memoryCapture
              ? t("cc_memory_capture_on", "Automatic memory on")
              : t("cc_memory_capture_off", "Automatic memory off")
          )

          SignalASIMemoryMetricStrip(snapshot: snapshot, language: interfaceLanguage)

          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("cc_memory_status_title", "Memory status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }

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
    .onAppear(perform: refresh)
  }

  private var snapshot: SignalASIMemoryControlSnapshot {
    SignalASIMemoryControlSnapshot.make(
      agentMemory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      inbox: inbox,
      evolutionRecords: evolutionRecords,
      auditReport: auditReport
    )
  }

  private var categoriesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_categories", "Memory Categories"))
      ForEach(Self.categories) { category in
        SignalASISecurityNavigationRow(
          title: t(category.titleKey, category.titleFallback),
          subtitle: t(category.subtitleKey, category.subtitleFallback),
          systemImage: category.systemImage,
          tint: color(category.tone),
          badge: "\(snapshot.activeCount(for: category.kinds))"
        ) {
          SignalASIMemoryCategoryView(category: category)
        }
      }
    }
  }

  private var controlsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_controls", "Memory Controls"))
      SignalASIMemoryCaptureRow(
        title: t("cc_memory_capture_title", "Remember useful context"),
        subtitle: t(
          "cc_memory_capture_subtitle",
          "Only durable, low-risk context is eligible for long-term memory"
        ),
        isOn: store.agentSafetySettings.memoryCapture,
        onToggle: {
          store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
          statusMessage = store.agentSafetySettings.memoryCapture
            ? t("cc_memory_capture_on", "Automatic memory on")
            : t("cc_memory_capture_off", "Automatic memory off")
        }
      )
      SignalASISecurityNavigationRow(
        title: t("cc_memory_manage_title", "Manage all memories"),
        subtitle: t(
          "cc_memory_manage_subtitle",
          "Review, edit, pin, resolve conflicts, or delete individual memories"
        ),
        systemImage: "brain",
        tint: .purple,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIAgentMemoryView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.agent_knowledge.title", "Knowledge"),
        subtitle: t(
          "cc_memory_knowledge_library_subtitle",
          "Imported documents and private facts that can ground Agent answers"
        ),
        systemImage: "books.vertical",
        tint: .blue,
        badge: "\(snapshot.knowledgeStats.itemCount)"
      ) {
        SignalASIAgentKnowledgeView()
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
        systemImage: "brain",
        tone: .green,
        count: snapshot.temporal.count(.current)
      )
      lifecycleRow(
        state: .planned,
        title: t("cc_memory_state_planned_title", "Planned state"),
        subtitle: t("cc_memory_state_planned_subtitle", "Goals and future changes that are not current facts yet"),
        systemImage: "calendar.badge.clock",
        tone: .blue,
        count: snapshot.temporal.count(.planned)
      )
      lifecycleRow(
        state: .historical,
        title: t("cc_memory_state_history_title", "Historical and replaced"),
        subtitle: t("cc_memory_state_history_subtitle", "Previous facts remain distinguishable from the current world model"),
        systemImage: "clock.arrow.circlepath",
        tone: .neutral,
        count: snapshot.temporal.count(.historical)
      )
      lifecycleRow(
        state: .deprecated,
        title: t("cc_memory_state_deprecated_title", "Superseded state"),
        subtitle: t("cc_memory_state_deprecated_subtitle", "Expired or replaced memory is kept out of current grounding"),
        systemImage: "archivebox",
        tone: .neutral,
        count: snapshot.temporal.count(.deprecated)
      )
      lifecycleRow(
        state: .pending,
        title: t("cc_memory_state_review_title", "Waiting for review"),
        subtitle: t(
          "cc_memory_state_review_subtitle",
          "Identity, preference, safety, and conflicting changes require a decision"
        ),
        systemImage: "tray",
        tone: snapshot.temporal.count(.pending) == 0 ? .green : .amber,
        count: snapshot.temporal.count(.pending)
      )
      lifecycleRow(
        state: .conflicted,
        title: t("cc_memory_state_conflicted_title", "Conflicted state"),
        subtitle: t("cc_memory_state_conflicted_subtitle", "Contradictory long-term state is isolated until resolved"),
        systemImage: "exclamationmark.shield",
        tone: snapshot.conflictCount == 0 ? .green : .amber,
        count: snapshot.conflictCount
      )
    }
  }

  private var evolutionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_memory_section_evolution", "Memory Evolution"))
      SignalASISecurityNavigationRow(
        title: t("cc_memory_inbox_title", "Memory inbox"),
        subtitle: t("cc_memory_inbox_subtitle", "Review identity, preference, safety, and conflicting memory candidates"),
        systemImage: "tray.full",
        tint: snapshot.pendingCandidates.isEmpty ? .signalASIAccent : .orange,
        badge: "\(snapshot.pendingCandidates.count)"
      ) {
        SignalASIMemoryInboxView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_evolution_history_title", "Memory evolution history"),
        subtitle: t("cc_memory_evolution_history_subtitle", "Review why durable memory was added, strengthened, replaced, or gated"),
        systemImage: "clock.badge.checkmark",
        tint: .purple,
        badge: "\(snapshot.evolutionRecords.count)"
      ) {
        SignalASIMemoryEvolutionHistoryView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_graph_title", "Relationship graph"),
        subtitle: t("cc_memory_graph_subtitle", "Explore current entities, states, and multi-hop relationships"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .blue,
        badge: String(
          format: t("cc_memory_graph_status", "%d entities / %d relations"),
          snapshot.graph.nodes.count,
          snapshot.graph.relations.count
        )
      ) {
        SignalASIMemoryGraphView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_memory_audit_title", "Memory health"),
        subtitle: t("cc_memory_audit_subtitle", "Find stale, conflicting, repeated, and promotable knowledge"),
        systemImage: "checkmark.shield",
        tint: snapshot.auditReport.findings.isEmpty ? .signalASIAccent : .orange,
        badge: "\(snapshot.auditReport.findings.count)"
      ) {
        SignalASIMemoryAuditView()
      }
    }
  }

  private func lifecycleRow(
    state: SignalASIMemoryLifecycleState,
    title: String,
    subtitle: String,
    systemImage: String,
    tone: SignalASIMemoryTone,
    count: Int
  ) -> some View {
    SignalASISecurityNavigationRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: color(tone),
      badge: "\(count)"
    ) {
      SignalASIMemoryLifecycleView(state: state)
    }
  }

  private func refresh() {
    inbox = evolutionStore.inbox()
    auditReport = evolutionStore.auditReport()
    evolutionRecords = evolutionStore.evolutionRecords()
  }

  private func color(_ tone: SignalASIMemoryTone) -> Color {
    switch tone {
    case .accent:
      return .signalASIAccent
    case .blue:
      return .blue
    case .green:
      return .signalASIAccent
    case .purple:
      return .purple
    case .amber:
      return .orange
    case .neutral:
      return .gray
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  static let categories: [SignalASIMemoryCategoryDescriptor] = [
    SignalASIMemoryCategoryDescriptor(
      id: "identity",
      titleKey: "cc_memory_identity_preferences_title",
      titleFallback: "Identity & Preferences",
      subtitleKey: "cc_memory_identity_preferences_subtitle",
      subtitleFallback: "Language, response style, defaults, and personal preferences",
      systemImage: "person.crop.circle.badge.checkmark",
      tone: .blue,
      kinds: [.identity, .preference]
    ),
    SignalASIMemoryCategoryDescriptor(
      id: "people",
      titleKey: "cc_memory_people_title",
      titleFallback: "People & Relationships",
      subtitleKey: "cc_memory_people_subtitle",
      subtitleFallback: "Trusted contacts, roles, names, and relationship context",
      systemImage: "person.2",
      tone: .green,
      kinds: [.contact]
    ),
    SignalASIMemoryCategoryDescriptor(
      id: "work",
      titleKey: "cc_memory_work_title",
      titleFallback: "Projects & Workflows",
      subtitleKey: "cc_memory_work_subtitle",
      subtitleFallback: "Tasks, project context, recurring procedures, and decisions",
      systemImage: "checklist",
      tone: .purple,
      kinds: [.task, .workflow]
    ),
    SignalASIMemoryCategoryDescriptor(
      id: "knowledge",
      titleKey: "cc_memory_knowledge_title",
      titleFallback: "Knowledge & Safety",
      subtitleKey: "cc_memory_knowledge_subtitle",
      subtitleFallback: "Learned facts, safety boundaries, and trusted operating rules",
      systemImage: "books.vertical",
      tone: .amber,
      kinds: [.knowledge, .safety]
    )
  ]
}

private struct SignalASIMemoryMetricStrip: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var snapshot: SignalASIMemoryControlSnapshot
  var language: String

  var body: some View {
    HStack(spacing: 8) {
      SignalASIMemoryMetricCell(value: "\(snapshot.temporal.count(.current))", label: t("cc_memory_metric_current", "Current"))
      SignalASIMemoryMetricCell(value: "\(snapshot.temporal.count(.planned))", label: t("cc_memory_metric_planned", "Planned"))
      SignalASIMemoryMetricCell(value: "\(snapshot.temporal.count(.pending))", label: t("cc_memory_metric_pending", "Review"))
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: language.isEmpty ? interfaceLanguage : language)
  }
}

private struct SignalASIMemoryMetricCell: View {
  var value: String
  var label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      Text(label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIMemoryCaptureRow: View {
  var title: String
  var subtitle: String
  var isOn: Bool
  var onToggle: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.signalASIAccent.opacity(0.16))
        Image(systemName: "lock.shield")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: Binding(
        get: { isOn },
        set: { _ in onToggle() }
      ))
      .labelsHidden()
      .tint(.signalASIAccent)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
