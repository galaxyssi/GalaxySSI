import SwiftUI

struct SignalASIWorkflowsView: View {
  @ObservedObject private var workflowStore = UserDefaultsAgentWorkflowStore.shared
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var creatingWorkflow = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.workflow.title", "Workflows"),
        leading: { SignalASIBackButton() },
        trailing: {
          Button {
            creatingWorkflow = true
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.signalASIAccent)
          }
          .accessibilityLabel(t("signalasi.workflow.new", "New workflow"))
        }
      )

      NavigationLink(
        destination: SignalASIWorkflowEditorView(),
        isActive: $creatingWorkflow
      ) {
        EmptyView()
      }
      .hidden()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AutomationHeroCard(
            title: t("signalasi.workflow.hero_title", "Reusable Agent workflows"),
            subtitle: t("signalasi.workflow.hero_subtitle", "Save a goal once and use it from automation"),
            icon: "square.stack.3d.up",
            tint: .signalASIAccent,
            metrics: [
              AutomationMetric(
                value: "\(workflowStore.list().count)",
                label: t("signalasi.workflow.metric_saved", "Saved")
              ),
              AutomationMetric(
                value: "\(AgentWorkflowTemplates.all.count)",
                label: t("signalasi.workflow.metric_templates", "Templates")
              ),
              AutomationMetric(
                value: "\(workflowStore.list().reduce(0) { $0 + $1.runCount })",
                label: t("signalasi.workflow.metric_runs", "Runs")
              )
            ]
          )

          sectionTitle(t("signalasi.workflow.saved", "Saved workflows"))
          if workflowStore.list().isEmpty {
            AutomationInfoRow(
              title: t("signalasi.workflow.no_saved", "No saved workflows"),
              subtitle: t("signalasi.workflow.no_saved_subtitle", "Create a workflow to reuse the same Agent goal"),
              icon: "square.stack.3d.up.slash",
              tint: .signalASITextSecondary,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(workflowStore.list()) { workflow in
                NavigationLink(
                  destination: SignalASIWorkflowEditorView(
                    initialName: workflow.name,
                    initialGoal: workflow.goal
                  )
                ) {
                  WorkflowRow(workflow: workflow, language: interfaceLanguage)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button(role: .destructive) {
                    _ = workflowStore.delete(name: workflow.name)
                  } label: {
                    Label(t("signalasi.common.delete", "Delete"), systemImage: "trash")
                  }
                }
              }
            }
          }

          sectionTitle(t("signalasi.workflow.templates", "Templates"))
          VStack(spacing: 8) {
            ForEach(AgentWorkflowTemplates.all) { template in
              NavigationLink(
                destination: SignalASIWorkflowEditorView(
                  initialName: template.name,
                  initialGoal: template.goal
                )
              ) {
                WorkflowTemplateRow(template: template, language: interfaceLanguage)
              }
              .buttonStyle(.plain)
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
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct WorkflowRow: View {
  var workflow: AgentWorkflow
  var language: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      WorkflowIcon(systemName: "square.stack.3d.up", tint: .signalASIAccent)
      VStack(alignment: .leading, spacing: 4) {
        Text(workflow.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Text(workflow.goal)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
        Text(String(format: SignalASILocalization.string(
          "signalasi.workflow.run_count",
          fallback: "%d runs",
          language: language
        ), workflow.runCount))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct WorkflowTemplateRow: View {
  var template: AgentWorkflowTemplate
  var language: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      WorkflowIcon(systemName: "wand.and.stars", tint: .blue)
      VStack(alignment: .leading, spacing: 4) {
        Text(template.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Text(template.goal)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(SignalASILocalization.string(
        "signalasi.workflow.use",
        fallback: "Use",
        language: language
      ))
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.blue)
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct WorkflowIcon: View {
  var systemName: String
  var tint: Color

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.14))
      Image(systemName: systemName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(tint)
    }
    .frame(width: 44, height: 44)
  }
}

struct SignalASIWorkflowEditorView: View {
  @ObservedObject private var workflowStore = UserDefaultsAgentWorkflowStore.shared
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  @State private var name: String
  @State private var goal: String
  @State private var errorMessage = ""

  init(initialName: String = "", initialGoal: String = "") {
    _name = State(initialValue: initialName)
    _goal = State(initialValue: initialGoal)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.workflow.editor_title", "Workflow"),
        leading: { SignalASIBackButton() },
        trailing: {
          Button {
            save()
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.signalASIAccent)
          }
          .accessibilityLabel(t("signalasi.common.save", "Save"))
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AutomationHeroCard(
            title: name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(
              t("signalasi.workflow.new", "New workflow")
            ),
            subtitle: t("signalasi.workflow.editor_subtitle", "Reuse one Agent goal from automation"),
            icon: "square.stack.3d.up",
            tint: .signalASIAccent,
            metrics: [
              AutomationMetric(value: "80", label: t("signalasi.workflow.name_limit", "Name limit")),
              AutomationMetric(value: "2K", label: t("signalasi.workflow.goal_limit", "Goal limit")),
              AutomationMetric(value: "iOS 15+", label: t("signalasi.workflow.platform", "Platform"))
            ]
          )
          AutomationTextInputRow(
            title: t("signalasi.workflow.name", "Name"),
            subtitle: t("signalasi.workflow.name_hint", "Use a short name you can recognize later"),
            icon: "textformat",
            tint: .signalASIAccent,
            text: $name
          )
          AutomationTextEditorRow(
            title: t("signalasi.workflow.goal", "Goal or instructions"),
            subtitle: t("signalasi.workflow.goal_hint", "The saved goal will be sent to the Agent when this workflow runs"),
            icon: "paperplane",
            tint: .orange,
            text: $goal,
            minHeight: 130
          )
          AutomationActionRow(
            title: t("signalasi.common.save", "Save"),
            subtitle: t("signalasi.workflow.save_subtitle", "Keep this workflow available for automation"),
            icon: "square.and.arrow.down",
            tint: .signalASIAccent,
            badge: t("signalasi.common.save", "Save"),
            action: save
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("signalasi.workflow.invalid", "The workflow is invalid"), isPresented: Binding(
      get: { !errorMessage.isEmpty },
      set: { if !$0 { errorMessage = "" } }
    )) {
      Button(t("signalasi.common.ok", "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func save() {
    do {
      _ = try workflowStore.save(name: name, goal: goal)
      presentationMode.wrappedValue.dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct WorkflowTargetPickerRow: View {
  @ObservedObject private var workflowStore = UserDefaultsAgentWorkflowStore.shared
  @Binding var targetId: String
  var language: String

  private var targets: [String] {
    var values = workflowStore.list().map(\.name) + AgentWorkflowTemplates.all.map(\.name)
    if !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !values.contains(targetId) {
      values.insert(targetId, at: 0)
    }
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  var body: some View {
    HStack(spacing: 12) {
      WorkflowIcon(systemName: "square.stack.3d.up", tint: .signalASIAccent)
      Text(SignalASILocalization.string(
        "signalasi.automation.target",
        fallback: "Target",
        language: language
      ))
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      Spacer(minLength: 8)
      Picker("Target", selection: $targetId) {
        ForEach(targets, id: \.self) { target in
          Text(target).tag(target)
        }
      }
      .pickerStyle(MenuPickerStyle())
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onAppear {
      if targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        targetId = AgentWorkflowResolver.defaultReference(store: workflowStore)
      }
    }
  }
}
