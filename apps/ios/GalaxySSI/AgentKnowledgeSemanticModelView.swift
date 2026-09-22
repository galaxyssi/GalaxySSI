import SwiftUI
import UniformTypeIdentifiers

struct AgentKnowledgeSemanticModelView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @ObservedObject var controller: AgentKnowledgeSemanticController
  @State private var showingImporter = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.agent_knowledge.semantic_title", "Semantic model"),
        leading: { GalaxySSIBackButton() }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          modelSummary
          controls
          if !controller.state.error.isEmpty {
            Text(controller.state.error)
              .font(.system(size: 12))
              .foregroundColor(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(16)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .item]) { result in
      if case let .success(url) = result { controller.importModel(url) }
    }
  }

  private var modelSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 25, weight: .semibold))
          .foregroundColor(.blue)
          .frame(width: 48, height: 48)
          .background(Color.blue.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(AgentKnowledgeEmbeddingModel.id)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(t("galaxyssi.agent_knowledge.semantic_spec", "Chinese and multilingual / 512 dimensions / 512 tokens"))
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
        }
      }
      Divider()
      metricRow(
        t("galaxyssi.agent_knowledge.semantic_status", "Status"),
        phaseLabel(controller.state.phase)
      )
      metricRow(
        t("galaxyssi.agent_knowledge.semantic_indexed", "Indexed chunks"),
        "\(controller.state.indexedChunks)"
      )
      metricRow(
        t("galaxyssi.agent_knowledge.semantic_pending", "Pending documents"),
        "\(controller.state.pendingDocuments)"
      )
      if controller.state.phase == .downloading {
        ProgressView(
          value: Double(controller.state.downloadedBytes),
          total: Double(AgentKnowledgeEmbeddingModel.expectedBytes)
        )
      }
    }
    .padding(14)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var controls: some View {
    VStack(spacing: 0) {
      Toggle(isOn: Binding(
        get: { controller.state.enabled },
        set: { controller.setEnabled($0) }
      )) {
        controlLabel(
          t("galaxyssi.agent_knowledge.semantic_enable", "Enable semantic retrieval"),
          t("galaxyssi.agent_knowledge.semantic_enable_subtitle", "Combine private vector similarity with keyword results"),
          "switch.2"
        )
      }
      .disabled(!controller.state.installed || isBusy)
      .padding(14)
      Divider().padding(.leading, 62)
      actionButton(
        controller.state.phase == .downloading
          ? t("galaxyssi.agent_knowledge.semantic_cancel", "Cancel download")
          : t("galaxyssi.agent_knowledge.semantic_download", "Download verified model"),
        controller.state.phase == .downloading ? "xmark.circle" : "arrow.down.circle"
      ) {
        if controller.state.phase == .downloading { controller.cancelDownload() }
        else { controller.startDownload() }
      }
      Divider().padding(.leading, 62)
      actionButton(t("galaxyssi.agent_knowledge.semantic_import", "Import GGUF model"), "square.and.arrow.down") {
        showingImporter = true
      }
      .disabled(isBusy)
      Divider().padding(.leading, 62)
      actionButton(t("galaxyssi.agent_knowledge.semantic_index", "Index pending knowledge"), "text.magnifyingglass") {
        controller.startIndexing()
      }
      .disabled(!controller.state.enabled || isBusy)
    }
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var isBusy: Bool {
    [.downloading, .verifying, .indexing].contains(controller.state.phase)
  }

  private func metricRow(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundColor(.galaxySSITextSecondary)
      Spacer()
      Text(value).foregroundColor(.galaxySSITextPrimary).fontWeight(.semibold)
    }
    .font(.system(size: 13))
  }

  private func controlLabel(_ title: String, _ subtitle: String, _ image: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: image)
        .font(.system(size: 19, weight: .semibold))
        .foregroundColor(.blue)
        .frame(width: 36)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.galaxySSITextPrimary)
        Text(subtitle).font(.system(size: 12)).foregroundColor(.galaxySSITextSecondary)
      }
    }
  }

  private func actionButton(_ title: String, _ image: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: image)
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(.blue)
          .frame(width: 36)
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .padding(14)
    }
    .buttonStyle(.plain)
  }

  private func phaseLabel(_ phase: AgentKnowledgeSemanticPhase) -> String {
    switch phase {
    case .notInstalled: return t("galaxyssi.agent_knowledge.semantic_not_installed", "Not installed")
    case .downloading: return t("galaxyssi.agent_knowledge.semantic_downloading", "Downloading")
    case .verifying: return t("galaxyssi.agent_knowledge.semantic_verifying", "Verifying")
    case .ready: return t("galaxyssi.agent_knowledge.semantic_ready", "Ready")
    case .indexing: return t("galaxyssi.agent_knowledge.semantic_indexing", "Indexing")
    case .disabled: return t("galaxyssi.agent_knowledge.semantic_disabled", "Disabled")
    case .failed: return t("galaxyssi.agent_knowledge.semantic_failed", "Failed")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
