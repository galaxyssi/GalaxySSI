import SwiftUI

struct SignalASIAgentMemoryTelemetryView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var snapshot = AgentMemoryPssSnapshot()

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent_memory.telemetry_title", "Agent Memory"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button {
            refresh()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.agent_memory.telemetry_title", "Agent Memory"),
            subtitle: t("signalasi.agent_memory.telemetry_subtitle", "iOS resident memory sampled across active Agent tasks and grouped by execution identity"),
            systemImage: "memorychip",
            tint: .purple,
            badge: t("signalasi.agent_memory.pss_badge", "PSS")
          )
          metrics
          processSection
          sessionBudgetSection
          dimensionSection(
            title: t("signalasi.agent_memory.by_agent", "By Agent"),
            values: snapshot.byAgent
          )
          dimensionSection(
            title: t("signalasi.agent_memory.by_session", "By Session"),
            values: snapshot.bySession
          )
          dimensionSection(
            title: t("signalasi.agent_memory.by_provider", "By Provider"),
            values: snapshot.byProvider
          )
          footer
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

  private var metrics: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
      ],
      spacing: 8
    ) {
      SignalASIAgentMemoryMetricCard(
        title: t("signalasi.agent_memory.current", "Current"),
        value: formattedBytes(snapshot.processCurrentBytes),
        systemImage: "memorychip",
        tint: .purple
      )
      SignalASIAgentMemoryMetricCard(
        title: t("signalasi.agent_memory.peak", "Peak"),
        value: formattedBytes(snapshot.processPeakBytes),
        systemImage: "chart.bar",
        tint: .blue
      )
      SignalASIAgentMemoryMetricCard(
        title: t("signalasi.agent_memory.session_latest", "Latest session overhead"),
        value: formattedBytes(snapshot.sessionBudget.latestIncrementalBytes),
        systemImage: "plusminus.circle",
        tint: sessionBudgetTint
      )
    }
  }

  private var processSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.agent_memory.process_section", "App Process"))
      processRow(
        title: t("signalasi.agent_memory.process_total", "Total resident memory"),
        subtitle: t("signalasi.agent_memory.process_total_subtitle", "Physical memory currently used by the SignalASI process"),
        value: formattedBytes(snapshot.processCurrentBytes),
        systemImage: "memorychip",
        tint: .purple
      )
      processRow(
        title: t("signalasi.agent_memory.native", "Native memory"),
        subtitle: t("signalasi.agent_memory.native_subtitle", "Native runtime, Swift, Objective-C, and system libraries"),
        value: formattedBytes(snapshot.nativeBytes),
        systemImage: "cpu",
        tint: .blue
      )
      processRow(
        title: t("signalasi.agent_memory.managed", "Managed memory"),
        subtitle: t("signalasi.agent_memory.managed_subtitle", "Agent state, Swift models, and in-process task objects"),
        value: formattedBytes(snapshot.dalvikBytes),
        systemImage: "square.stack.3d.up",
        tint: .signalASIAccent
      )
      processRow(
        title: t("signalasi.agent_memory.other", "Other memory"),
        subtitle: t("signalasi.agent_memory.other_subtitle", "Graphics, code pages, stacks, caches, and shared mappings"),
        value: formattedBytes(snapshot.otherBytes),
        systemImage: "info.circle",
        tint: .signalASITextSecondary
      )
    }
  }

  private var sessionBudgetSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.agent_memory.session_section", "New Session Budget"))
      processRow(
        title: t("signalasi.agent_memory.session_latest", "Latest session overhead"),
        subtitle: t("signalasi.agent_memory.session_latest_subtitle", "Incremental SignalASI process memory after creating a conversation"),
        value: sessionLatestBadge,
        systemImage: "memorychip",
        tint: sessionBudgetTint
      )
      processRow(
        title: t("signalasi.agent_memory.session_peak", "Peak session overhead"),
        subtitle: t("signalasi.agent_memory.session_peak_subtitle", "Highest measured conversation-shell increment"),
        value: formattedBytes(snapshot.sessionBudget.peakIncrementalBytes),
        systemImage: "chart.bar",
        tint: snapshot.sessionBudget.peakIncrementalBytes <= snapshot.sessionBudget.targetBytes ? .signalASIAccent : .orange
      )
      processRow(
        title: t("signalasi.agent_memory.session_average", "Average session overhead"),
        subtitle: String(
          format: t("signalasi.agent_memory.session_average_subtitle", "%d measurements / %d over budget"),
          snapshot.sessionBudget.sampleCount,
          snapshot.sessionBudget.exceededCount
        ),
        value: formattedBytes(snapshot.sessionBudget.averageIncrementalBytes),
        systemImage: "divide.circle",
        tint: .blue
      )
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(t("signalasi.agent_memory.estimate_notice", "iOS exposes process-level resident memory. When multiple tasks share the process, SignalASI divides the current memory across active tasks and marks the attribution as an estimate."))
      Text(t("signalasi.agent_memory.session_notice", "Session overhead measures only the SignalASI conversation shell. External Codex, Claude Code, Hermes, OpenClaw, and model processes remain separate."))
    }
    .font(.system(size: 12))
    .foregroundColor(.signalASITextSecondary)
    .padding(.horizontal, 4)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func dimensionSection(title: String, values: [AgentMemoryDimensionStats]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: title)
      if values.isEmpty {
        processRow(
          title: t("signalasi.agent_memory.no_samples", "No attributed samples"),
          subtitle: t("signalasi.agent_memory.no_samples_subtitle", "Start an Agent task to collect this dimension"),
          value: "",
          systemImage: "info.circle",
          tint: .signalASITextSecondary
        )
      } else {
        ForEach(values.prefix(12)) { item in
          processRow(
            title: item.id,
            subtitle: String(
              format: t("signalasi.agent_memory.dimension_subtitle", "Peak %@ / %d samples"),
              formattedBytes(item.peakBytes),
              item.sampleCount
            ),
            value: formattedBytes(item.currentBytes),
            systemImage: "person.crop.circle",
            tint: item.estimated ? .orange : .signalASIAccent
          )
        }
      }
    }
  }

  private func processRow(
    title: String,
    subtitle: String,
    value: String,
    systemImage: String,
    tint: Color
  ) -> some View {
    SignalASISecurityStatusRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: value
    )
  }

  private var sessionBudgetTint: Color {
    if snapshot.sessionBudget.sampleCount == 0 {
      return .signalASITextSecondary
    }
    return snapshot.sessionBudget.withinBudget ? .signalASIAccent : .orange
  }

  private var sessionLatestBadge: String {
    guard snapshot.sessionBudget.sampleCount > 0 else {
      return t("signalasi.agent_memory.session_unmeasured", "Not measured")
    }
    let key = snapshot.sessionBudget.withinBudget
      ? "signalasi.agent_memory.session_target"
      : "signalasi.agent_memory.session_over"
    let fallback = snapshot.sessionBudget.withinBudget
      ? "Under %@ target"
      : "Over %@ target"
    return String(
      format: t(key, fallback),
      formattedBytes(snapshot.sessionBudget.targetBytes)
    )
  }

  private func refresh() {
    snapshot = AgentMemoryPssRuntime.snapshot()
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .memory)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIAgentMemoryMetricCard: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(tint)
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.64)
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
