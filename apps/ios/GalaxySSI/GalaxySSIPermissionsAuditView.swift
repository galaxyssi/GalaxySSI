import AVFoundation
import SwiftUI
import UIKit
import UserNotifications

struct GalaxySSIPermissionsAuditView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
  @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var auditCount = 0

  private var screenExecutorReady: Bool {
    store.agentSafetySettings.screenObservationAllowed
  }

  private var grantedCount: Int {
    [
      screenExecutorReady,
      notificationGranted,
      microphonePermission == .granted,
      cameraStatus == .authorized
    ].filter { $0 }.count
  }

  private var notificationGranted: Bool {
    switch notificationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .notDetermined, .denied:
      return false
    @unknown default:
      return false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_permissions_title", "Permissions & Audit"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_permissions_title", "Permissions & Audit"),
            subtitle: String(format: t("galaxyssi.permissions_summary_ios", "%d of %d required iOS permissions ready"), grantedCount, 4),
            systemImage: "checkmark.shield",
            tint: grantedCount == 4 ? .galaxySSIAccent : .orange,
            badge: t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle)
          )
          GalaxySSIPermissionsMetricStrip(metrics: [
            GalaxySSIPermissionsMetric(value: "\(grantedCount)/4", label: t("galaxyssi.permissions_ios_section", "iOS Permissions"), tint: grantedCount == 4 ? .galaxySSIAccent : .orange),
            GalaxySSIPermissionsMetric(value: "\(auditCount)", label: t("feature_audit_log", "Audit Log"), tint: .blue),
            GalaxySSIPermissionsMetric(value: t("galaxyssi.permissions.secure_status", "Secure"), label: t("cc_metric_security", "Security"), tint: .galaxySSIAccent)
          ])
          permissionsSection
          auditSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
  }

  private var permissionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.permissions_ios_section", "iOS Permissions"))
      GalaxySSISecurityActionRow(
        title: t("cc_accessibility_title", "Accessibility"),
        subtitle: t("cc_accessibility_subtitle", "Interface understanding and controlled execution"),
        systemImage: "hand.tap",
        tint: screenExecutorReady ? .galaxySSIAccent : .orange,
        badge: screenExecutorReady ? t("galaxyssi.permission.allowed", "Allowed") : t("galaxyssi.permission.needs_setup", "Needs setup")
      ) {
        openAppSettings()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_notification_access_title", "Notification Access"),
        subtitle: t("cc_notification_access_subtitle", "Read task-related notifications and reply after confirmation"),
        systemImage: "bell.badge",
        tint: notificationGranted ? .galaxySSIAccent : .orange,
        badge: notificationLabel
      ) {
        requestNotifications()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_microphone_permission_title", "Microphone"),
        subtitle: t("cc_microphone_permission_subtitle", "Voice input, wake-up, and local ASR"),
        systemImage: "mic",
        tint: microphonePermission == .granted ? .galaxySSIAccent : .orange,
        badge: microphoneLabel
      ) {
        requestMicrophone()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_camera_permission_title", "Camera"),
        subtitle: t("cc_camera_permission_subtitle", "Capture, QR pairing, and visual tasks"),
        systemImage: "camera",
        tint: cameraStatus == .authorized ? .galaxySSIAccent : .orange,
        badge: cameraLabel
      ) {
        requestCamera()
      }
    }
  }

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("feature_audit_log", "Audit Log"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_audit_operations_title", "Audit Operations"),
        subtitle: t("cc_audit_operations_subtitle", "Review native tool execution and recent Agent tasks on this phone"),
        systemImage: "clock.arrow.circlepath",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        GalaxySSIAgentAuditOperationsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("advanced_agent_permission_audit", "Agent Permission Audit"),
        subtitle: t("advanced_agent_permission_audit_subtitle", "Check native tool availability, permissions, and consent boundaries"),
        systemImage: "checkmark.shield",
        tint: .orange,
        badge: t("common_view", "View")
      ) {
        GalaxySSIAgentPermissionAuditView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t("galaxyssi.settings.model_data_sharing.subtitle", "Review metadata-only disclosure events and destination blocks"),
        systemImage: "lock.doc",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        AgentDataDisclosureDashboardView()
      }
    }
  }

  private var notificationLabel: String {
    switch notificationStatus {
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

  private var microphoneLabel: String {
    switch microphonePermission {
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

  private var cameraLabel: String {
    switch cameraStatus {
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

  private func refresh() {
    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    microphonePermission = AVAudioSession.sharedInstance().recordPermission
    auditCount = AgentNativeToolDefaultStores.makePersistentStores().auditStore
      .list(limit: 100, toolId: "", status: nil)
      .count
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationStatus = settings.authorizationStatus
      }
    }
  }

  private func requestNotifications() {
    Task {
      _ = await NotificationService.requestAuthorization()
      refresh()
    }
  }

  private func requestMicrophone() {
    AVAudioSession.sharedInstance().requestRecordPermission { _ in
      DispatchQueue.main.async {
        refresh()
      }
    }
  }

  private func requestCamera() {
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async {
        refresh()
      }
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIPermissionsMetric: Identifiable {
  var value: String
  var label: String
  var tint: Color

  var id: String { label }
}

private struct GalaxySSIPermissionsMetricStrip: View {
  var metrics: [GalaxySSIPermissionsMetric]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(metrics) { metric in
        VStack(alignment: .leading, spacing: 4) {
          Text(metric.value)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(metric.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(metric.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }
}
