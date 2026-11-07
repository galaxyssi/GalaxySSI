import SwiftUI
import UIKit
import UserNotifications

struct GalaxySSIContactReminderOverlay: ViewModifier {
  @Environment(\.scenePhase) private var phase
  @Environment(\.dynamicTypeSize) private var textSize
  @ObservedObject var coordinator: MessageCoordinator
  @ObservedObject var store: GalaxySSIStore
  @State private var collapsed = Set<String>()
  @State private var preferredID: String?
  @State private var settingsPresented = false

  private var active: GalaxySSIContactReminder? {
    guard phase == .active, coordinator.contactReminderReceivingEnabled,
          !coordinator.contactReminderAlert.mustBeQuiet else { return nil }
    let now = AgentControlPlaneClock.nowMillis()
    let rows = coordinator.contactReminders.filter {
      GalaxySSIContactReminderPresentationPolicy.canShowPanel($0, explicitlyOpened: $0.id == preferredID, now: now) &&
        !collapsed.contains($0.id) &&
        store.contact(id: $0.peerID)?.isCommunicable == true
    }
    return rows.first { $0.id == preferredID } ?? rows.first
  }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let reminder = active {
          panel(reminder)
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
      }
      .onAppear(perform: consumeNotificationAction)
      .sheet(isPresented: $settingsPresented) {
        GalaxySSIContactReminderSettingsView(coordinator: coordinator, t: t)
      }
      .onChange(of: phase) { value in
        if value == .active {
          coordinator.restoreContactReminders()
          consumeNotificationAction()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIContactReminderNotification.actionNotification)) { _ in
        consumeNotificationAction()
      }
      .onChange(of: store.profile.identityFingerprint) { _ in
        collapsed.removeAll()
        preferredID = nil
        settingsPresented = false
        coordinator.contactReminderAlert.stop()
        coordinator.restoreContactReminders()
      }
  }

  private func panel(_ reminder: GalaxySSIContactReminder) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(t("galaxyssi.contact_reminder.title", "Contact reminder"), systemImage: "bell.badge")
          .font(.headline)
        Spacer(minLength: 8)
        Button {
          settingsPresented = true
        } label: {
          Image(systemName: "gearshape").frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("galaxyssi.contact_reminder.settings", "Reminder settings"))
        .accessibilityIdentifier("ios.contact-reminder.settings")
      }
      Text(store.contact(id: reminder.peerID)?.displayName ?? "")
        .font(.subheadline)
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(2)
      if textSize.isAccessibilitySize {
        VStack(spacing: 6) { actions(reminder) }
      } else {
        HStack(spacing: 8) { actions(reminder) }
      }
    }
    .frame(maxWidth: 460, alignment: .leading)
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.galaxySSISeparator))
    .accessibilityIdentifier("ios.contact-reminder.panel")
    .accessibilityAction(.escape) { collapse(reminder) }
    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
      if value.translation.height < -32 && abs(value.translation.height) > abs(value.translation.width) {
        collapse(reminder)
      }
    })
  }

  @ViewBuilder
  private func actions(_ reminder: GalaxySSIContactReminder) -> some View {
    action(reminder, .muted, "mute", "Mute", icon: "speaker.slash")
      .disabled(reminder.status == .muted)
    action(reminder, .dismissed, "ignore", "Ignore", icon: "xmark")
    action(reminder, .acknowledged, "got_it", "Got it", icon: "checkmark")
  }

  private func action(_ reminder: GalaxySSIContactReminder, _ action: GalaxySSIContactReminderAction,
                      _ key: String, _ fallback: String, icon: String) -> some View {
    Button {
      coordinator.actOnContactReminder(id: reminder.id, action: action)
    } label: {
      Label(t("galaxyssi.contact_reminder." + key, fallback), systemImage: icon)
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 44)
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("ios.contact-reminder." + key)
  }

  private func collapse(_ reminder: GalaxySSIContactReminder) {
    if reminder.status == .muted || coordinator.actOnContactReminder(id: reminder.id, action: .muted) {
      collapsed.insert(reminder.id)
    }
  }

  private func consumeNotificationAction() {
    guard phase == .active,
          let action = UserDefaults.standard.dictionary(forKey: GalaxySSIContactReminderNotification.pendingKey),
          let id = action["id"] as? String, let command = action["action"] as? String else { return }
    UserDefaults.standard.removeObject(forKey: GalaxySSIContactReminderNotification.pendingKey)
    coordinator.restoreContactReminders()
    let now = AgentControlPlaneClock.nowMillis()
    guard coordinator.contactReminderReceivingEnabled,
          coordinator.contactReminders.contains(where: { $0.id == id && !$0.outgoing &&
            !$0.status.terminal && $0.expiresAt > now && store.contact(id: $0.peerID)?.isCommunicable == true }) else { return }
    if command == UNNotificationDefaultActionIdentifier {
      collapsed.remove(id)
      preferredID = id
    } else if let event = GalaxySSIContactReminderAction(rawValue: command) {
      coordinator.actOnContactReminder(id: id, action: event)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: store.languagePolicy.interfaceLanguage)
  }
}

struct GalaxySSIContactReminderSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var phase
  @Environment(\.openURL) private var openURL
  @ObservedObject var coordinator: MessageCoordinator
  var t: (String, String) -> String
  @State private var receiving = true
  @State private var silentModeSound = true
  @State private var backgroundNotifications = true
  @State private var notificationSettings: UNNotificationSettings?
  @State private var requestingAuthorization = false

  var body: some View {
    NavigationView {
      Form {
        Toggle(t("galaxyssi.contact_reminder.enable", "Receive contact reminders"), isOn: $receiving)
        Toggle(t("galaxyssi.contact_reminder.silent_sound", "Play in silent mode while in the app"), isOn: $silentModeSound)
          .disabled(!receiving)
        Toggle(t("galaxyssi.contact_reminder.background_notifications", "Background notifications"),
          isOn: $backgroundNotifications)
          .disabled(!receiving)
        Section(header: Text(t("galaxyssi.contact_reminder.system_notifications", "System notifications"))) {
          if let notificationSettings {
            permissionRow(t("galaxyssi.settings.notifications", "Notifications"),
              allowed: GalaxySSIContactReminderPresentationPolicy.canPost(notificationSettings.authorizationStatus),
              pending: notificationSettings.authorizationStatus == .notDetermined)
            permissionRow(t("galaxyssi.contact_reminder.lock_screen", "Lock screen"),
              allowed: notificationSettings.lockScreenSetting == .enabled)
            if notificationSettings.authorizationStatus == .notDetermined {
              Button {
                Task { await requestNotifications() }
              } label: {
                Label(t("galaxyssi.settings.enable_notifications", "Enable notifications"), systemImage: "bell")
              }
              .disabled(requestingAuthorization)
            }
          }
          Button(action: openSystemSettings) {
            Label(t("galaxyssi.permission.fix.open_notification_settings", "Open notification settings"),
              systemImage: "gearshape")
          }
        }
      }
      .navigationTitle(t("galaxyssi.contact_reminder.settings", "Reminder settings"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.common.done", "Done")) { dismiss() }
        }
      }
      .onAppear {
        receiving = coordinator.contactReminderReceivingEnabled
        silentModeSound = coordinator.contactReminderSoundInSilentMode
        backgroundNotifications = coordinator.contactReminderBackgroundNotifications
      }
      .onChange(of: receiving) { coordinator.contactReminderReceivingEnabled = $0 }
      .onChange(of: silentModeSound) { coordinator.contactReminderSoundInSilentMode = $0 }
      .onChange(of: backgroundNotifications) { coordinator.contactReminderBackgroundNotifications = $0 }
      .task(id: phase) {
        if phase == .active { await reloadNotificationSettings() }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func permissionRow(_ title: String, allowed: Bool, pending: Bool = false) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(pending ? t("galaxyssi.contact_reminder.not_requested", "Not requested") :
        allowed ? t("galaxyssi.permission.allowed", "Allowed") : t("galaxyssi.permission.denied", "Denied"))
        .foregroundColor(.secondary)
    }
  }

  private func reloadNotificationSettings() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    if !Task.isCancelled { notificationSettings = settings }
  }

  private func requestNotifications() async {
    guard !requestingAuthorization else { return }
    requestingAuthorization = true
    defer { requestingAuthorization = false }
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    await reloadNotificationSettings()
  }

  private func openSystemSettings() {
    let value: String
    if #available(iOS 15.4, *) { value = UIApplication.openNotificationSettingsURLString }
    else { value = UIApplication.openSettingsURLString }
    if let url = URL(string: value) { openURL(url) }
  }
}
