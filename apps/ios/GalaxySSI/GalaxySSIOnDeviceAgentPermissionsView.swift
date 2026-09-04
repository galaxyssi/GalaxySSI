import AVFoundation
import CoreLocation
import SwiftUI
import UIKit
import UserNotifications

struct OnDeviceAgentPermissionsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var cameraStatus = ""
  @State private var microphoneStatus = ""
  @State private var locationStatus = ""
  @State private var notificationStatus = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.on_device_agent.title", "On-device Agent Permissions"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          OnDeviceAgentHeroView(
            title: t("galaxyssi.on_device_agent.hero_title", "On-device Agent"),
            subtitle: t("galaxyssi.on_device_agent.hero_subtitle", "Manage perception, voice, and automation permissions"),
            systemImage: "cpu",
            tint: .blue,
            badge: store.agentSafetySettings.executionPaused
              ? t("galaxyssi.on_device_agent.status_paused", "Paused")
              : t("galaxyssi.on_device_agent.status_running", "Running")
          )
          sectionTitle(t("galaxyssi.on_device_agent.section_execution", "Execution"))
          VStack(spacing: 8) {
            OnDeviceAgentActionRow(
              title: t("galaxyssi.on_device_agent.permission_mode", "Execution Mode"),
              subtitle: t(
                "galaxyssi.on_device_agent.permission_mode_subtitle",
                "Tap to switch observation, suggestion, confirmation, or low-risk automation"
              ),
              systemImage: "shield",
              tint: .blue,
              badge: t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle)
            ) {
              cyclePermissionMode()
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.high_risk_guard", "High-risk Guard"),
              subtitle: t(
                "galaxyssi.on_device_agent.high_risk_guard_subtitle",
                "Always protect payments, deletion, privacy sharing, installation, and security changes"
              ),
              systemImage: "exclamationmark.shield",
              tint: .orange,
              isOn: store.agentSafetySettings.highRiskGuard
            ) {
              store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.memory_capture", "Memory Capture"),
              subtitle: t(
                "galaxyssi.on_device_agent.memory_capture_subtitle",
                "Allow explicit notes to update encrypted long-term memory; task context stays session-scoped"
              ),
              systemImage: "brain.head.profile",
              tint: .purple,
              isOn: store.agentSafetySettings.memoryCapture
            ) {
              store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.execution_pause", "Pause All Execution"),
              subtitle: t(
                "galaxyssi.on_device_agent.execution_pause_subtitle",
                "Immediately stop automatic execution while keeping observation available"
              ),
              systemImage: "pause.circle",
              tint: .red,
              isOn: store.agentSafetySettings.executionPaused
            ) {
              store.updateAgentSafetySettings { $0.executionPaused.toggle() }
            }
          }
          sectionTitle(t("galaxyssi.on_device_agent.section_intelligence", "Planning Intelligence"))
          VStack(spacing: 8) {
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.model_planner", "Model-driven Planning"),
              subtitle: t(
                "galaxyssi.on_device_agent.model_planner_subtitle",
                "Let a configured cloud model propose ActionPlans; iOS validates every action locally"
              ),
              systemImage: "wand.and.stars",
              tint: .blue,
              isOn: store.modelPlannerSettings.enabled
            ) {
              store.updateModelPlannerSettings { $0.enabled.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.model_screen_text", "Share Screen Text for Planning"),
              subtitle: t(
                "galaxyssi.on_device_agent.model_screen_text_subtitle",
                "Include non-sensitive visible text and element labels in model planning requests"
              ),
              systemImage: "text.viewfinder",
              tint: .teal,
              isOn: store.modelPlannerSettings.shareScreenText
            ) {
              store.updateModelPlannerSettings { $0.shareScreenText.toggle() }
            }
            OnDeviceAgentNavigationRow(
              title: t("galaxyssi.on_device_agent.model_source", "Planning Model"),
              subtitle: t(
                "galaxyssi.on_device_agent.model_source_subtitle",
                "Choose the configured cloud model that proposes ActionPlans"
              ),
              systemImage: "link",
              tint: .blue,
              badge: plannerSourceLabel
            ) {
              AgentModelPlannerSettingsView()
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.dynamic_replanning", "Dynamic Replanning"),
              subtitle: t(
                "galaxyssi.on_device_agent.dynamic_replanning_subtitle",
                "Observe after each action and rebuild remaining steps when the screen changes or execution fails"
              ),
              systemImage: "arrow.triangle.2.circlepath",
              tint: .galaxySSIAccent,
              isOn: store.modelPlannerSettings.dynamicReplanning
            ) {
              store.updateModelPlannerSettings { $0.dynamicReplanning.toggle() }
            }
            OnDeviceAgentActionRow(
              title: t("galaxyssi.on_device_agent.max_replans", "Maximum Replans"),
              subtitle: t(
                "galaxyssi.on_device_agent.max_replans_subtitle",
                "Bound autonomous recovery to 1, 3, or 5 plan revisions per task"
              ),
              systemImage: "arrow.clockwise",
              tint: .galaxySSIAccent,
              badge: "\(store.modelPlannerSettings.maxReplans)"
            ) {
              cycleModelPlannerInt(\.maxReplans, values: [1, 3, 5])
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.multi_agent_coordination", "Multi-Agent Coordination"),
              subtitle: t(
                "galaxyssi.on_device_agent.multi_agent_coordination_subtitle",
                "Allow validated task graphs to call multiple paired Agents with explicit dependencies"
              ),
              systemImage: "link",
              tint: .purple,
              isOn: store.modelPlannerSettings.multiAgentCoordination
            ) {
              store.updateModelPlannerSettings { $0.multiAgentCoordination.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.share_agent_outputs", "Share Agent Outputs with Planner"),
              subtitle: t(
                "galaxyssi.on_device_agent.share_agent_outputs_subtitle",
                "Send redacted Agent results to the selected planning model for the next decision"
              ),
              systemImage: "lock.shield",
              tint: .orange,
              isOn: store.modelPlannerSettings.shareAgentOutputsWithPlanner
            ) {
              store.updateModelPlannerSettings { $0.shareAgentOutputsWithPlanner.toggle() }
            }
            OnDeviceAgentActionRow(
              title: t("galaxyssi.on_device_agent.max_agent_hops", "Maximum Agent Hops"),
              subtitle: t(
                "galaxyssi.on_device_agent.max_agent_hops_subtitle",
                "Limit each task graph to 2, 4, or 8 dependency levels"
              ),
              systemImage: "arrow.triangle.branch",
              tint: .purple,
              badge: "\(store.modelPlannerSettings.maxAgentHops)"
            ) {
              cycleModelPlannerInt(\.maxAgentHops, values: [2, 4, 8])
            }
            OnDeviceAgentActionRow(
              title: t("galaxyssi.on_device_agent.max_tool_calls", "Maximum Tool Calls"),
              subtitle: t(
                "galaxyssi.on_device_agent.max_tool_calls_subtitle",
                "Stop repeated or runaway autonomous execution after 8, 16, or 32 calls"
              ),
              systemImage: "wrench.and.screwdriver",
              tint: .orange,
              badge: "\(store.modelPlannerSettings.maxToolCalls)"
            ) {
              cycleModelPlannerInt(\.maxToolCalls, values: [8, 16, 32])
            }
            OnDeviceAgentActionRow(
              title: t("galaxyssi.on_device_agent.model_max_actions", "Maximum Planned Actions"),
              subtitle: t(
                "galaxyssi.on_device_agent.model_max_actions_subtitle",
                "Limit each model-generated plan to 4, 8, or 12 validated actions"
              ),
              systemImage: "list.number",
              tint: .blue,
              badge: "\(store.modelPlannerSettings.maxActions)"
            ) {
              cycleModelPlannerInt(\.maxActions, values: [4, 8, 12])
            }
          }
          sectionTitle(t("galaxyssi.on_device_agent.section_capabilities", "Capability Access"))
          VStack(spacing: 8) {
            OnDeviceAgentNavigationRow(
              title: t("galaxyssi.native_tool_catalog.title", "Native Tools"),
              subtitle: t(
                "galaxyssi.native_tool_catalog.hero_subtitle",
                "Review iOS tool availability, risk, runtime scope, permissions, and consent boundaries"
              ),
              systemImage: "wrench.and.screwdriver",
              tint: .blue,
              badge: String(
                format: t("galaxyssi.native_tool_catalog.badge", "%d tools"),
                AgentPhoneNativeToolCatalog.descriptors().count
              )
            ) {
              GalaxySSINativeToolCatalogView()
            }
            OnDeviceAgentNavigationRow(
              title: t("agent_app_adapters_title", "Specialized App Adapters"),
              subtitle: t(
                "agent_app_adapters_subtitle",
                "Grounded workflows for communication, browser, and document apps"
              ),
              systemImage: "rectangle.3.group",
              tint: .galaxySSIAccent,
              badge: String(
                format: t("agent_app_adapters_count", "%d adapters"),
                GalaxySSIAppAdapterCatalog.adapterCount
              )
            ) {
              GalaxySSIAppAdaptersView()
            }
            OnDeviceAgentNavigationRow(
              title: t("galaxyssi.on_device_agent.visual_model", "On-device Visual Model"),
              subtitle: t(
                "galaxyssi.on_device_agent.visual_model_subtitle",
                "Fuse offline OCR geometry with the UI tree for grounded complex-page actions"
              ),
              systemImage: "viewfinder",
              tint: .teal,
              badge: store.agentSafetySettings.screenObservationAllowed
                ? t("galaxyssi.status.ready", "Ready")
                : t("galaxyssi.permission.needs_setup", "Needs setup")
            ) {
              GalaxySSIAgentScreenUnderstandingView()
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.allow_screen_observation", "Screen Understanding"),
              subtitle: t(
                "galaxyssi.on_device_agent.allow_screen_observation_subtitle",
                "Allow the Agent runtime to capture structured screen context"
              ),
              systemImage: "text.viewfinder",
              tint: .teal,
              isOn: store.agentSafetySettings.screenObservationAllowed
            ) {
              store.updateAgentSafetySettings { $0.screenObservationAllowed.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.allow_local_actions", "On-device Actions"),
              subtitle: t(
                "galaxyssi.on_device_agent.allow_local_actions_subtitle",
                "Allow confirmed taps, text input, navigation, intents, and system actions"
              ),
              systemImage: "hand.tap",
              tint: .blue,
              isOn: store.agentSafetySettings.localActionsAllowed
            ) {
              store.updateAgentSafetySettings { $0.localActionsAllowed.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.allow_connectors", "Agents and Models"),
              subtitle: t(
                "galaxyssi.on_device_agent.allow_connectors_subtitle",
                "Allow tasks to be routed to trusted local, desktop, and cloud connectors"
              ),
              systemImage: "link",
              tint: .purple,
              isOn: store.agentSafetySettings.connectorCallsAllowed
            ) {
              store.updateAgentSafetySettings { $0.connectorCallsAllowed.toggle() }
            }
            OnDeviceAgentToggleRow(
              title: t("galaxyssi.on_device_agent.allow_devices", "Smart Devices"),
              subtitle: t(
                "galaxyssi.on_device_agent.allow_devices_subtitle",
                "Allow confirmed Home Assistant and trusted device control"
              ),
              systemImage: "house",
              tint: .galaxySSIAccent,
              isOn: store.agentSafetySettings.deviceControlAllowed
            ) {
              store.updateAgentSafetySettings { $0.deviceControlAllowed.toggle() }
            }
          }
          sectionTitle(t("galaxyssi.on_device_agent.section_permissions", "Permissions"))
          VStack(spacing: 8) {
            OnDeviceAgentStatusRow(
              title: t("galaxyssi.on_device_agent.screen_access", "Screen Access"),
              subtitle: t(
                "galaxyssi.on_device_agent.screen_access_subtitle",
                "Read screen structure and perform confirmed local actions"
              ),
              systemImage: "rectangle.on.rectangle",
              tint: .blue,
              badge: t("galaxyssi.status.protected", "Protected")
            )
            OnDeviceAgentPermissionRow(
              title: t("galaxyssi.on_device_agent.microphone", "Microphone"),
              subtitle: t("galaxyssi.on_device_agent.microphone_subtitle", "Voice input and hold-to-talk"),
              systemImage: "mic",
              tint: .galaxySSIAccent,
              badge: microphoneStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
            ) {
              requestMicrophone()
            }
            OnDeviceAgentPermissionRow(
              title: t("galaxyssi.on_device_agent.camera", "Camera"),
              subtitle: t("galaxyssi.on_device_agent.camera_subtitle", "QR scanning and visual recognition"),
              systemImage: "camera",
              tint: .teal,
              badge: cameraStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
            ) {
              requestCamera()
            }
            OnDeviceAgentPermissionRow(
              title: t("galaxyssi.on_device_agent.location", "Location"),
              subtitle: t("galaxyssi.on_device_agent.location_subtitle", "Can be disabled for automation scenarios"),
              systemImage: "location",
              tint: .purple,
              badge: locationStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
            ) {
              openAppSettings()
            }
            OnDeviceAgentPermissionRow(
              title: t("galaxyssi.on_device_agent.notifications", "Notifications"),
              subtitle: t("galaxyssi.on_device_agent.notifications_subtitle", "Background message alerts and security prompts"),
              systemImage: "bell.badge",
              tint: .orange,
              badge: notificationStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
            ) {
              requestNotifications()
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshPermissionStatuses)
  }

  private var plannerSourceLabel: String {
    let selected = store.modelPlannerSettings.cloudContactId
    guard !selected.isEmpty,
          let contact = store.cloudModelContacts.first(where: { $0.id == selected }) else {
      return t("galaxyssi.on_device_agent.model_source_automatic", "Automatic")
    }
    return contact.displayName
  }

  private func cyclePermissionMode() {
    let modes = AgentPermissionMode.allCases
    guard let index = modes.firstIndex(of: store.agentSafetySettings.permissionMode) else {
      store.updateAgentSafetySettings { $0.permissionMode = .askBeforeAction }
      return
    }
    store.updateAgentSafetySettings { $0.permissionMode = modes[(index + 1) % modes.count] }
  }

  private func cycleModelPlannerInt(
    _ keyPath: WritableKeyPath<AgentModelPlannerSettings, Int>,
    values: [Int]
  ) {
    guard !values.isEmpty else { return }
    let current = store.modelPlannerSettings[keyPath: keyPath]
    let next = values.first { $0 > current } ?? values[0]
    store.updateModelPlannerSettings { $0[keyPath: keyPath] = next }
  }

  private func refreshPermissionStatuses() {
    cameraStatus = authorizationLabel(AVCaptureDevice.authorizationStatus(for: .video))
    microphoneStatus = recordPermissionLabel(AVAudioSession.sharedInstance().recordPermission)
    locationStatus = locationAuthorizationLabel(CLLocationManager.authorizationStatus())
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationStatus = notificationAuthorizationLabel(settings.authorizationStatus)
      }
    }
  }

  private func requestCamera() {
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async {
        refreshPermissionStatuses()
      }
    }
  }

  private func requestMicrophone() {
    AVAudioSession.sharedInstance().requestRecordPermission { _ in
      DispatchQueue.main.async {
        refreshPermissionStatuses()
      }
    }
  }

  private func requestNotifications() {
    Task {
      _ = await NotificationService.requestAuthorization()
      refreshPermissionStatuses()
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func authorizationLabel(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    case .denied, .restricted:
      return t("galaxyssi.status.protected", "Protected")
    @unknown default:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    }
  }

  private func recordPermissionLabel(_ permission: AVAudioSession.RecordPermission) -> String {
    switch permission {
    case .granted:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .undetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    case .denied:
      return t("galaxyssi.status.protected", "Protected")
    @unknown default:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    }
  }

  private func locationAuthorizationLabel(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return t("galaxyssi.permission.while_using", "While in use")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    case .denied, .restricted:
      return t("galaxyssi.status.protected", "Protected")
    @unknown default:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    }
  }

  private func notificationAuthorizationLabel(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    case .denied:
      return t("galaxyssi.status.protected", "Protected")
    @unknown default:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct OnDeviceAgentHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct OnDeviceAgentNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      OnDeviceAgentRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct OnDeviceAgentToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var isOn: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      OnDeviceAgentRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: isOn ? "ON" : "OFF",
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct OnDeviceAgentActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      OnDeviceAgentRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct OnDeviceAgentPermissionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      OnDeviceAgentRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct OnDeviceAgentStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    OnDeviceAgentRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct OnDeviceAgentRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
