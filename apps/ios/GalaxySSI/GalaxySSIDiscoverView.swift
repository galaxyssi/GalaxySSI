import SwiftUI

struct DiscoverView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var myQRCodePresented = false
  var showsBackButton = true
  var onBackToSettings: (() -> Void)? = nil

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        GalaxySSITopBar(
          title: t("galaxyssi.discover.title", "Discover"),
          leading: {
            if showsBackButton {
              GalaxySSIBackButton()
            } else if let onBackToSettings {
              Button(action: onBackToSettings) {
                Image(systemName: "chevron.left")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundColor(.galaxySSITextPrimary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
            } else {
              Color.clear
            }
          },
          trailing: { Color.clear }
        )
        ScrollView {
          VStack(spacing: 10) {
            GalaxySSIAndroidMenuGroup {
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.ai_agent_title", "AI Agent"),
                subtitle: t("galaxyssi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
                systemImage: "cpu",
                assetImageName: "DiscoverAiAgent",
                tint: .galaxySSIAccent
              ) {
                GalaxySSIMyAgentsView()
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.add_cloud_model", "Add Cloud Model"),
                subtitle: t(
                  "galaxyssi.discover.add_cloud_model_subtitle",
                  "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
                ),
                systemImage: "cloud.fill",
                assetImageName: "DiscoverAiAgent",
                tint: .galaxySSIInsightText
              ) {
                CloudModelProviderSelectionView()
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.device_center", "Device Center"),
                subtitle: t("galaxyssi.discover.device.subtitle", "Manage and control your devices"),
                systemImage: "antenna.radiowaves.left.and.right",
                assetImageName: "DiscoverDevice",
                tint: .galaxySSIAccent
              ) {
                DeviceManagementView()
              }
            }
            GalaxySSIAndroidMenuGroup {
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.automation.title", "Automation"),
                subtitle: t("galaxyssi.automation.hero_subtitle", "Create and manage automated tasks"),
                systemImage: "clock",
                assetImageName: "DiscoverAutomation",
                tint: .orange
              ) {
                GalaxySSIAutomationView()
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.security_center_title", "Security Center"),
                subtitle: t("galaxyssi.discover.security_center_subtitle", "View security status and permissions"),
                systemImage: "checkmark.shield",
                assetImageName: "DiscoverSecurity",
                tint: .galaxySSIAccent
              ) {
                GalaxySSISecurityCenterView()
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.lab_title", "Lab"),
                subtitle: t("galaxyssi.discover.lab_subtitle", "Explore frontier features"),
                systemImage: "sparkles",
                assetImageName: "DiscoverLab",
                tint: .purple
              ) {
                GalaxySSILocalModelLabView()
              }
            }
            GalaxySSIAndroidMenuGroup {
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.scan_title", "Scan"),
                subtitle: t("galaxyssi.discover.scan_subtitle", "Add contacts or devices"),
                systemImage: "qrcode.viewfinder",
                assetImageName: "DiscoverScan",
                tint: .galaxySSIAccent
              ) {
                AddContactView(autoOpenScanner: true)
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuButton(
                title: t("galaxyssi.discover.my_qr_title", "My QR Code"),
                subtitle: t("galaxyssi.discover.my_qr_subtitle", "Show this device identity"),
                systemImage: "qrcode",
                assetImageName: "DiscoverScan",
                tint: .galaxySSITextPrimary
              ) {
                myQRCodePresented = true
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("galaxyssi.discover.create_group_title", "Create Group"),
                subtitle: t("galaxyssi.discover.create_group_subtitle", "Secure multi-person communication"),
                systemImage: "person.3",
                assetImageName: "DiscoverGroup",
                tint: .galaxySSIAccent
              ) {
                GalaxySSICreateGroupView()
              }
            }
            GalaxySSIAndroidMenuGroup {
              GalaxySSIAndroidGroupedMenuLink(
                title: t("cc_profile_title", "My GalaxySSI"),
                subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
                systemImage: "person.crop.circle",
                assetImageName: "DiscoverProfile",
                tint: .galaxySSITextPrimary
              ) {
                GalaxySSIProfileIdentityView()
              }
              GalaxySSIAndroidMenuDivider()
              GalaxySSIAndroidGroupedMenuLink(
                title: t("settings_my_galaxyssi", "My GalaxySSI"),
                subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
                systemImage: "slider.horizontal.3",
                assetImageName: "DiscoverGalaxySSI",
                tint: .galaxySSIAccent
              ) {
                GalaxySSIControlCenterView()
              }
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_learning_title", "Learning & Skill Evolution"),
              subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
              systemImage: "sparkles.rectangle.stack",
              tint: .purple
            ) {
              GalaxySSILearningSkillEvolutionView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_agent_core_title", "Agent Core"),
              subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
              systemImage: "cpu",
              tint: .galaxySSIAccent
            ) {
              GalaxySSIAgentCoreView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_permissions_title", "Permissions & Audit"),
              subtitle: t("cc_recent_operations_subtitle", "Review native tools, Agent actions, and confirmation decisions"),
              systemImage: "hand.raised",
              tint: .orange
            ) {
              GalaxySSIPermissionsAuditView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
              subtitle: t("cc_privacy_dashboard_subtitle", "See what data leaves this phone and where it is processed"),
              systemImage: "lock.doc",
              tint: .galaxySSIInsightText
            ) {
              GalaxySSIPrivacyDashboardView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_data_title", "Data & Backup"),
              subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
              systemImage: "externaldrive",
              tint: .galaxySSIInsightText
            ) {
              GalaxySSIDataBackupView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_execution_policy_title", "Execution Policy"),
              subtitle: t("cc_permission_mode_banner_subtitle", "This setting is enforced by the local safety policy before every action."),
              systemImage: "checkmark.shield",
              tint: .orange
            ) {
              GalaxySSIExecutionPolicyView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_system_status_title", "System Status"),
              subtitle: systemStatusSubtitle,
              systemImage: systemStatusIcon,
              tint: systemStatusTint
            ) {
              GalaxySSISystemStatusView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("galaxyssi.discover.pairing", "Pairing"),
              subtitle: t("galaxyssi.discover.pairing.subtitle", "Scan QR codes and connect GalaxySSI Desktop"),
              systemImage: "qrcode.viewfinder",
              tint: .galaxySSIAccent
            ) {
              PairingView()
            }
            if GalaxySSIRuntimePlaintextProtection.sensitiveDiagnosticsEnabled {
              GalaxySSIAndroidMenuLink(
                title: t("galaxyssi.agent_memory.telemetry_title", "Agent Memory"),
                subtitle: t("galaxyssi.agent_memory.telemetry_subtitle", "iOS resident memory sampled across active Agent tasks"),
                systemImage: "memorychip",
                tint: .purple
              ) {
                GalaxySSIAgentMemoryTelemetryView()
              }
            }
            GalaxySSIAndroidMenuLink(
              title: t("galaxyssi.discover.voice", "Voice"),
              subtitle: t("galaxyssi.discover.voice.subtitle", "Wake, transcription and local voice models"),
              systemImage: "waveform",
              tint: .galaxySSIInsightText
            ) {
              GalaxySSIVoiceControlCenterView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_general_page_title", "General"),
              subtitle: t("galaxyssi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"),
              systemImage: "gearshape",
              tint: .galaxySSIInsightText
            ) {
              GalaxySSIGeneralControlCenterView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_runtime_title", "On-device Linux Runtime"),
              subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
              systemImage: "terminal",
              tint: .teal
            ) {
              GalaxySSIOnDeviceRuntimeView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_nodes_title", "Agents, Models & Nodes"),
              subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
              systemImage: "link.circle",
              tint: .galaxySSIInsightText
            ) {
              GalaxySSIAgentsModelsNodesView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_smart_spaces_title", "Smart Spaces"),
              subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
              systemImage: "house",
              tint: .purple
            ) {
              GalaxySSISmartSpacesView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_resource_routing_title", "Models & Resource Routing"),
              subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
              systemImage: "point.3.connected.trianglepath.dotted",
              tint: .blue
            ) {
              GalaxySSIResourceRoutingView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("cc_phone_title", "Phone Capabilities"),
              subtitle: phoneCapabilitiesSummary,
              systemImage: "iphone",
              tint: nativeToolSummary.available > 0 ? .galaxySSIAccent : .orange
            ) {
              GalaxySSIPhoneCapabilitiesView()
            }
            GalaxySSIAndroidMenuLink(
              title: t("galaxyssi.discover.model_planner", "Model Planner"),
              subtitle: t("galaxyssi.discover.planner.subtitle", "Agent planning, budget and model routing"),
              systemImage: "slider.horizontal.3",
              tint: .galaxySSIInsightText
            ) {
              AgentModelPlannerSettingsView()
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
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
    systemStatusNeedsAttention ? .orange : .galaxySSIAccent
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
      GalaxySSILinkTransportDiagnostics.snapshot().failureCount == 0
  }

  private var systemStatusAvailableResourceCount: Int {
    store.cloudModelContacts.count +
      store.serverLinks.filter(\.paired).count +
      store.customDeviceConnectors.filter(\.enabled).count
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
