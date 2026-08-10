import AVKit
import AVFoundation
import Foundation
import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers

struct SignalASIRichContentView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var coordinator: MessageCoordinator
  @EnvironmentObject private var store: SignalASIStore

  @State private var artifactDocument: SignalASIArtifactDocument?
  @State private var artifactExportPresented = false
  @State private var artifactExportSourceURI = ""
  @State private var artifactExportFilename = "SignalASI-artifact"
  @State private var largeOutputExpanded = false

  var content: String
  var richOutputJson: String = ""
  var isOutgoing: Bool = false
  var onAction: (AgentRichAction) -> Void = { _ in }
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void = { _, _ in }

  private var resolvedBlocks: [AgentRichBlock] {
    let richSource = richOutputJson.trimmingCharacters(in: .whitespacesAndNewlines)
    if !richSource.isEmpty {
      let explicit = AgentRichContentCodec.decode(richSource)
      if !explicit.isEmpty {
        return explicit.map { coordinator.desktopArtifactStore.resolveBlock($0) }
      }
    }

    let explicit = AgentRichContentCodec.decode(content)
    let blocks = explicit.isEmpty ? AgentRichContentCodec.fromText(content) : explicit
    return blocks.map { coordinator.desktopArtifactStore.resolveBlock($0) }
  }

  var body: some View {
    _ = coordinator.artifactRevision
    let blocks = resolvedBlocks
    let layout = AgentResponseSectionOrganizer.organize(
      blocks,
      expandStructuredDetails: AgentPreferenceModePolicy
        .profile(store.agentPreferenceMode)
        .expandStructuredDetails
    )

    Group {
      if isLargeOutput && !largeOutputExpanded {
        largeOutputPreview
      } else {
        VStack(alignment: .leading, spacing: 8) {
          if blocks.isEmpty {
            Text(content)
              .font(.body)
              .textSelection(.enabled)
          } else if layout.collapsible {
            ForEach(layout.sections) { section in
              if section.kind == .finalAnswer {
                SignalASIRichBlockListView(
                  blocks: section.blocks,
                  isOutgoing: isOutgoing,
                  onAction: onAction,
                  onFormSubmit: onFormSubmit,
                  onArtifactSave: { exportArtifact($0) }
                )
                .padding(.vertical, 4)
              } else {
                SignalASIRichSectionView(
                  section: section,
                  isOutgoing: isOutgoing,
                  onAction: onAction,
                  onFormSubmit: onFormSubmit,
                  onArtifactSave: { exportArtifact($0) }
                )
              }
            }
          } else {
            SignalASIRichBlockListView(
              blocks: blocks,
              isOutgoing: isOutgoing,
              onAction: onAction,
              onFormSubmit: onFormSubmit,
              onArtifactSave: { exportArtifact($0) }
            )
          }
          if isLargeOutput {
            largeOutputToggle
          }
        }
      }
    }
    .environment(\.signalASIInterfaceLanguage, interfaceLanguage)
    .textSelection(.enabled)
    .fileExporter(
      isPresented: $artifactExportPresented,
      document: artifactDocument,
      contentType: .data,
      defaultFilename: artifactExportFilename
    ) { result in
      guard case .success = result else { return }
      coordinator.markDesktopArtifactSaved(
        sourceURI: artifactExportSourceURI,
        savedURI: "file-export://\(artifactExportFilename)"
      )
    }
  }

  private var isLargeOutput: Bool {
    max(content.utf16.count, richOutputJson.utf16.count) > AgentLargeOutputPolicy.chunkThresholdCharacters
  }

  private var largeOutputPreview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(largeOutputPreviewText)
        .font(.body)
        .foregroundColor(.signalASITextPrimary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      largeOutputToggle
    }
  }

  private var largeOutputToggle: some View {
    Button {
      largeOutputExpanded.toggle()
    } label: {
      Label(
        largeOutputExpanded
          ? t("rich_output_show_less", "Show less")
          : t("rich_output_show_more", "Show more"),
        systemImage: largeOutputExpanded ? "chevron.up" : "chevron.down"
      )
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASIAccent)
      .frame(minHeight: 36)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        largeOutputExpanded
          ? t("rich_output_show_less", "Show less")
          : t("rich_output_show_more", "Show more")
      )
    )
  }

  private var largeOutputPreviewText: String {
    let source = content.ifBlank(AgentRichContentCodec.fallbackText(richOutputJson))
      .ifBlank(t("rich_output_load_failed", "Unable to display preview"))
    let preview = String(source.prefix(AgentLargeOutputPolicy.previewCharacters))
    return preview.count < source.count ? preview + "..." : preview
  }

  fileprivate func exportArtifact(_ block: AgentRichBlock) {
    guard let file = coordinator.desktopArtifactStore.localFile(for: block),
      let data = try? Data(contentsOf: file) else {
      return
    }
    artifactExportSourceURI = block.metadata["artifact_source_uri"] ?? block.uri
    artifactExportFilename = AgentDesktopArtifactStore.safeFileName(
      block.title.ifBlank(file.lastPathComponent)
    )
    artifactDocument = SignalASIArtifactDocument(data: data)
    artifactExportPresented = true
  }
}

private struct SignalASIRichSectionView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var section: AgentResponseSection
  var isOutgoing: Bool
  var onAction: (AgentRichAction) -> Void
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void
  var onArtifactSave: (AgentRichBlock) -> Void

  @State private var expanded: Bool

  init(
    section: AgentResponseSection,
    isOutgoing: Bool,
    onAction: @escaping (AgentRichAction) -> Void,
    onFormSubmit: @escaping (AgentRichBlock, [String: String]) -> Void,
    onArtifactSave: @escaping (AgentRichBlock) -> Void
  ) {
    self.section = section
    self.isOutgoing = isOutgoing
    self.onAction = onAction
    self.onFormSubmit = onFormSubmit
    self.onArtifactSave = onArtifactSave
    _expanded = State(initialValue: section.expandedByDefault)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          expanded.toggle()
        }
      } label: {
        HStack(spacing: 8) {
          Text(sectionTitle)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(String(format: t("rich_output_section_items", "%d items"), section.blocks.count))
            .font(.caption2)
            .foregroundColor(.signalASITextSecondary)
          Spacer(minLength: 8)
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .rotationEffect(.degrees(expanded ? 180 : 0))
            .foregroundColor(.signalASITextSecondary)
        }
        .frame(minHeight: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        expanded
          ? t("rich_output_section_collapse", "Collapse section")
          : t("rich_output_section_expand", "Expand section")
      )

      Divider()

      if expanded {
        SignalASIRichBlockListView(
          blocks: section.blocks,
          isOutgoing: isOutgoing,
          onAction: onAction,
          onFormSubmit: onFormSubmit,
          onArtifactSave: onArtifactSave
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  private var sectionTitle: String {
    switch section.kind {
    case .plan:
      return t("rich_output_section_plan", "Plan")
    case .executionLog:
      return t("rich_output_section_execution_log", "Execution log")
    case .finalAnswer:
      return ""
    case .evidence:
      return t("rich_output_section_evidence", "Evidence")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIRichBlockListView: View {
  var blocks: [AgentRichBlock]
  var isOutgoing: Bool
  var onAction: (AgentRichAction) -> Void
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void
  var onArtifactSave: (AgentRichBlock) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { block in
        SignalASIRichBlockView(
          block: block,
          isOutgoing: isOutgoing,
          onAction: onAction,
          onFormSubmit: onFormSubmit,
          onArtifactSave: onArtifactSave
        )
      }
    }
  }
}

private struct SignalASIRichBlockView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var coordinator: MessageCoordinator

  var block: AgentRichBlock
  var isOutgoing: Bool
  var onAction: (AgentRichAction) -> Void
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void
  var onArtifactSave: (AgentRichBlock) -> Void

  @State private var expandedCode = false
  @State private var expandedTable = false
  @State private var copiedCode = false
  @State private var formValues: [String: String] = [:]
  @State private var imageViewerItem: SignalASIImageViewerItem?

  var body: some View {
    switch block.type {
    case .text:
      selectableText(displayText)
    case .heading:
      headingBlock
    case .quote:
      quoteBlock
    case .list:
      listBlock
    case .divider:
      Divider()
        .padding(.vertical, 2)
    case .code, .json, .diff:
      codeBlock
    case .keyValue:
      keyValueBlock
    case .table:
      tableBlock
    case .image:
      imageBlock
    case .video:
      videoBlock
    case .audio:
      audioBlock
    case .gallery:
      galleryBlock
    case .chart:
      chartBlock
    case .status:
      statusBlock
    case .progress:
      progressBlock
    case .metric:
      metricBlock
    case .tool:
      toolBlock
    case .timeline:
      timelineBlock
    case .notice:
      noticeBlock
    case .actions:
      actionsBlock(title: block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? t("rich_output_actions", "Actions") : block.title)
    case .approval:
      approvalBlock
    case .form:
      formBlock
    case .html:
      htmlBlock
    case .webpage:
      webpageBlock
    case .file, .link, .citation, .unknown:
      resourceBlock
    }
  }

  private var displayText: String {
    firstNonEmpty([block.text, block.title, block.fallbackText, block.uri])
  }

  private var headingBlock: some View {
    let level = Int(block.metadata["level"] ?? "") ?? 2
    return selectableText(displayText)
      .font(level == 1 ? .title3.weight(.bold) : .subheadline.weight(.semibold))
  }

  private var quoteBlock: some View {
    HStack(alignment: .top, spacing: 8) {
      Rectangle()
        .fill(Color.signalASIAccent.opacity(0.75))
        .frame(width: 3)
      selectableText(displayText)
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.vertical, 3)
  }

  private var listBlock: some View {
    let values = listRows
    return VStack(alignment: .leading, spacing: 5) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        HStack(alignment: .top, spacing: 7) {
          Text("•")
            .foregroundColor(.signalASITextSecondary)
          selectableText(value)
        }
      }
    }
  }

  private var codeBlock: some View {
    let value = displayText
    let lines = value.components(separatedBy: .newlines)
    let collapsed = !expandedCode && lines.count > Self.collapsedCodeLines
    let visibleText = collapsed ? lines.prefix(Self.collapsedCodeLines).joined(separator: "\n") : value
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text(codeLabel)
          .font(.caption2.weight(.semibold))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
        Spacer(minLength: 8)
        if copiedCode {
          Text(t("rich_output_copied", "Copied"))
            .font(.caption2.weight(.semibold))
            .foregroundColor(.signalASIAccent)
            .transition(.opacity)
        }
        Button {
          copyCode(value)
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.caption.weight(.semibold))
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundColor(copiedCode ? .signalASIAccent : .signalASITextSecondary)
        .accessibilityLabel(copiedCode ? t("rich_output_copied", "Copied") : t("rich_output_copy", "Copy"))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.signalASISearchBackground.opacity(isOutgoing ? 0.4 : 0.7))

      ScrollView(.horizontal, showsIndicators: true) {
        Text(visibleText)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.signalASITextPrimary)
          .textSelection(.enabled)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if lines.count > Self.collapsedCodeLines {
        Button {
          expandedCode.toggle()
        } label: {
          Text(expandedCode ? t("rich_output_show_less", "Show less") : t("rich_output_show_more", "Show more"))
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundColor(.signalASIAccent)
        .background(Color.signalASISearchBackground.opacity(0.35))
      }
    }
    .background(Color.signalASISurface.opacity(isOutgoing ? 0.75 : 1))
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var keyValueBlock: some View {
    let pairs = keyValuePairs
    return VStack(alignment: .leading, spacing: 0) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
          .padding(.bottom, 6)
      }
      ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
        HStack(alignment: .top, spacing: 10) {
          Text(pair.key)
            .font(.caption.weight(.semibold))
            .foregroundColor(.signalASITextSecondary)
            .frame(width: 88, alignment: .leading)
          selectableText(pair.value)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(index.isMultiple(of: 2) ? Color.signalASISurface : Color.signalASISearchBackground.opacity(0.35))
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var tableBlock: some View {
    let columnCount = tableColumnCount
    let visibleRows = expandedTable ? block.rows : Array(block.rows.prefix(Self.visibleTableRows))
    return VStack(alignment: .leading, spacing: 6) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
      }

      ScrollView(.horizontal, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          if !block.columns.isEmpty {
            tableRow(block.columns, header: true, columnCount: columnCount, rowIndex: 0)
          }
          ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
            tableRow(row, header: false, columnCount: columnCount, rowIndex: index)
          }
        }
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(Color.signalASISeparator, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      }

      if block.rows.count > Self.visibleTableRows {
        Button {
          expandedTable.toggle()
        } label: {
          Text(expandedTable
            ? t("rich_output_show_less", "Show less")
            : String(format: t("rich_output_more_rows", "%d more rows"), block.rows.count - Self.visibleTableRows))
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundColor(.signalASIAccent)
      }
    }
  }

  private var imageBlock: some View {
    if isDesktopArtifact {
      desktopArtifactBlock
    } else {
      let data = inlineImageData ?? localImageData
      let url = remoteURL
      VStack(alignment: .leading, spacing: 6) {
        if !block.title.isEmpty {
          selectableText(block.title)
            .font(.subheadline.weight(.semibold))
        }

        Group {
          if let data {
            SignalASIAnimatedImageView(data: data)
          } else if let url {
            SignalASIAsyncAnimatedImageView(url: url) {
              resourceBlock
            }
          } else {
            resourceBlock
          }
        }
        .frame(maxHeight: 240)
        .background(Color.signalASISearchBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
          guard let item = makeImageViewerItem(
            data: data,
            url: url,
            id: "\(block.id)-image",
            title: block.title
          ) else { return }
          imageViewerItem = item
        }
        .fullScreenCover(item: $imageViewerItem) { item in
          SignalASIImageLightboxView(item: item)
        }
      }
    }
  }

  private var audioBlock: some View {
    if let url = mediaURL {
      SignalASIAudioArtifactView(
        url: url,
        title: block.title.isEmpty ? t("rich_output_type_audio", "Audio") : block.title
      )
    } else {
      resourceBlock
    }
  }

  private var htmlBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
      }
      SignalASIInlineHTMLView(html: block.text)
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      if !block.fallbackText.isEmpty {
        selectableText(block.fallbackText)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
      }
    }
  }

  private var webpageBlock: some View {
    if let url = webpageURL {
      SignalASIWebPagePreviewView(
        url: url,
        title: block.title,
        fallbackText: block.fallbackText.ifBlank(block.uri)
      )
    } else {
      resourceBlock
    }
  }

  private var videoBlock: some View {
    if let url = mediaURL {
      SignalASIVideoArtifactView(
        url: url,
        title: block.title.isEmpty ? t("rich_output_type_video", "Video") : block.title
      )
    } else {
      resourceBlock
    }
  }

  private var galleryBlock: some View {
    let items = galleryImageItems
    VStack(alignment: .leading, spacing: 8) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
      }
      if items.isEmpty {
        imageBlock
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(items) { item in
              SignalASIImageThumbnailView(item: item) {
                imageViewerItem = item
              }
            }
          }
          .padding(.vertical, 1)
        }
        .fullScreenCover(item: $imageViewerItem) { item in
          SignalASIImageLightboxView(item: item)
        }
      }
    }
  }

  private var chartBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
      }
      SignalASIRichBarChartView(columns: block.columns, rows: block.rows)
        .accessibilityLabel(String(format: t("rich_output_chart_description", "Chart with %d data points"), block.rows.count))
    }
  }

  private var statusBlock: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: statusIcon)
        .font(.caption.weight(.semibold))
        .foregroundColor(statusColor)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 2) {
        selectableText(firstNonEmpty([block.title, block.text, t("rich_output_progress", "Progress")]))
          .font(.subheadline.weight(.semibold))
        if !block.fallbackText.isEmpty {
          selectableText(block.fallbackText)
            .font(.caption)
            .foregroundColor(.signalASITextSecondary)
        }
      }
    }
    .padding(9)
    .background(statusColor.opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var progressBlock: some View {
    let clamped = min(max(block.value, 0), block.maximum)
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        selectableText(firstNonEmpty([block.title, block.text, t("rich_output_progress", "Progress")]))
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 8)
        Text("\(Int((Double(clamped) / Double(max(block.maximum, 1)) * 100).rounded()))%")
          .font(.caption.weight(.semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      ProgressView(value: Double(clamped), total: Double(max(block.maximum, 1)))
        .accentColor(.signalASIAccent)
    }
    .padding(9)
    .background(Color.signalASISearchBackground.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var metricBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(firstNonEmpty([block.title, block.metadata["label"] ?? "", t("rich_output_type_data", "Data")]))
        .font(.caption.weight(.semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(firstNonEmpty([block.text, block.metadata["value"] ?? "", "\(block.value)"]))
        .font(.title3.weight(.bold))
        .foregroundColor(.signalASITextPrimary)
        .minimumScaleFactor(0.75)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var toolBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .font(.caption.weight(.semibold))
          .foregroundColor(.signalASIAccent)
        Text(firstNonEmpty([block.title, block.metadata["tool"] ?? "", t("rich_output_type_code", "Code")]))
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.signalASITextPrimary)
      }
      if !block.text.isEmpty {
        selectableText(block.text)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(9)
    .background(Color.signalASISearchBackground.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var timelineBlock: some View {
    let rows = block.rows.isEmpty ? listRows.map { [$0] } : block.rows
    return VStack(alignment: .leading, spacing: 8) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
      }
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(Color.signalASIAccent)
            .frame(width: 7, height: 7)
            .padding(.top, 5)
          VStack(alignment: .leading, spacing: 2) {
            if let first = row.first, row.count > 1 {
              Text(first)
                .font(.caption.weight(.semibold))
                .foregroundColor(.signalASITextSecondary)
              selectableText(row.dropFirst().joined(separator: " "))
            } else {
              selectableText(row.joined(separator: " "))
            }
          }
        }
      }
    }
  }

  private var noticeBlock: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "info.circle")
        .foregroundColor(.signalASIInsightText)
      selectableText(displayText)
        .foregroundColor(.signalASIInsightText)
    }
    .padding(9)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var approvalBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "checkmark.seal")
          .foregroundColor(.signalASIAccent)
        selectableText(firstNonEmpty([block.title, t("rich_output_input_required", "Input required")]))
          .font(.subheadline.weight(.semibold))
      }
      if !block.text.isEmpty {
        selectableText(block.text)
          .foregroundColor(.signalASITextSecondary)
      }
      actionsBlock(title: "")
    }
    .padding(9)
    .background(Color.signalASIAccent.opacity(0.10))
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASIAccent.opacity(0.25), lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var formBlock: some View {
    VStack(alignment: .leading, spacing: 9) {
      selectableText(firstNonEmpty([block.title, t("rich_output_input_required", "Input required")]))
        .font(.subheadline.weight(.semibold))
      if !block.text.isEmpty {
        selectableText(block.text)
          .foregroundColor(.signalASITextSecondary)
      }
      ForEach(block.fields) { field in
        VStack(alignment: .leading, spacing: 4) {
          Text(field.required ? "\(field.label) *" : field.label)
            .font(.caption.weight(.semibold))
            .foregroundColor(.signalASITextSecondary)
          inputField(field)
        }
      }
      Button {
        onFormSubmit(block, submittedFormValues)
      } label: {
        Text(block.actions.first?.label ?? t("rich_output_submit", "Submit"))
          .font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .padding(.horizontal, 10)
          .background(formMissingRequired ? Color.signalASIButtonSoft : Color.signalASIAccent)
          .foregroundColor(formMissingRequired ? .signalASITextSecondary : .white)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(formMissingRequired)
      .accessibilityHint(formMissingRequired ? t("rich_output_complete_required", "Complete required fields") : "")
    }
    .padding(9)
    .background(Color.signalASISurface.opacity(isOutgoing ? 0.75 : 1))
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var resourceBlock: some View {
    if isDesktopArtifact {
      desktopArtifactBlock
    } else {
      SignalASIRichResourceRow(
        icon: resourceIcon,
        title: resourceTitle,
        subtitle: resourceSubtitle,
        url: SignalASIRichContentLink.safeURL(block.uri),
        typeLabel: resourceTypeLabel
      )
    }
  }

  private var desktopArtifactBlock: some View {
    let available = coordinator.desktopArtifactStore.localFile(for: block) != nil
    return VStack(alignment: .leading, spacing: 8) {
      SignalASIRichResourceRow(
        icon: "doc.richtext",
        title: resourceTitle,
        subtitle: resourceSubtitle,
        url: nil,
        typeLabel: resourceTypeLabel
      )
      HStack(spacing: 8) {
        if available {
          Button {
            onArtifactSave(block)
          } label: {
            Label(t("rich_output_save", "Save to Files"), systemImage: "square.and.arrow.down")
              .font(.caption.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 32)
          }
          .buttonStyle(.borderedProminent)
        } else {
          Button {
            Task { _ = await coordinator.requestDesktopArtifactDownload(block: block) }
          } label: {
            Label(t("rich_output_download", "Download"), systemImage: "arrow.down.circle")
              .font(.caption.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 32)
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private var isDesktopArtifact: Bool {
    let sourceURI = block.metadata["artifact_source_uri"] ?? block.uri
    return block.isArtifactBlock && AgentDesktopArtifactStore.isSignalASIArtifactURI(sourceURI)
  }

  private func actionsBlock(title: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if !title.isEmpty {
        selectableText(title)
          .font(.subheadline.weight(.semibold))
      }
      if !block.text.isEmpty && block.type == .actions {
        selectableText(block.text)
          .foregroundColor(.signalASITextSecondary)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
        ForEach(block.actions) { action in
          Button {
            onAction(action)
          } label: {
            Text(action.label)
              .font(.caption.weight(.semibold))
              .lineLimit(2)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity, minHeight: 34)
              .padding(.horizontal, 8)
              .background(actionBackground(action))
              .foregroundColor(actionForeground(action))
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func inputField(_ field: AgentRichField) -> some View {
    if field.inputType == "password" {
      SecureField(field.label, text: binding(for: field))
        .textFieldStyle(.roundedBorder)
    } else if !field.options.isEmpty {
      Picker(field.label, selection: binding(for: field)) {
        ForEach(field.options, id: \.self) { option in
          Text(option).tag(option)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      TextField(field.label, text: binding(for: field))
        .textFieldStyle(.roundedBorder)
        .keyboardType(field.inputType == "number" ? .numbersAndPunctuation : .default)
    }
  }

  private func tableRow(_ values: [String], header: Bool, columnCount: Int, rowIndex: Int) -> some View {
    HStack(spacing: 0) {
      ForEach(0..<columnCount, id: \.self) { index in
        let value = index < values.count ? values[index] : ""
        Text(value)
          .font(header ? .caption.weight(.semibold) : .caption)
          .foregroundColor(.signalASITextPrimary)
          .textSelection(.enabled)
          .multilineTextAlignment(isNumeric(value) && !header ? .trailing : .leading)
          .frame(width: 112, alignment: isNumeric(value) && !header ? .trailing : .leading)
          .padding(.horizontal, 8)
          .padding(.vertical, 7)
          .background(header ? Color.signalASISearchBackground : rowColor(rowIndex))
      }
    }
  }

  private func previewPlaceholder(_ text: String) -> some View {
    HStack(spacing: 8) {
      ProgressView()
      Text(text)
        .font(.caption)
        .foregroundColor(.signalASITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
    .background(Color.signalASISearchBackground.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private func selectableText(_ text: String) -> Text {
    Text(text)
      .font(.body)
  }

  private func copyCode(_ value: String) {
    UIPasteboard.general.string = value
    withAnimation(.easeInOut(duration: 0.12)) {
      copiedCode = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      withAnimation(.easeInOut(duration: 0.12)) {
        copiedCode = false
      }
    }
  }

  private func binding(for field: AgentRichField) -> Binding<String> {
    Binding(
      get: {
        formValues[field.id] ?? field.value
      },
      set: { next in
        formValues[field.id] = next
      }
    )
  }

  private var submittedFormValues: [String: String] {
    Dictionary(uniqueKeysWithValues: block.fields.map { field in
      (field.id, (formValues[field.id] ?? field.value).trimmingCharacters(in: .whitespacesAndNewlines))
    })
  }

  private var formMissingRequired: Bool {
    block.fields.contains { field in
      field.required && (formValues[field.id] ?? field.value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var listRows: [String] {
    if !block.rows.isEmpty {
      return block.rows.map { $0.joined(separator: " ") }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    return block.text
      .components(separatedBy: .newlines)
      .map { line in
        line.trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
      }
      .filter { !$0.isEmpty }
  }

  private var keyValuePairs: [(key: String, value: String)] {
    if !block.rows.isEmpty {
      let rowPairs = block.rows.compactMap { row -> (String, String)? in
        guard let key = row.first, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (key, row.dropFirst().joined(separator: " "))
      }
      if !rowPairs.isEmpty {
        return rowPairs
      }
    }
    return block.metadata
      .sorted { $0.key < $1.key }
      .map { ($0.key, $0.value) }
  }

  private var tableColumnCount: Int {
    max(1, block.columns.count, block.rows.map(\.count).max() ?? 0)
  }

  private var inlineImageData: Data? {
    SignalASIImageResourceDecoder.base64Data(block.dataB64)
  }

  private var localImageData: Data? {
    guard let url = localURL else { return nil }
    return SignalASIImageResourceDecoder.fileData(url)
  }

  private var localURL: URL? {
    guard let url = URL(string: block.uri), url.isFileURL else { return nil }
    return url
  }

  private var mediaURL: URL? {
    guard let url = URL(string: block.uri),
          ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
      return nil
    }
    return url
  }

  private var webpageURL: URL? {
    guard let url = URL(string: block.uri),
          url.scheme?.lowercased() == "https",
          url.host?.isBlank == false else {
      return nil
    }
    return url
  }

  private var remoteURL: URL? {
    guard block.type == .image || block.type == .gallery,
          let url = SignalASIRichContentLink.safeURL(block.uri),
          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      return nil
    }
    return url
  }

  private var galleryImageItems: [SignalASIImageViewerItem] {
    var items: [SignalASIImageViewerItem] = []
    let primaryData = inlineImageData ?? localImageData
    let primaryURL = primaryData == nil ? imageURL(for: block.uri) : nil
    if let primary = makeImageViewerItem(
      data: primaryData,
      url: primaryURL,
      id: "\(block.id)-primary",
      title: block.title
    ) {
      items.append(primary)
    }

    for (index, row) in block.rows.enumerated() {
      let title = row.first?.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(
        "\(t("rich_output_type_image", "Image")) \(index + 1)"
      ) ?? "\(t("rich_output_type_image", "Image")) \(index + 1)"
      let rawURL = row.dropFirst().first ?? ""
      guard let url = imageURL(for: rawURL) else { continue }
      let data = url.isFileURL ? try? Data(contentsOf: url) : nil
      let remote = data == nil && !url.isFileURL ? url : nil
      if let item = makeImageViewerItem(
        data: data,
        url: remote,
        id: "\(block.id)-gallery-\(index)",
        title: title
      ) {
        items.append(item)
      }
    }
    return Array(items.prefix(12))
  }

  private func makeImageViewerItem(
    data: Data?,
    url: URL?,
    id: String,
    title: String
  ) -> SignalASIImageViewerItem? {
    guard data != nil || url != nil else { return nil }
    return SignalASIImageViewerItem(
      id: id,
      data: data,
      url: url,
      title: title.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  private func imageURL(for raw: String) -> URL? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: clean),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "file"].contains(scheme) else {
      return nil
    }
    return url
  }

  private var codeLabel: String {
    let type = block.type == .json ? "json" : block.type.rawValue
    return firstNonEmpty([block.title, block.language, type]).lowercased()
  }

  private var resourceTitle: String {
    firstNonEmpty([
      block.title,
      block.fallbackText,
      AgentRichFormatRegistry.fileName(block),
      resourceTypeLabel
    ])
  }

  private var resourceSubtitle: String {
    firstNonEmpty([block.text, block.uri, block.mimeType])
  }

  private var resourceTypeLabel: String {
    switch block.type {
    case .image, .gallery:
      return t("rich_output_type_image", "Image")
    case .video:
      return t("rich_output_type_video", "Video")
    case .audio:
      return t("rich_output_type_audio", "Audio")
    case .link, .webpage, .html:
      return t("rich_output_type_web", "Web")
    case .citation:
      return t("rich_output_section_evidence", "Evidence")
    case .file:
      return t("rich_output_type_file", "File")
    default:
      return t("rich_output_type_file", "File")
    }
  }

  private var resourceIcon: String {
    switch block.type {
    case .image, .gallery:
      return "photo"
    case .video:
      return "play.rectangle"
    case .audio:
      return "waveform"
    case .link, .webpage, .html:
      return "safari"
    case .citation:
      return "quote.bubble"
    default:
      return "doc"
    }
  }

  private var statusIcon: String {
    let normalized = firstNonEmpty([block.metadata["status"] ?? "", block.text, block.title]).lowercased()
    if normalized.contains("fail") || normalized.contains("error") {
      return "xmark.circle.fill"
    }
    if normalized.contains("complete") || normalized.contains("success") || normalized.contains("done") {
      return "checkmark.circle.fill"
    }
    return "clock.fill"
  }

  private var statusColor: Color {
    let normalized = firstNonEmpty([block.metadata["status"] ?? "", block.text, block.title]).lowercased()
    if normalized.contains("fail") || normalized.contains("error") {
      return .red
    }
    if normalized.contains("complete") || normalized.contains("success") || normalized.contains("done") {
      return .signalASIAccent
    }
    return .orange
  }

  private func actionBackground(_ action: AgentRichAction) -> Color {
    switch action.style.lowercased() {
    case "destructive", "danger":
      return Color.red.opacity(0.14)
    case "primary", "confirm":
      return Color.signalASIAccent
    default:
      return Color.signalASIButtonSoft
    }
  }

  private func actionForeground(_ action: AgentRichAction) -> Color {
    switch action.style.lowercased() {
    case "primary", "confirm":
      return .white
    case "destructive", "danger":
      return .red
    default:
      return .signalASITextPrimary
    }
  }

  private func rowColor(_ index: Int) -> Color {
    index.isMultiple(of: 2) ? Color.signalASISurface : Color.signalASISearchBackground.opacity(0.35)
  }

  private func isNumeric(_ value: String) -> Bool {
    Double(value.replacingOccurrences(of: ",", with: "")) != nil
  }

  private func firstNonEmpty(_ values: [String]) -> String {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private static let collapsedCodeLines = 12
  private static let visibleTableRows = 6
}

private struct SignalASIRichResourceRow: View {
  var icon: String
  var title: String
  var subtitle: String
  var url: URL?
  var typeLabel: String

  var body: some View {
    Group {
      if let url {
        Link(destination: url) {
          rowBody
        }
      } else {
        rowBody
      }
    }
    .buttonStyle(.plain)
  }

  private var rowBody: some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.signalASIAccent)
        .frame(width: 28, height: 28)
        .background(Color.signalASIAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(title.isEmpty ? typeLabel : title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
            .truncationMode(.middle)
        }
      }
      Spacer(minLength: 8)
      if url != nil {
        Image(systemName: "arrow.up.right.square")
          .font(.caption.weight(.semibold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(9)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

private struct SignalASIRichBarChartView: View {
  var columns: [String]
  var rows: [[String]]

  private var points: [SignalASIRichChartPoint] {
    rows.prefix(Self.maxPoints).compactMap { row in
      let values = row.dropFirst().compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
      guard !values.isEmpty else { return nil }
      return SignalASIRichChartPoint(label: row.first ?? "", values: Array(values.prefix(Self.maxSeries)))
    }
  }

  private var maximum: Double {
    max(1, points.flatMap(\.values).map { abs($0) }.max() ?? 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      if columns.dropFirst().count > 1 {
        HStack(spacing: 10) {
          ForEach(Array(columns.dropFirst().prefix(Self.maxSeries).enumerated()), id: \.offset) { index, label in
            HStack(spacing: 4) {
              Circle()
                .fill(seriesColor(index))
                .frame(width: 7, height: 7)
              Text(label)
                .font(.caption2)
                .foregroundColor(.signalASITextSecondary)
                .lineLimit(1)
            }
          }
        }
      }

      ForEach(Array(points.enumerated()), id: \.offset) { _, point in
        HStack(spacing: 8) {
          Text(point.label)
            .font(.caption2)
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
            .frame(width: 58, alignment: .leading)
          GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
              ForEach(Array(point.values.enumerated()), id: \.offset) { valueIndex, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                  .fill(seriesColor(valueIndex))
                  .frame(width: max(3, proxy.size.width * CGFloat(min(abs(value) / maximum, 1))), height: 12)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(height: 14)
          Text(point.values.map { SignalASIRichContentLink.numberFormatter.string(from: NSNumber(value: $0)) ?? "\($0)" }.joined(separator: " / "))
            .font(.caption2)
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
            .frame(width: 54, alignment: .trailing)
        }
      }
    }
    .padding(10)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private func seriesColor(_ index: Int) -> Color {
    Self.seriesColors[index % Self.seriesColors.count]
  }

  private static let maxPoints = 24
  private static let maxSeries = 4
  private static let seriesColors: [Color] = [
    .signalASIAccent,
    .blue,
    .orange,
    .purple
  ]
}

private struct SignalASIInlineHTMLView: UIViewRepresentable {
  let html: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptEnabled = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    let coordinator = context.coordinator
    let webView = SignalASIRichHTMLWebView(frame: .zero, configuration: configuration)
    coordinator.webView = webView
    webView.onFocus = { [weak coordinator] in coordinator?.focusIfVisible() }
    webView.onDetach = { [weak coordinator] in coordinator?.deactivate() }
    webView.navigationDelegate = coordinator
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.scrollView.alwaysBounceVertical = false
    webView.scrollView.alwaysBounceHorizontal = false
    context.coordinator.loadedHTML = html
    webView.loadHTMLString(Self.isolatedDocument(html), baseURL: nil)
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    guard context.coordinator.loadedHTML != html else { return }
    context.coordinator.loadedHTML = html
    context.coordinator.deactivate()
    webView.loadHTMLString(Self.isolatedDocument(html), baseURL: nil)
  }

  private static func isolatedDocument(_ fragment: String) -> String {
    """
    <!doctype html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5,user-scalable=yes">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; media-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; frame-src 'none'; font-src data:; form-action 'none'; base-uri 'none'">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; min-height: 100%; overflow: auto; background: transparent; color: #14202B; font-family: -apple-system, BlinkMacSystemFont, sans-serif; touch-action: pan-x pan-y pinch-zoom; }
          * { box-sizing: border-box; max-width: 100%; }
          @media (prefers-color-scheme: dark) { html, body { color: #F3F5F7; } }
        </style>
      </head>
      <body>
        (fragment.prefix(32_000))
      </body>
    </html>
    """
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    var loadedHTML: String?
    weak var webView: WKWebView?

    func focusIfVisible() {
      guard let webView, webView.window != nil else { return }
      SignalASIRichHTMLPlaybackCoordinator.shared.activate(webView)
    }

    func deactivate() {
      guard let webView else { return }
      SignalASIRichHTMLPlaybackCoordinator.shared.deactivate(webView)
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      SignalASIRichHTMLPlaybackCoordinator.shared.sync(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      SignalASIRichHTMLPlaybackCoordinator.shared.sync(webView)
    }

    deinit {
      deactivate()
    }
  }
}

private struct SignalASIAudioArtifactView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @StateObject private var player: SignalASIAudioArtifactPlayer
  let url: URL
  let title: String

  init(url: URL, title: String) {
    self.url = url
    self.title = title
    _player = StateObject(wrappedValue: SignalASIAudioArtifactPlayer(url: url))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "waveform")
          .foregroundColor(.signalASIAccent)
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Spacer(minLength: 8)
        Button {
          player.togglePlayback()
        } label: {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.signalASIAccent))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
          .accessibilityLabel(
            SignalASILocalization.string(
              player.isPlaying ? "rich_output_pause" : "rich_output_play",
              fallback: player.isPlaying
                ? (interfaceLanguage.hasPrefix("zh") ? "暂停" : "Pause")
                : (interfaceLanguage.hasPrefix("zh") ? "播放" : "Play"),
              language: interfaceLanguage
            )
          )
      }
      Slider(
        value: Binding(
          get: { player.currentTime },
          set: { player.seek(to: $0) }
        ),
        in: 0...max(player.duration, 1)
      )
      HStack {
        Text(formatTime(player.currentTime))
        Spacer()
        Text(formatTime(player.duration))
      }
      .font(.caption2.monospacedDigit())
      .foregroundColor(.signalASITextSecondary)
    }
    .padding(10)
    .background(Color.signalASISearchBackground.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .onDisappear {
      player.stop()
    }
  }

  private func formatTime(_ value: TimeInterval) -> String {
    let totalSeconds = max(0, Int(value.rounded()))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}

private final class SignalASIAudioArtifactPlayer: NSObject, ObservableObject {
  @Published private(set) var isPlaying = false
  @Published private(set) var currentTime: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0

  private let url: URL
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  init(url: URL) {
    self.url = url
    super.init()
  }

  func togglePlayback() {
    if isPlaying {
      SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
      pauseForCoordinator()
      return
    }
    do {
      if player == nil {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let audioPlayer = AVPlayer(url: url)
        player = audioPlayer
        installObservers(for: audioPlayer)
      }
      SignalASIRichMediaPlaybackCoordinator.shared.activate(owner: self) { [weak self] in
        self?.pauseForCoordinator()
      }
      player?.play()
      isPlaying = true
    } catch {
      SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
      player = nil
      duration = 0
      currentTime = 0
    }
  }

  func seek(to value: TimeInterval) {
    let resolved = min(max(0, value), max(duration, 0))
    player?.seek(to: CMTime(seconds: resolved, preferredTimescale: 600))
    currentTime = resolved
  }

  func stop() {
    SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
    player?.pause()
    player?.seek(to: .zero)
    currentTime = 0
    isPlaying = false
    removeObservers()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  deinit {
    SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
    removeObservers()
  }

  private func installObservers(for player: AVPlayer) {
    let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      guard let self else { return }
      self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
      if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
        self.duration = seconds
      }
    }
    if let item = player.currentItem {
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.finishPlayback()
      }
    }
  }

  private func finishPlayback() {
    SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
    currentTime = 0
    isPlaying = false
    player?.seek(to: .zero)
  }

  private func pauseForCoordinator() {
    player?.pause()
    isPlaying = false
    stopTimer()
  }

  private func removeObservers() {
    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }
}

private struct SignalASIVideoArtifactView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @StateObject private var player: SignalASIVideoArtifactPlayer
  let title: String

  init(url: URL, title: String) {
    self.title = title
    _player = StateObject(wrappedValue: SignalASIVideoArtifactPlayer(url: url))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !title.isEmpty {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(.signalASITextPrimary)
      }
      VideoPlayer(player: player.player)
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel(title.isEmpty
          ? SignalASILocalization.string("rich_output_type_video", fallback: "Video", language: interfaceLanguage)
          : title)
    }
    .onDisappear {
      player.stop()
    }
  }
}

private final class SignalASIVideoArtifactPlayer: ObservableObject {
  let player: AVPlayer
  private var playbackObservation: NSKeyValueObservation? = nil

  init(url: URL) {
    player = AVPlayer(url: url)
    installPlaybackObservation()
  }

  private func installPlaybackObservation() {
    playbackObservation = player.observe(
      \.timeControlStatus,
      options: [.initial, .new]
    ) { [weak self] player, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        if player.timeControlStatus == .playing {
          SignalASIRichMediaPlaybackCoordinator.shared.activate(owner: self) { [weak self] in
            self?.pauseForCoordinator()
          }
        } else {
          SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
        }
      }
    }
  }

  func stop() {
    SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
    player.pause()
    player.seek(to: .zero)
  }

  private func pauseForCoordinator() {
    player.pause()
  }

  deinit {
    playbackObservation?.invalidate()
    SignalASIRichMediaPlaybackCoordinator.shared.deactivate(owner: self)
  }
}

private struct SignalASIArtifactDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

private struct SignalASIRichChartPoint {
  var label: String
  var values: [Double]
}

private enum SignalASIRichContentLink {
  static func safeURL(_ raw: String) -> URL? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: clean),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "mailto", "tel"].contains(scheme) else {
      return nil
    }
    return url
  }

  static let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    formatter.numberStyle = .decimal
    return formatter
  }()
}
