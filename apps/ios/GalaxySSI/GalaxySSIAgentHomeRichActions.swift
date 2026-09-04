import UIKit

extension AgentHomeView {
  func handleRichAction(_ action: AgentRichAction) {
    switch action.verb {
    case "decide_task_permission":
      handleLocalPermissionAction(action.value)
    case "decide_remote_task_permission":
      handleRemotePermissionAction(action.value)
    case "copy":
      let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        richActionStatus = t("galaxyssi.agent.action_status.empty", "This action has no content.")
        return
      }
      UIPasteboard.general.string = value
      richActionStatus = t("galaxyssi.common.copied", "Copied")
    case "open_uri":
      openRichActionURI(action.value)
    case "set_input":
      prefillAgentScreenCommand(action.value)
    case "submit_prompt":
      submitRichPrompt(action.value)
    case "open_conversation":
      openRichConversation(action.value)
    case "recover_agent_task":
      recoverAgentTask(action.value)
    case "download_desktop_artifact":
      guard let payload = AgentDesktopArtifactRequestPayload.decode(action.value) else {
        runtimeArtifactError = t("runtime_artifact.error.invalid", "The artifact information is invalid.")
        return
      }
      if let file = coordinator.desktopArtifactStore.localFile(for: payload.richBlock) {
        do {
          runtimeArtifactDocument = GalaxySSIRuntimeArtifactDocument(data: try Data(contentsOf: file))
          runtimeArtifactExportFilename = payload.displayName
          runtimeArtifactExportSourceURI = payload.artifactURI
          runtimeArtifactExportPresented = true
        } catch {
          runtimeArtifactError = error.localizedDescription
        }
      } else {
        let block = payload.richBlock
        Task { @MainActor in
          if await coordinator.requestDesktopArtifactDownload(block: block) {
            runtimeArtifactStatus = t(
              "runtime_artifact.download_requested",
              "The Desktop was asked to resend this artifact."
            )
          } else {
            runtimeArtifactError = coordinator.lastError.ifBlank(
              t(
                "runtime_artifact.download_failed",
                "The artifact could not be requested from the Desktop."
              )
            )
          }
        }
      }
    case "preview_runtime_artifact", "save_runtime_artifact":
      guard let payload = AgentRuntimeArtifactActionPayload.decode(action.value) else {
        runtimeArtifactError = t("runtime_artifact.error.invalid", "The artifact information is invalid.")
        return
      }
      do {
        let file = try AgentRuntimeArtifactUi.resolve(
          payload: payload,
          managedRoots: runtimeArtifactManagedRoots
        )
        if action.verb == "preview_runtime_artifact" {
          runtimeArtifactPreview = GalaxySSIRuntimeArtifactPreview(
            title: payload.displayName,
            content: try AgentRuntimeArtifactUi.preview(file: file)
          )
        } else {
          runtimeArtifactDocument = GalaxySSIRuntimeArtifactDocument(data: try Data(contentsOf: file))
          runtimeArtifactExportFilename = payload.displayName
          runtimeArtifactExportSourceURI = ""
          runtimeArtifactExportPresented = true
        }
      } catch {
        runtimeArtifactError = error.localizedDescription
      }
    default:
      richActionStatus = action.label
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(
          t(
            "galaxyssi.agent.action_status.unsupported",
            "This Agent action is not available on iOS."
          )
        )
    }
  }

  func handleRichAction(_ action: AgentRichAction, from message: ChatMessage) {
    guard action.verb == "recover_agent_task" else {
      handleRichAction(action)
      return
    }
    recoverAgentTask(action.value, sourceMessage: message)
  }

  func openRichActionURI(_ rawURI: String) {
    let value = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "mailto", "tel", "sms"].contains(scheme),
          (scheme == "http" || scheme == "https" ? url.host != nil : true) else {
      richActionStatus = t("galaxyssi.agent.action_status.invalid_uri", "This link cannot be opened on iOS.")
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      guard !opened else { return }
      DispatchQueue.main.async {
        richActionStatus = t("galaxyssi.agent.action_status.open_failed", "The link could not be opened.")
      }
    }
  }

  func submitRichPrompt(_ rawPrompt: String) {
    let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      richActionStatus = t("galaxyssi.agent.action_status.empty", "This action has no content.")
      return
    }
    draft = prompt
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
    sendAgentMessage()
  }

  func openRichConversation(_ rawConversationID: String) {
    let conversationID = rawConversationID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty, store.switchAgentSession(conversationID) else {
      richActionStatus = t(
        "galaxyssi.agent.action_status.conversation_unavailable",
        "That Agent conversation is no longer available."
      )
      return
    }
    draft = ""
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
  }
}
