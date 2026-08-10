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
  var expansionStorageKey: String = ""
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
                  expansionStorageKey: expansionStorageKey,
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
  var expansionStorageKey: String
  var isOutgoing: Bool
  var onAction: (AgentRichAction) -> Void
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void
  var onArtifactSave: (AgentRichBlock) -> Void

  @State private var expanded: Bool

  init(
    section: AgentResponseSection,
    expansionStorageKey: String = "",
    isOutgoing: Bool,
    onAction: @escaping (AgentRichAction) -> Void,
    onFormSubmit: @escaping (AgentRichBlock, [String: String]) -> Void,
    onArtifactSave: @escaping (AgentRichBlock) -> Void
  ) {
    self.section = section
    self.expansionStorageKey = expansionStorageKey
    self.isOutgoing = isOutgoing
    self.onAction = onAction
    self.onFormSubmit = onFormSubmit
    self.onArtifactSave = onArtifactSave
    let storageKey = expansionStorageKey.isEmpty
      ? ""
      : "\(expansionStorageKey):\(section.kind.rawValue)"
    _expanded = State(
      initialValue: AgentResponseSectionExpansionStore.shared.state(for: storageKey)
        ?? section.expandedByDefault
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          expanded.toggle()
          AgentResponseSectionExpansionStore.shared.set(expanded, for: expansionKey)
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

  private var expansionKey: String {
    guard !expansionStorageKey.isEmpty else { return "" }
    return "\(expansionStorageKey):\(section.kind.rawValue)"
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
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        SignalASIRichBlockView(
          block: block,
          isOutgoing: isOutgoing,
          onAction: onAction,
          onFormSubmit: onFormSubmit,
          onArtifactSave: onArtifactSave
        )
        .padding(.top, index == 0 ? 0 : Self.blockSpacing(for: block))
      }
    }
  }

  private static func blockSpacing(for block: AgentRichBlock) -> CGFloat {
    switch block.type {
    case .heading:
      return 12
    case .divider:
      return 10
    case .text, .list, .quote:
      return 6
    default:
      return 10
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
        .frame(maxWidth: UIScreen.main.bounds.width * Self.approvalWidthRatio, alignment: .leading)
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
    let values = listItems
    return VStack(alignment: .leading, spacing: 5) {
      ForEach(Array(values.prefix(Self.visibleListItems).enumerated()), id: \.offset) { _, item in
        HStack(alignment: .top, spacing: 7) {
          Text(listMarkerLabel(item.marker))
            .foregroundColor(item.marker.lowercased() == "checked" ? .signalASIAccent : .signalASITextSecondary)
            .frame(width: 24, alignment: .trailing)
          selectableText(item.text)
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
    let pairs = Array(keyValuePairs.prefix(Self.visibleTableRows))
    return VStack(alignment: .leading, spacing: 0) {
      if !block.title.isEmpty {
        selectableText(block.title)
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 12)
          .padding(.top, 10)
          .padding(.bottom, 7)
      }
      ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
        HStack(alignment: .center, spacing: 0) {
          Text(pair.key)
            .font(.caption.weight(.semibold))
            .foregroundColor(.signalASITextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          selectableText(pair.value)
            .font(.subheadline)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
    let hasNumbers = block.rows.contains { row in
      row.dropFirst().contains { isNumeric($0) }
    }
    if hasNumbers {
      return AnyView(
        VStack(alignment: .leading, spacing: 8) {
          if !block.title.isEmpty {
            selectableText(block.title)
              .font(.subheadline.weight(.semibold))
          }
          SignalASIRichBarChartView(columns: block.columns, rows: block.rows)
            .accessibilityLabel(String(format: t("rich_output_chart_description", "Chart with %d data points"), block.rows.count))
        }
      )
    } else {
      return AnyView(tableBlock)
    }
  }

  private var statusBlock: some View {
    HStack(spacing: 8) {
      Image(systemName: "terminal")
        .font(.caption.weight(.semibold))
        .foregroundColor(.signalASITextSecondary)
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
      Text(statusText)
        .font(.caption)
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 30)
  }

  private var progressBlock: some View {
    let clamped = min(max(block.value, 0), block.maximum)
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        selectableText(firstNonEmpty([block.title, block.text, t("rich_output_progress", "Progress")]))
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 8)
        Text(block.value < 0
          ? "--"
          : "\(Int((Double(clamped) / Double(max(block.maximum, 1)) * 100).rounded()))%")
          .font(.caption.weight(.semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      if block.value < 0 {
        ProgressView()
          .frame(maxWidth: .infinity, alignment: .leading)
          .accentColor(.signalASIAccent)
      } else {
        ProgressView(value: Double(clamped), total: Double(max(block.maximum, 1)))
          .accentColor(.signalASIAccent)
      }
    }
    .padding(9)
    .background(Color.signalASISearchBackground.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var metricBlock: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(firstNonEmpty([block.text, block.metadata["value"] ?? "", "\(block.value)"]))
        .font(.title2.weight(.bold))
        .foregroundColor(.signalASITextPrimary)
        .minimumScaleFactor(0.75)
      Text(firstNonEmpty([block.title, block.metadata["label"] ?? "", t("rich_output_type_data", "Data")]))
        .font(.caption)
        .foregroundColor(.signalASITextSecondary)
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
    statusBlock
  }

  private var timelineBlock: some View {
    let rows = Array(
      (block.rows.isEmpty ? listRows.map { [$0] } : block.rows)
        .prefix(Self.visibleTimelineItems)
    )
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
    let palette = noticePalette
    return HStack(alignment: .top, spacing: 8) {
      Rectangle()
        .fill(palette.accent)
        .frame(width: 4)
      VStack(alignment: .leading, spacing: 2) {
        if !block.title.isEmpty {
          selectableText(block.title)
            .font(.subheadline.weight(.semibold))
        }
        if !block.text.isEmpty {
          selectableText(block.text)
            .font(.caption)
        }
        if block.title.isEmpty && block.text.isEmpty {
          selectableText(displayText)
            .font(.caption)
        }
      }
      .foregroundColor(palette.text)
    }
    .padding(9)
    .background(palette.background)
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(palette.accent.opacity(0.65), lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private var noticePalette: (background: Color, accent: Color, text: Color) {
    switch (block.metadata["style"]?.lowercased()) {
    case "success":
      return (.signalASIInsightBackground, .signalASIAccent, .signalASIInsightText)
    case "warning":
      return (Color.orange.opacity(0.12), .orange, .orange)
    case "error":
      return (Color.red.opacity(0.10), .red, .red)
    default:
      return (Color.blue.opacity(0.10), .blue, .blue)
    }
  }

  private var approvalBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "lock.shield")
          .foregroundColor(.signalASIAccent)
          .frame(width: 24, height: 24)
        selectableText(firstNonEmpty([block.title, t("rich_output_input_required", "Input required")]))
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 4)
        if !block.fallbackText.isEmpty {
          Text(block.fallbackText)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.signalASIButtonSoft)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
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
      let hasPriorityAction = block.actions.contains {
        ["preview_runtime_artifact", "save_runtime_artifact"].contains($0.verb)
      }
      VStack(alignment: .leading, spacing: 8) {
        SignalASIRichResourceRow(
          icon: resourceIcon,
          title: resourceTitle,
          subtitle: resourceSubtitle,
          url: hasPriorityAction ? nil : SignalASIRichContentLink.safeURL(block.uri),
          typeLabel: resourceTypeLabel
        )
        if !block.actions.isEmpty {
          resourceActionButtons(block.actions)
        }
      }
    }
  }

  private func resourceActionButtons(_ actions: [AgentRichAction]) -> some View {
    let columnCount = actions.count > 2 ? 2 : max(actions.count, 1)
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount),
      alignment: .leading,
      spacing: 8
    ) {
      ForEach(actions) { action in
        Button {
          onAction(action)
        } label: {
          Label(action.label, systemImage: resourceActionIcon(action))
            .font(.caption.weight(.semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, 8)
            .background(actionBackground(action))
            .foregroundColor(actionForeground(action))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func resourceActionIcon(_ action: AgentRichAction) -> String {
    switch action.verb.lowercased() {
    case "preview_runtime_artifact":
      return "eye"
    case "save_runtime_artifact":
      return "square.and.arrow.down"
    default:
      return "bolt"
    }
  }

  private var desktopArtifactBlock: some View {
    let available = coordinator.desktopArtifactStore.localFile(for: block) != nil
    let previewActions = block.actions.filter { $0.verb == "preview_runtime_artifact" }
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
      if !previewActions.isEmpty {
        resourceActionButtons(previewActions)
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
      let columnCount = block.actions.count > 2 ? 2 : max(block.actions.count, 1)
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount),
        alignment: .leading,
        spacing: 8
      ) {
        ForEach(block.actions) { action in
          Button {
            onAction(action)
          } label: {
            Text(action.label)
              .font(.caption.weight(.semibold))
              .lineLimit(2)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity, minHeight: 42)
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
    let inputType = field.inputType.lowercased()
    if inputType == "password" {
      SecureField("", text: binding(for: field))
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(Text(field.label))
    } else if inputType == "boolean" || inputType == "checkbox" {
      Toggle("", isOn: booleanBinding(for: field))
        .labelsHidden()
        .accessibilityLabel(Text(field.label))
    } else if !field.options.isEmpty || ["select", "choice", "enum"].contains(inputType) {
      let choices = field.options.isEmpty
        ? [field.value].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        : field.options
      Picker("", selection: binding(for: field)) {
        if choices.isEmpty {
          Text("").tag("")
        } else {
          ForEach(choices, id: \.self) { option in
            Text(option).tag(option)
          }
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel(Text(field.label))
    } else if inputType == "multiline" || inputType == "textarea" {
      TextEditor(text: binding(for: field))
        .frame(minHeight: 80, maxHeight: 140)
        .padding(4)
        .background(Color.signalASISearchBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel(Text(field.label))
    } else {
      TextField("", text: binding(for: field))
        .textFieldStyle(.roundedBorder)
        .keyboardType(keyboardType(for: inputType))
        .accessibilityLabel(Text(field.label))
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
    var attributed = AttributedString("")
    for segment in AgentInlineMarkdown.parse(text) {
      var fragment = AttributedString(segment.text)
      switch segment.style {
      case .bold:
        fragment.inlinePresentationIntent = .stronglyEmphasized
      case .italic:
        fragment.inlinePresentationIntent = .emphasized
      case .strike:
        fragment.inlinePresentationIntent = .strikethrough
      case .code:
        fragment.inlinePresentationIntent = .code
      case .link:
        if let url = URL(string: segment.url) {
          fragment.link = url
        }
        fragment.foregroundColor = Color.signalASIAccent
        fragment.underlineStyle = .single
      case .normal:
        break
      }
      attributed.append(fragment)
    }
    return Text(attributed)
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

  private func booleanBinding(for field: AgentRichField) -> Binding<Bool> {
    Binding(
      get: {
        ["true", "1", "yes", "on"].contains(
          (formValues[field.id] ?? field.value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
      },
      set: { next in
        formValues[field.id] = next ? "true" : "false"
      }
    )
  }

  private func keyboardType(for inputType: String) -> UIKeyboardType {
    switch inputType {
    case "email":
      return .emailAddress
    case "phone":
      return .phonePad
    case "integer":
      return .numberPad
    case "number", "decimal":
      return .decimalPad
    default:
      return .default
    }
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

  private var listItems: [(marker: String, text: String)] {
    if !block.rows.isEmpty {
      return block.rows.compactMap { row in
        guard let marker = row.first else { return nil }
        let text = row.dropFirst().joined(separator: " ")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (marker: marker.ifBlank("bullet"), text: text)
      }
    }
    return block.text
      .components(separatedBy: .newlines)
      .compactMap { parseListItem($0) }
  }

  private func parseListItem(_ line: String) -> (marker: String, text: String)? {
    let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    if let range = clean.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
      let prefix = String(clean[..<range.upperBound])
      let marker = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
      return (marker: marker, text: String(clean[range.upperBound...]))
    }
    if clean.range(of: #"^[-+*]\s+\[[ xX]\]\s*"#, options: .regularExpression) != nil {
      let checked = clean.range(of: #"^[-+*]\s+\[[xX]\]"#, options: .regularExpression) != nil
      let text = clean.replacingOccurrences(
        of: #"^[-+*]\s+\[[ xX]\]\s*"#,
        with: "",
        options: .regularExpression
      )
      return (marker: checked ? "checked" : "unchecked", text: text)
    }
    if let range = clean.range(of: #"^[-+*]\s+"#, options: .regularExpression) {
      return (marker: "bullet", text: String(clean[range.upperBound...]))
    }
    return (marker: "bullet", text: clean)
  }

  private func listMarkerLabel(_ marker: String) -> String {
    switch marker.lowercased() {
    case "checked": return "✓"
    case "unchecked": return "○"
    case "bullet": return "•"
    default: return marker.hasSuffix(".") ? marker : "\(marker)."
    }
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
    return Array(items.prefix(Self.visibleGalleryItems))
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

  private var statusText: String {
    let values = [block.title, block.text].filter {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return values.joined(separator: " · ").ifBlank(block.fallbackText)
  }

  private func actionBackground(_ action: AgentRichAction) -> Color {
    if isPermissionConfirmation(action) {
      return Color.signalASIAccent.opacity(0.12)
    }
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
    if isPermissionConfirmation(action) {
      return .signalASIAccent
    }
    switch action.style.lowercased() {
    case "primary", "confirm":
      return .white
    case "destructive", "danger":
      return .red
    default:
      return .signalASITextPrimary
    }
  }

  private func isPermissionConfirmation(_ action: AgentRichAction) -> Bool {
    guard ["decide_task_permission", "decide_remote_task_permission"].contains(action.verb) else {
      return false
    }
    let denied = action.value == AgentPermissionChoice.denyAlways.wireValue ||
      action.value.contains("\"decision_scope\":\"\(AgentPermissionChoice.denyAlways.wireValue)\"")
    return !denied
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

  private static let collapsedCodeLines = 28
  private static let visibleListItems = 100
  private static let visibleTableRows = 12
  private static let approvalWidthRatio: CGFloat = 0.78
  private static let visibleGalleryItems = 10
  private static let visibleTimelineItems = 50
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
  @State private var reveal: CGFloat = 0

  private var points: [SignalASIRichChartPoint] {
    rows.prefix(Self.maxPoints).compactMap { row in
      let values = row.dropFirst().compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }
      guard !values.isEmpty else { return nil }
      return SignalASIRichChartPoint(label: row.first ?? "", values: Array(values.prefix(Self.maxSeries)))
    }
  }

  private var seriesCount: Int {
    points.max { $0.values.count < $1.values.count }?.values.count ?? 1
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
      Canvas { context, size in
        drawChart(&context, size: size)
      }
      .frame(height: 230)
      .onAppear {
        withAnimation(.easeOut(duration: 0.42)) {
          reveal = 1
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

  private func drawChart(_ context: inout GraphicsContext, size: CGSize) {
    guard !points.isEmpty else { return }

    let left: CGFloat = 12
    let right = max(left + 1, size.width - 12)
    let top: CGFloat = 18
    let bottom = max(top + 1, size.height - 34)
    let chartHeight = max(1, bottom - top)
    let allValues = points.flatMap(\.values)
    let minimum = min(0, allValues.min() ?? 0)
    let maximum = max(0, allValues.max() ?? 0)
    let range = max(1, maximum - minimum)

    var grid = Path()
    for step in 0...4 {
      let y = top + chartHeight * CGFloat(step) / 4
      grid.move(to: CGPoint(x: left, y: y))
      grid.addLine(to: CGPoint(x: right, y: y))
    }
    context.stroke(grid, with: .color(Color.signalASISeparator), lineWidth: 1)

    let groupWidth = (right - left) / CGFloat(max(points.count, 1))
    let gap: CGFloat = 2
    let barWidth = max(1, (groupWidth * 0.72 - gap * CGFloat(seriesCount - 1)) / CGFloat(seriesCount))
    let zeroY = bottom - CGFloat((0 - minimum) / range) * chartHeight

    for (pointIndex, point) in points.enumerated() {
      let groupStart = left + CGFloat(pointIndex) * groupWidth + groupWidth * 0.14
      for (seriesIndex, value) in point.values.enumerated() {
        let x = groupStart + CGFloat(seriesIndex) * (barWidth + gap)
        let valueY = bottom - CGFloat((value - minimum) / range) * chartHeight
        let animatedY = zeroY + (valueY - zeroY) * reveal
        let rect = CGRect(
          x: x,
          y: min(zeroY, animatedY),
          width: barWidth,
          height: max(1, abs(animatedY - zeroY))
        )
        context.fill(
          Path(roundedRect: rect, cornerRadius: 3),
          with: .color(seriesColor(seriesIndex))
        )
      }

      if pointIndex % labelStride(points.count) == 0 {
        let label = String(point.label.prefix(12))
        context.draw(
          Text(label)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary),
          at: CGPoint(x: left + CGFloat(pointIndex) * groupWidth + groupWidth / 2, y: size.height - 12),
          anchor: .center
        )
      }
    }
  }

  private func labelStride(_ count: Int) -> Int {
    if count <= 6 { return 1 }
    if count <= 12 { return 2 }
    return 3
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
