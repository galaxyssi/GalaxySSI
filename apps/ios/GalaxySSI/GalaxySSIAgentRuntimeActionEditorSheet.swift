import SwiftUI

struct GalaxySSIAgentRuntimeActionSelection: Identifiable {
  var task: AgentTaskRecord
  var action: AgentAction

  var id: String { "\(task.taskId):\(action.id)" }
}

struct GalaxySSIAgentRuntimeActionEditorSheet: View {
  @Environment(\.dismiss) private var dismiss

  var task: AgentTaskRecord
  var action: AgentAction
  var t: (String, String) -> String
  var onUpdate: (String, String, String, String) -> AgentPendingActionEditResult
  var onMove: (String, String, Int) -> AgentPendingActionEditResult
  var onRemove: (String, String) -> AgentPendingActionEditResult

  @State private var description: String
  @State private var input: String
  @State private var errorMessage = ""
  @State private var showRemoveConfirmation = false

  init(
    task: AgentTaskRecord,
    action: AgentAction,
    t: @escaping (String, String) -> String,
    onUpdate: @escaping (String, String, String, String) -> AgentPendingActionEditResult,
    onMove: @escaping (String, String, Int) -> AgentPendingActionEditResult,
    onRemove: @escaping (String, String) -> AgentPendingActionEditResult
  ) {
    self.task = task
    self.action = action
    self.t = t
    self.onUpdate = onUpdate
    self.onMove = onMove
    self.onRemove = onRemove
    _description = State(initialValue: action.description)
    _input = State(initialValue: AgentPlanEditor.inputValue(action: action))
  }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 6) {
            Text(t("agent_plan_edit_action", "Edit action"))
              .font(.system(size: 17, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
            Text(action.description.ifBlank(action.kind.rawValue))
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          editorField(
            title: t("agent_plan_action_description", "Description"),
            text: $description,
            minHeight: 110
          )

          if AgentPlanEditor.inputKey(action: action) != nil {
            editorField(
              title: t("agent_plan_action_input", "Input"),
              text: $input,
              minHeight: 90
            )
          }

          if !errorMessage.isBlank {
            Text(errorMessage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.red)
              .fixedSize(horizontal: false, vertical: true)
          }

          VStack(spacing: 8) {
            actionButton(
              title: t("agent_plan_move_up", "Move up"),
              systemImage: "arrow.up",
              action: { move(offset: -1) }
            )
            actionButton(
              title: t("agent_plan_move_down", "Move down"),
              systemImage: "arrow.down",
              action: { move(offset: 1) }
            )
            actionButton(
              title: t("agent_plan_remove_action", "Remove action"),
              systemImage: "trash",
              tint: .red,
              action: { showRemoveConfirmation = true }
            )
          }
        }
        .padding(16)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationTitle(t("agent_plan_edit_title", "Edit pending action"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("common_save", "Save")) {
            save()
          }
          .font(.body.weight(.semibold))
        }
      }
      .alert(
        t("agent_plan_remove_action", "Remove action"),
        isPresented: $showRemoveConfirmation
      ) {
        Button(t("common_delete", "Delete"), role: .destructive) {
          remove()
        }
        Button(t("common_cancel", "Cancel"), role: .cancel) {}
      } message: {
        Text(t("agent_plan_remove_confirmation", "This pending action will be removed from the task."))
      }
    }
  }

  private func editorField(
    title: String,
    text: Binding<String>,
    minHeight: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      TextEditor(text: text)
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextPrimary)
        .frame(minHeight: minHeight)
        .padding(8)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func actionButton(
    title: String,
    systemImage: String,
    tint: Color = .galaxySSIAccent,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func save() {
    let result = onUpdate(task.taskId, action.id, description, input)
    handle(result)
  }

  private func move(offset: Int) {
    let result = onMove(task.taskId, action.id, offset)
    handle(result)
  }

  private func remove() {
    let result = onRemove(task.taskId, action.id)
    handle(result)
  }

  private func handle(_ result: AgentPendingActionEditResult) {
    if result.success {
      dismiss()
    } else {
      errorMessage = localizedError(result.error.ifBlank(
        t("agent_plan_edit_failed", "Unable to update this action")
      ))
    }
  }

  private func localizedError(_ message: String) -> String {
    switch message {
    case "Action is no longer in the active task":
      return t("agent_plan_error_inactive", "This action is no longer active")
    case "Only pending actions can be edited":
      return t("agent_plan_error_edit_pending", "Only pending actions can be edited")
    case "Only pending actions can be removed":
      return t("agent_plan_error_remove_pending", "Only pending actions can be removed")
    case "Only pending actions can be moved":
      return t("agent_plan_error_move_pending", "Only pending actions can be moved")
    case "Action description cannot be empty":
      return t("agent_plan_error_description", "Action description cannot be empty")
    case "Action input cannot be empty":
      return t("agent_plan_error_input", "Action input cannot be empty")
    case "A task must contain at least one action":
      return t("agent_plan_error_last_action", "A task must contain at least one action")
    case "Unsupported move":
      return t("agent_plan_error_move", "Unsupported move")
    case "Action is already at the task boundary":
      return t("agent_plan_error_boundary", "Action is already at the boundary")
    case "Completed or running actions cannot be reordered":
      return t("agent_plan_error_order", "Completed or running actions cannot be reordered")
    case "Only paused or waiting tasks can be edited":
      return t("agent_plan_error_task_state", "Only paused or waiting tasks can be edited")
    default:
      if message.hasPrefix("Remove dependent action") {
        return t("agent_plan_error_dependency", "Remove dependent actions first")
      }
      return message
    }
  }
}
