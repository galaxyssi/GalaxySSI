import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIAgentHomePresentationRoutes: ViewModifier {
  @Binding var scanShortcutActive: Bool
  @Binding var fileImporterPresented: Bool
  @Binding var photoPickerPresented: Bool
  @Binding var cameraPickerPresented: Bool
  @Binding var attachmentError: String
  @Binding var homeActionEditorSelection: GalaxySSIAgentRuntimeActionSelection?
  @Binding var runtimeArtifactPreview: GalaxySSIRuntimeArtifactPreview?
  @Binding var runtimeArtifactDocument: GalaxySSIRuntimeArtifactDocument?
  @Binding var runtimeArtifactExportPresented: Bool
  @Binding var runtimeArtifactExportFilename: String
  @Binding var runtimeArtifactError: String
  @Binding var runtimeArtifactStatus: String
  @Binding var richActionStatus: String
  @Binding var pendingHighRiskApprovalTask: AgentTaskRecord?
  @Binding var homeTaskPendingDeletion: AgentTaskRecord?

  let t: (String, String) -> String
  let onAgentAdded: ([String]) -> Void
  let onAddAttachment: (URL) -> Void
  let onAppendAttachment: (GalaxySSIDraftAttachment) -> Void
  let onUpdatePendingAction: (String, String, String, String) -> AgentPendingActionEditResult
  let onMovePendingAction: (String, String, Int) -> AgentPendingActionEditResult
  let onRemovePendingAction: (String, String) -> AgentPendingActionEditResult
  let onArtifactExport: (Result<URL, Error>) -> Void
  let onApproveHighRisk: (AgentTaskRecord) -> Void
  let onDeleteTask: (AgentTaskRecord) -> Void

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $scanShortcutActive) {
        AddContactView(
          autoOpenScanner: true,
          onAgentAdded: { agentIDs in
            scanShortcutActive = false
            onAgentAdded(agentIDs)
          },
          onImportCompleted: {
            // Return to the Agent home even when the scanned Agent needs approval.
            scanShortcutActive = false
          }
        )
      }
      .fileImporter(
        isPresented: $fileImporterPresented,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true
      ) { result in
        switch result {
        case .success(let urls):
          urls.forEach(onAddAttachment)
        case .failure(let error):
          attachmentError = error.localizedDescription
        }
      }
      .sheet(isPresented: $photoPickerPresented) {
        PhotoLibraryPickerView { attachment in
          onAppendAttachment(attachment)
        }
      }
      .fullScreenCover(isPresented: $cameraPickerPresented) {
        CameraAttachmentPickerView(
          onAttachment: { attachment in
            onAppendAttachment(attachment)
            cameraPickerPresented = false
          },
          onCancel: {
            cameraPickerPresented = false
          }
        )
      }
      .sheet(item: $homeActionEditorSelection) { selection in
        GalaxySSIAgentRuntimeActionEditorSheet(
          task: selection.task,
          action: selection.action,
          t: t,
          onUpdate: onUpdatePendingAction,
          onMove: onMovePendingAction,
          onRemove: onRemovePendingAction
        )
      }
      .sheet(item: $runtimeArtifactPreview) { preview in
        GalaxySSIRuntimeArtifactPreviewView(preview: preview)
      }
      .fileExporter(
        isPresented: $runtimeArtifactExportPresented,
        document: runtimeArtifactDocument,
        contentType: .data,
        defaultFilename: runtimeArtifactExportFilename,
        onCompletion: onArtifactExport
      )
      .alert(
        t("runtime_artifact.error.title", "Artifact unavailable"),
        isPresented: Binding(
          get: { !runtimeArtifactError.isEmpty },
          set: { if !$0 { runtimeArtifactError = "" } }
        )
      ) {
        Button(t("galaxyssi.common.done", "Done"), role: .cancel) {
          runtimeArtifactError = ""
        }
      } message: {
        Text(runtimeArtifactError)
      }
      .alert(
        t("runtime_artifact.status.title", "Artifact"),
        isPresented: Binding(
          get: { !runtimeArtifactStatus.isEmpty },
          set: { if !$0 { runtimeArtifactStatus = "" } }
        )
      ) {
        Button(t("galaxyssi.common.done", "Done"), role: .cancel) {
          runtimeArtifactStatus = ""
        }
      } message: {
        Text(runtimeArtifactStatus)
      }
      .alert(
        t("galaxyssi.agent.action_status.title", "Agent action"),
        isPresented: Binding(
          get: { !richActionStatus.isEmpty },
          set: { if !$0 { richActionStatus = "" } }
        )
      ) {
        Button(t("galaxyssi.common.done", "Done"), role: .cancel) {
          richActionStatus = ""
        }
      } message: {
        Text(richActionStatus)
      }
      .alert(item: $pendingHighRiskApprovalTask) { task in
        let action = task.pendingAction
        let fallbackDescription = t("galaxyssi.agent.confirmation.untitled", "Phone action")
        let description = action.map {
          $0.description.ifBlank(fallbackDescription)
        } ?? fallbackDescription
        let target = action?.target.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = target.isEmpty ? description : "\(description)\n\(target)"
        return Alert(
          title: Text(t("galaxyssi.agent.high_risk_confirmation.title", "Confirm high-risk action")),
          message: Text(detail),
          primaryButton: .default(
            Text(t("galaxyssi.agent.high_risk_confirmation.execute", "Execute"))
          ) {
            onApproveHighRisk(task)
          },
          secondaryButton: .cancel(Text(t("galaxyssi.common.cancel", "Cancel")))
        )
      }
      .alert(item: $homeTaskPendingDeletion) { task in
        Alert(
          title: Text(t("galaxyssi.agent_task_center.delete_title", "Delete task?")),
          message: Text(
            String(
              format: t(
                "galaxyssi.agent_task_center.delete_message",
                "Delete the task record for \"%@\"? The conversation will remain available."
              ),
              task.goal
            )
          ),
          primaryButton: .destructive(Text(t("galaxyssi.common.delete", "Delete"))) {
            onDeleteTask(task)
          },
          secondaryButton: .cancel(Text(t("galaxyssi.common.cancel", "Cancel")))
        )
      }
  }
}

extension View {
  func galaxySSIAgentHomePresentationRoutes(
    scanShortcutActive: Binding<Bool>,
    fileImporterPresented: Binding<Bool>,
    photoPickerPresented: Binding<Bool>,
    cameraPickerPresented: Binding<Bool>,
    attachmentError: Binding<String>,
    homeActionEditorSelection: Binding<GalaxySSIAgentRuntimeActionSelection?>,
    runtimeArtifactPreview: Binding<GalaxySSIRuntimeArtifactPreview?>,
    runtimeArtifactDocument: Binding<GalaxySSIRuntimeArtifactDocument?>,
    runtimeArtifactExportPresented: Binding<Bool>,
    runtimeArtifactExportFilename: Binding<String>,
    runtimeArtifactError: Binding<String>,
    runtimeArtifactStatus: Binding<String>,
    richActionStatus: Binding<String>,
    pendingHighRiskApprovalTask: Binding<AgentTaskRecord?>,
    homeTaskPendingDeletion: Binding<AgentTaskRecord?>,
    t: @escaping (String, String) -> String,
    onAgentAdded: @escaping ([String]) -> Void,
    onAddAttachment: @escaping (URL) -> Void,
    onAppendAttachment: @escaping (GalaxySSIDraftAttachment) -> Void,
    onUpdatePendingAction: @escaping (String, String, String, String) -> AgentPendingActionEditResult,
    onMovePendingAction: @escaping (String, String, Int) -> AgentPendingActionEditResult,
    onRemovePendingAction: @escaping (String, String) -> AgentPendingActionEditResult,
    onArtifactExport: @escaping (Result<URL, Error>) -> Void,
    onApproveHighRisk: @escaping (AgentTaskRecord) -> Void,
    onDeleteTask: @escaping (AgentTaskRecord) -> Void
  ) -> some View {
    modifier(
      GalaxySSIAgentHomePresentationRoutes(
        scanShortcutActive: scanShortcutActive,
        fileImporterPresented: fileImporterPresented,
        photoPickerPresented: photoPickerPresented,
        cameraPickerPresented: cameraPickerPresented,
        attachmentError: attachmentError,
        homeActionEditorSelection: homeActionEditorSelection,
        runtimeArtifactPreview: runtimeArtifactPreview,
        runtimeArtifactDocument: runtimeArtifactDocument,
        runtimeArtifactExportPresented: runtimeArtifactExportPresented,
        runtimeArtifactExportFilename: runtimeArtifactExportFilename,
        runtimeArtifactError: runtimeArtifactError,
        runtimeArtifactStatus: runtimeArtifactStatus,
        richActionStatus: richActionStatus,
        pendingHighRiskApprovalTask: pendingHighRiskApprovalTask,
        homeTaskPendingDeletion: homeTaskPendingDeletion,
        t: t,
        onAgentAdded: onAgentAdded,
        onAddAttachment: onAddAttachment,
        onAppendAttachment: onAppendAttachment,
        onUpdatePendingAction: onUpdatePendingAction,
        onMovePendingAction: onMovePendingAction,
        onRemovePendingAction: onRemovePendingAction,
        onArtifactExport: onArtifactExport,
        onApproveHighRisk: onApproveHighRisk,
        onDeleteTask: onDeleteTask
      )
    )
  }
}
