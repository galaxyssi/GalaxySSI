import SwiftUI

private enum SignalASICapabilityLibraryKind: String, CaseIterable, Identifiable {
  case nativeTools
  case mcp
  case automation

  var id: String { rawValue }
}

struct SignalASICapabilityLibraryView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedKind: SignalASICapabilityLibraryKind = .nativeTools

  private var nativeTools: [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: AgentPhoneCapabilityCatalog.declaredStatuses()
    )
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  private var mcpConnections: [AgentMcpConnection] {
    SignalASIMcpControlStores.makeRegistry().list()
  }

  private var automationTasks: [AgentProactiveTask] {
    store.automationTasks()
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("agent_capability_library_title", "Capability Library"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("agent_capability_library_title", "Capability Library"),
            subtitle: t(
              "agent_capability_library_subtitle",
              "Manage phone tools, MCP connections, and reusable automation from one place"
            ),
            systemImage: "shippingbox.and.arrow.down",
            tint: .signalASIAccent,
            badge: String(format: t("signalasi.capability_library.total", "%d types"), SignalASICapabilityLibraryKind.allCases.count)
          )

          Picker(
            t("signalasi.capability_library.tabs", "Capability type"),
            selection: $selectedKind
          ) {
            Text(t("signalasi.capability_library.native_tools", "Native Tools"))
              .tag(SignalASICapabilityLibraryKind.nativeTools)
            Text(t("agent_mcp_title", "MCP"))
              .tag(SignalASICapabilityLibraryKind.mcp)
            Text(t("signalasi.automation.title", "Automation"))
              .tag(SignalASICapabilityLibraryKind.automation)
          }
          .pickerStyle(.segmented)
          .accessibilityLabel(t("signalasi.capability_library.tabs", "Capability type"))

          selectedContent
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedKind {
    case .nativeTools:
      nativeToolsContent
    case .mcp:
      mcpContent
    case .automation:
      automationContent
    }
  }

  private var nativeToolsContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.capability_library.native_section", "Phone Native Tools"))
      SignalASISecurityStatusRow(
        title: String(format: t("signalasi.capability_library.native_summary", "%d tools / %d available"), nativeTools.count, nativeTools.filter(isAvailable).count),
        subtitle: t("signalasi.capability_library.native_subtitle", "Built-in iOS tools stay inside the local permission and confirmation boundary"),
        systemImage: "iphone.and.arrow.forward",
        tint: .signalASIAccent,
        badge: t("agent_marketplace_built_in", "Built in")
      )
      ForEach(Array(nativeTools.prefix(6))) { tool in
        SignalASISecurityNavigationRow(
          title: tool.title,
          subtitle: tool.description,
          systemImage: "wrench.and.screwdriver",
          tint: isAvailable(tool) ? .signalASIAccent : .orange,
          badge: statusLabel(tool)
        ) {
          SignalASINativeToolDetailView(tool: tool)
        }
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.capability_library.open_native_catalog", "Open Native Tool Catalog"),
        subtitle: t("signalasi.capability_library.open_native_catalog_subtitle", "Review every tool, schema, risk, permission, and consent"),
        systemImage: "list.bullet.rectangle",
        tint: .blue,
        badge: "\(nativeTools.count)"
      ) {
        SignalASINativeToolCatalogView()
      }
    }
  }

  private var mcpContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.capability_library.mcp_section", "MCP Services"))
      SignalASISecurityStatusRow(
        title: String(format: t("signalasi.capability_library.mcp_summary", "%d installed connections"), mcpConnections.count),
        subtitle: t("signalasi.capability_library.mcp_subtitle", "Connect remote services or install verified local MCP packages"),
        systemImage: "shippingbox",
        tint: .blue,
        badge: mcpConnections.isEmpty ? t("agent_capability_requires_setup", "Setup") : t("status_ready", "Ready")
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.capability_library.open_mcp", "Manage MCP"),
        subtitle: t("signalasi.capability_library.open_mcp_subtitle", "Add services, install packages, test connections, and review permissions"),
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIMcpControlCenterView()
      }
    }
  }

  private var automationContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.capability_library.automation_section", "Reusable Automation"))
      SignalASISecurityStatusRow(
        title: String(format: t("signalasi.capability_library.automation_summary", "%d proactive tasks"), automationTasks.count),
        subtitle: t("signalasi.capability_library.automation_subtitle", "Create workflows, schedules, and device event triggers that can run after the app restarts"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: .orange,
        badge: automationTasks.filter { $0.enabled }.isEmpty ? t("common_off", "Off") : t("status_enabled", "Enabled")
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.capability_library.open_automation", "Manage Automation"),
        subtitle: t("signalasi.capability_library.open_automation_subtitle", "Review tasks, workflows, schedules, triggers, and recent runs"),
        systemImage: "clock",
        tint: .orange,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIAutomationView()
      }
    }
  }

  private func isAvailable(_ tool: AgentNativeToolDescriptor) -> Bool {
    tool.risk != .blocked && tool.availability.status == .available
  }

  private func statusLabel(_ tool: AgentNativeToolDescriptor) -> String {
    switch tool.availability.status {
    case .available:
      return t("signalasi.capability_library.available", "Available")
    case .requiresSetup:
      return t("agent_capability_requires_setup", "Setup")
    case .unavailable:
      return t("badge_unavailable", "Unavailable")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
