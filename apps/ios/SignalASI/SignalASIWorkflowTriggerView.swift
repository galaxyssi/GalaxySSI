import SwiftUI

struct SignalASIWorkflowTriggerEditorView: View {
  @Environment(\.presentationMode) private var presentationMode
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @ObservedObject private var triggerStore = UserDefaultsAgentWorkflowTriggerStore.shared
  @ObservedObject private var workflowStore = UserDefaultsAgentWorkflowStore.shared
  @State private var workflowId: String
  @State private var kind: AgentWorkflowTriggerKind
  @State private var cooldownMinutes: String
  @State private var enabled: Bool
  @State private var errorMessage = ""
  private let original: AgentWorkflowTrigger?

  init(trigger: AgentWorkflowTrigger? = nil) {
    let firstWorkflow = UserDefaultsAgentWorkflowStore.shared.list().first
    _workflowId = State(initialValue: trigger?.workflowId ?? firstWorkflow?.id ?? "")
    _kind = State(initialValue: trigger?.kind ?? .powerConnected)
    _cooldownMinutes = State(initialValue: "\(trigger?.cooldownMinutes ?? 5)")
    _enabled = State(initialValue: trigger?.enabled ?? true)
    original = trigger
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.workflow_trigger.title", "Workflow Trigger"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear.frame(width: 22) }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AutomationHeroCard(
            title: t("signalasi.workflow_trigger.hero_title", "Device event trigger"),
            subtitle: t("signalasi.workflow_trigger.hero_subtitle", "Run a saved workflow when iOS reports a device event"),
            icon: "bolt",
            tint: .orange,
            metrics: [
              AutomationMetric(value: "iOS 15+", label: t("signalasi.workflow.platform", "Platform")),
              AutomationMetric(value: "15%", label: t("signalasi.workflow_trigger.battery_limit", "Low battery"))
            ]
          )
          if workflowStore.list().isEmpty {
            AutomationInfoRow(
              title: t("signalasi.workflow_trigger.no_workflows", "No saved workflows"),
              subtitle: t("signalasi.workflow_trigger.create_workflow", "Create a workflow before adding a trigger"),
              icon: "exclamationmark.circle",
              tint: .orange,
              badge: ""
            )
          } else {
            AutomationPickerRow(
              title: t("signalasi.workflow_trigger.workflow", "Workflow"),
              icon: "square.stack.3d.up",
              tint: .signalASIAccent,
              selection: $workflowId,
              values: workflowStore.list().map(\.id),
              label: { id in workflowStore.findById(id)?.name ?? id }
            )
            AutomationPickerRow(
              title: t("signalasi.workflow_trigger.event", "Event"),
              icon: "bolt",
              tint: .orange,
              selection: $kind,
              values: [.powerConnected, .batteryLow],
              label: triggerLabel
            )
            AutomationTextInputRow(
              title: t("signalasi.workflow_trigger.cooldown", "Cooldown minutes"),
              subtitle: t("signalasi.workflow_trigger.cooldown_hint", "Avoid repeated runs for the same event"),
              icon: "timer",
              tint: .blue,
              text: $cooldownMinutes,
              keyboardType: .numberPad
            )
            AutomationSwitchRow(
              title: t("signalasi.workflow_trigger.enabled", "Enabled"),
              subtitle: t("signalasi.workflow_trigger.enabled_subtitle", "Listen for this event while SignalASI is running"),
              icon: "power",
              tint: .signalASIAccent,
              isOn: $enabled
            )
            AutomationActionRow(
              title: t("signalasi.common.save", "Save"),
              subtitle: t("signalasi.workflow_trigger.save_subtitle", "Store this trigger on the device"),
              icon: "square.and.arrow.down",
              tint: .signalASIAccent,
              badge: t("signalasi.common.save", "Save"),
              action: save
            )
            if original != nil {
              AutomationActionRow(
                title: t("signalasi.common.delete", "Delete"),
                subtitle: t("signalasi.workflow_trigger.delete_subtitle", "Remove this device event trigger"),
                icon: "trash",
                tint: .red,
                badge: t("signalasi.common.delete", "Delete"),
                action: delete
              )
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("signalasi.workflow_trigger.invalid", "Invalid workflow trigger"), isPresented: Binding(
      get: { !errorMessage.isEmpty },
      set: { if !$0 { errorMessage = "" } }
    )) {
      Button(t("signalasi.common.ok", "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func save() {
    guard let workflow = workflowStore.findById(workflowId) else {
      errorMessage = t("signalasi.workflow_trigger.workflow_required", "Select a saved workflow")
      return
    }
    do {
      let trigger = try AgentWorkflowTrigger(
        id: original?.id ?? UUID().uuidString.lowercased(),
        workflowId: workflow.id,
        workflowName: workflow.name,
        kind: kind,
        enabled: enabled,
        cooldownMinutes: Int(cooldownMinutes) ?? 5,
        lastTriggeredAtMillis: original?.lastTriggeredAtMillis ?? 0,
        createdAtMillis: original?.createdAtMillis ?? Int64(Date().timeIntervalSince1970 * 1_000),
        conditions: original?.conditions ?? []
      )
      _ = try triggerStore.upsert(trigger)
      presentationMode.wrappedValue.dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete() {
    guard let original else { return }
    _ = triggerStore.delete(id: original.id)
    presentationMode.wrappedValue.dismiss()
  }

  private func triggerLabel(_ kind: AgentWorkflowTriggerKind) -> String {
    switch kind {
    case .powerConnected:
      return t("signalasi.workflow_trigger.power_connected", "Power connected")
    case .batteryLow:
      return t("signalasi.workflow_trigger.battery_low", "Battery low")
    case .notificationPackage, .notificationText:
      return kind.rawValue
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIWorkflowTriggerRow: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  let trigger: AgentWorkflowTrigger

  var body: some View {
    AutomationTaskRow(
      title: trigger.workflowName,
      subtitle: [eventLabel, cooldownLabel, conditionLabel, statusLabel]
        .compactMap { $0 }
        .joined(separator: "\n"),
      icon: "bolt",
      tint: trigger.enabled ? .orange : .signalASITextSecondary,
      badge: trigger.enabled ? t("signalasi.common.on", "On") : t("signalasi.common.off", "Off"),
      badgeTint: trigger.enabled ? .signalASIAccent : .signalASITextSecondary
    )
  }

  private var eventLabel: String {
    switch trigger.kind {
    case .powerConnected:
      return t("signalasi.workflow_trigger.power_connected", "Power connected")
    case .batteryLow:
      return t("signalasi.workflow_trigger.battery_low", "Battery low")
    case .notificationPackage, .notificationText:
      return trigger.kind.rawValue
    }
  }

  private var cooldownLabel: String {
    String(format: t("signalasi.workflow_trigger.cooldown_value", "Cooldown: %d min"), trigger.cooldownMinutes)
  }

  private var conditionLabel: String? {
    guard !trigger.conditions.isEmpty else { return nil }
    return String(format: t("signalasi.workflow_trigger.condition_count", "%d additional conditions"), trigger.conditions.count)
  }

  private var statusLabel: String {
    trigger.lastTriggeredAtMillis > 0
      ? t("signalasi.workflow_trigger.last_triggered", "Triggered before")
      : t("signalasi.workflow_trigger.waiting", "Waiting for event")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
