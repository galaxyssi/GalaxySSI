import SwiftUI

struct DiscoverView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var myQRCodePresented = false
  var showsBackButton = true
  var onBackToSettings: (() -> Void)? = nil

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.discover.title", "Discover"),
          leading: {
            if showsBackButton {
              SignalASIBackButton()
            } else if let onBackToSettings {
              Button(action: onBackToSettings) {
                Image(systemName: "chevron.left")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundColor(.signalASITextPrimary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(t("signalasi.common.back", "Back")))
            } else {
              Color.clear
            }
          },
          trailing: { Color.clear }
        )
        ScrollView {
          VStack(spacing: 10) {
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.ai_agent_title", "AI Agent"),
                subtitle: t("signalasi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
                systemImage: "cpu",
                assetImageName: "DiscoverAiAgent",
                tint: .signalASIAccent
              ) {
                SignalASIMyAgentsView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.add_cloud_model", "Add Cloud Model"),
                subtitle: t(
                  "signalasi.discover.add_cloud_model_subtitle",
                  "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
                ),
                systemImage: "cloud.fill",
                assetImageName: "DiscoverAiAgent",
                tint: .signalASIInsightText
              ) {
                CloudModelProviderSelectionView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.device_center", "Device Center"),
                subtitle: t("signalasi.discover.device.subtitle", "Manage and control your devices"),
                systemImage: "antenna.radiowaves.left.and.right",
                assetImageName: "DiscoverDevice",
                tint: .signalASIAccent
              ) {
                DeviceManagementView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.automation.title", "Automation"),
                subtitle: t("signalasi.automation.hero_subtitle", "Create and manage automated tasks"),
                systemImage: "clock",
                assetImageName: "DiscoverAutomation",
                tint: .orange
              ) {
                SignalASIAutomationView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.security_center_title", "Security Center"),
                subtitle: t("signalasi.discover.security_center_subtitle", "View security status and permissions"),
                systemImage: "checkmark.shield",
                assetImageName: "DiscoverSecurity",
                tint: .signalASIAccent
              ) {
                SignalASISecurityCenterView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.lab_title", "Lab"),
                subtitle: t("signalasi.discover.lab_subtitle", "Explore frontier features"),
                systemImage: "sparkles",
                assetImageName: "DiscoverLab",
                tint: .purple
              ) {
                SignalASILocalModelLabView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.scan_title", "Scan"),
                subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
                systemImage: "qrcode.viewfinder",
                assetImageName: "DiscoverScan",
                tint: .signalASIAccent
              ) {
                AddContactView(autoOpenScanner: true)
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuButton(
                title: t("signalasi.discover.my_qr_title", "My QR Code"),
                subtitle: t("signalasi.discover.my_qr_subtitle", "Show this device identity"),
                systemImage: "qrcode",
                assetImageName: "DiscoverScan",
                tint: .signalASITextPrimary
              ) {
                myQRCodePresented = true
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.create_group_title", "Create Group"),
                subtitle: t("signalasi.discover.create_group_subtitle", "Secure multi-person communication"),
                systemImage: "person.3",
                assetImageName: "DiscoverGroup",
                tint: .signalASIAccent
              ) {
                SignalASICreateGroupView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("cc_profile_title", "My SignalASI"),
                subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
                systemImage: "person.crop.circle",
                assetImageName: "DiscoverProfile",
                tint: .signalASITextPrimary
              ) {
                SignalASIProfileIdentityView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("settings_my_signalasi", "My SignalASI"),
                subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
                systemImage: "slider.horizontal.3",
                assetImageName: "DiscoverSignalASI",
                tint: .signalASIAccent
              ) {
                SignalASIControlCenterView()
              }
            }
            SignalASIAndroidMenuLink(
              title: t("cc_learning_title", "Learning & Skill Evolution"),
              subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
              systemImage: "sparkles.rectangle.stack",
              tint: .purple
            ) {
              SignalASILearningSkillEvolutionView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_agent_core_title", "Agent Core"),
              subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
              systemImage: "cpu",
              tint: .signalASIAccent
            ) {
              SignalASIAgentCoreView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_permissions_title", "Permissions & Audit"),
              subtitle: t("cc_recent_operations_subtitle", "Review native tools, Agent actions, and confirmation decisions"),
              systemImage: "hand.raised",
              tint: .orange
            ) {
              SignalASIPermissionsAuditView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
              subtitle: t("cc_privacy_dashboard_subtitle", "See what data leaves this phone and where it is processed"),
              systemImage: "lock.doc",
              tint: .signalASIInsightText
            ) {
              SignalASIPrivacyDashboardView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_data_title", "Data & Backup"),
              subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
              systemImage: "externaldrive",
              tint: .signalASIInsightText
            ) {
              SignalASIDataBackupView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_execution_policy_title", "Execution Policy"),
              subtitle: t("cc_permission_mode_banner_subtitle", "This setting is enforced by the local safety policy before every action."),
              systemImage: "checkmark.shield",
              tint: .orange
            ) {
              SignalASIExecutionPolicyView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_system_status_title", "System Status"),
              subtitle: systemStatusSubtitle,
              systemImage: systemStatusIcon,
              tint: systemStatusTint
            ) {
              SignalASISystemStatusView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.pairing", "Pairing"),
              subtitle: t("signalasi.discover.pairing.subtitle", "Scan QR codes and connect SignalASI Desktop"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              PairingView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.agent_memory.telemetry_title", "Agent Memory"),
              subtitle: t("signalasi.agent_memory.telemetry_subtitle", "iOS resident memory sampled across active Agent tasks"),
              systemImage: "memorychip",
              tint: .purple
            ) {
              SignalASIAgentMemoryTelemetryView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.voice", "Voice"),
              subtitle: t("signalasi.discover.voice.subtitle", "Wake, transcription and local voice models"),
              systemImage: "waveform",
              tint: .signalASIInsightText
            ) {
              SignalASIVoiceControlCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_general_page_title", "General"),
              subtitle: t("signalasi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"),
              systemImage: "gearshape",
              tint: .signalASIInsightText
            ) {
              SignalASIGeneralControlCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_runtime_title", "On-device Linux Runtime"),
              subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
              systemImage: "terminal",
              tint: .teal
            ) {
              SignalASIOnDeviceRuntimeView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_nodes_title", "Agents, Models & Nodes"),
              subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
              systemImage: "link.circle",
              tint: .signalASIInsightText
            ) {
              SignalASIAgentsModelsNodesView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_smart_spaces_title", "Smart Spaces"),
              subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
              systemImage: "house",
              tint: .purple
            ) {
              SignalASISmartSpacesView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_resource_routing_title", "Models & Resource Routing"),
              subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
              systemImage: "point.3.connected.trianglepath.dotted",
              tint: .blue
            ) {
              SignalASIResourceRoutingView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_phone_title", "Phone Capabilities"),
              subtitle: phoneCapabilitiesSummary,
              systemImage: "iphone",
              tint: nativeToolSummary.available > 0 ? .signalASIAccent : .orange
            ) {
              SignalASIPhoneCapabilitiesView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.model_planner", "Model Planner"),
              subtitle: t("signalasi.discover.planner.subtitle", "Agent planning, budget and model routing"),
              systemImage: "slider.horizontal.3",
              tint: .signalASIInsightText
            ) {
              AgentModelPlannerSettingsView()
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .sheet(isPresented: $myQRCodePresented) {
        MyContactQRCodeView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var nativeToolSummary: (total: Int, available: Int, needingAttention: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available, max(tools.count - available, 0))
  }

  private var phoneCapabilitiesSummary: String {
    String(
      format: t("cc_phone_subtitle", "%d native tools - %d need attention"),
      nativeToolSummary.available,
      nativeToolSummary.needingAttention
    )
  }

  private var systemStatusIcon: String {
    systemStatusNeedsAttention ? "exclamationmark.triangle" : "checkmark.shield"
  }

  private var systemStatusTint: Color {
    systemStatusNeedsAttention ? .orange : .signalASIAccent
  }

  private var systemStatusSubtitle: String {
    systemStatusNeedsAttention
      ? t("cc_services_need_attention_subtitle", "Unavailable resources are excluded from automatic routing")
      : t("cc_all_services_normal_subtitle", "Local execution, routing, messaging, and security are available")
  }

  private var systemStatusNeedsAttention: Bool {
    store.agentSafetySettings.executionPaused ||
      !systemStatusLinkReady ||
      systemStatusAvailableResourceCount == 0
  }

  private var systemStatusLinkReady: Bool {
    store.serverLinks.contains(where: \.paired) &&
      SignalASILinkTransportDiagnostics.snapshot().failureCount == 0
  }

  private var systemStatusAvailableResourceCount: Int {
    store.cloudModelContacts.count +
      store.serverLinks.filter(\.paired).count +
      store.customDeviceConnectors.filter(\.enabled).count
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
