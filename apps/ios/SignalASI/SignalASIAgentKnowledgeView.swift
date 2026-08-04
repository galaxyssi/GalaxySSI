import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct SignalASIAgentKnowledgeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var searchText = ""
  @State private var activeQuery = ""
  @State private var searchHits: [AgentKnowledgeHit] = []
  @State private var showingImporter = false
  @State private var showingSearch = false
  @State private var selectedGroup: AgentKnowledgeSourceGroup?
  @State private var statusText = ""

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent_knowledge.title", "Knowledge"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button {
            showingImporter = true
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 21, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentKnowledgeHeroView(
            title: t("signalasi.agent_knowledge.hero_title", "Private knowledge"),
            subtitle: t(
              "signalasi.agent_knowledge.hero_subtitle",
              "Encrypted retrieval with governed model and Agent access"
            ),
            badge: String(
              format: t("signalasi.agent_knowledge.source_badge", "%d sources"),
              store.agentKnowledgeStats.sourceCount
            )
          )

          sectionTitle(t("signalasi.agent_knowledge.section_actions", "RETRIEVE AND IMPORT"))
          VStack(spacing: 8) {
            AgentKnowledgeActionRow(
              title: t("signalasi.agent_knowledge.import", "Import source"),
              subtitle: t(
                "signalasi.agent_knowledge.import_subtitle",
                "PDF, Word, Markdown, text, JSON, or another readable document"
              ),
              systemImage: "doc.text",
              tint: .signalASIAccent,
              badge: t("signalasi.agent_knowledge.add", "Add")
            ) {
              showingImporter = true
            }
            AgentKnowledgeActionRow(
              title: t("signalasi.agent_knowledge.search", "Search knowledge"),
              subtitle: activeQuery.ifBlank(t(
                "signalasi.agent_knowledge.search_subtitle",
                "Hybrid phrase, keyword, and semantic similarity retrieval"
              )),
              systemImage: "magnifyingglass",
              tint: .blue,
              badge: t("signalasi.agent_knowledge.search_action", "Search")
            ) {
              showingSearch = true
            }
          }

          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 12))
              .foregroundColor(.signalASITextSecondary)
              .padding(.horizontal, 4)
          }

          if !activeQuery.isEmpty {
            sectionTitle(String(
              format: t("signalasi.agent_knowledge.section_results", "RESULTS / %d"),
              searchHits.count
            ))
            if searchHits.isEmpty {
              AgentKnowledgeInfoRow(
                title: t("signalasi.agent_knowledge.no_results", "No matching knowledge"),
                subtitle: activeQuery,
                systemImage: "magnifyingglass",
                tint: .blue,
                badge: ""
              )
            } else {
              VStack(spacing: 8) {
                ForEach(searchHits.indices, id: \.self) { index in
                  let hit = searchHits[index]
                  AgentKnowledgeInfoRow(
                    title: "[\(index + 1)] \(displayTitle(hit.item.title))",
                    subtitle: hit.excerpt,
                    systemImage: "book",
                    tint: .signalASIAccent,
                    badge: String(
                      format: t("signalasi.agent_knowledge.score", "%.1f score"),
                      hit.score
                    )
                  )
                }
              }
            }
          }

          let groups = store.agentKnowledgeSourceGroups()
          sectionTitle(String(
            format: t("signalasi.agent_knowledge.section_sources", "SOURCES / %d"),
            groups.count
          ))
          if groups.isEmpty {
            AgentKnowledgeInfoRow(
              title: t("signalasi.agent_knowledge.empty_title", "No private sources yet"),
              subtitle: t(
                "signalasi.agent_knowledge.empty_subtitle",
                "Import a source to make it available to the on-device Agent."
              ),
              systemImage: "book",
              tint: .signalASIAccent,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(groups) { group in
                AgentKnowledgeActionRow(
                  title: group.title,
                  subtitle: String(
                    format: t("signalasi.agent_knowledge.source_subtitle", "%d chunks / Cloud: %@ / Agents: %@"),
                    group.chunkCount,
                    cloudAccessLabel(group.cloudAccess),
                    agentAccessLabel(group.agentAccess)
                  ),
                  systemImage: "book",
                  tint: .signalASIAccent,
                  badge: t("signalasi.agent_knowledge.manage", "Manage")
                ) {
                  selectedGroup = group
                }
              }
            }
          }

          let audit = Array(store.agentKnowledgeAccessAudit.suffix(8).reversed())
          if !audit.isEmpty {
            sectionTitle(t("signalasi.agent_knowledge.section_audit", "RECENT KNOWLEDGE ACCESS"))
            VStack(spacing: 8) {
              ForEach(audit) { entry in
                AgentKnowledgeInfoRow(
                  title: entry.targetId,
                  subtitle: String(
                    format: t("signalasi.agent_knowledge.audit_subtitle", "%d sources / %@ / %d blocked matches"),
                    entry.sourceCount,
                    evidenceModeSummary(entry.evidenceModes),
                    entry.blockedMatchCount
                  ),
                  systemImage: "lock.shield",
                  tint: .orange,
                  badge: auditTime(entry.timestampMillis)
                )
              }
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
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      importFiles(result)
    }
    .sheet(isPresented: $showingSearch) {
      AgentKnowledgeSearchSheet(initialQuery: searchText) { query in
        runSearch(query)
      }
    }
    .sheet(item: $selectedGroup) { group in
      AgentKnowledgeSourceAccessSheet(group: group) { message in
        statusText = message
      }
      .environmentObject(store)
    }
  }

  private func importFiles(_ result: Result<[URL], Error>) {
    do {
      let urls = try result.get()
      var importedChunks = 0
      for url in urls {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }
        let text = try extractText(from: url)
        importedChunks += store.importAgentKnowledge(
          title: url.lastPathComponent.ifBlank(t("signalasi.agent_knowledge.title", "Knowledge")),
          content: text,
          source: url.absoluteString,
          kind: knowledgeKind(for: url),
          tags: knowledgeTags(for: url)
        ).count
      }
      statusText = String(
        format: t("signalasi.agent_knowledge.imported_count", "Imported %d chunks into Agent knowledge"),
        importedChunks
      )
      if !activeQuery.isEmpty {
        runSearch(activeQuery)
      }
    } catch {
      statusText = String(
        format: t("signalasi.agent_knowledge.import_failed", "Import failed: %@"),
        error.localizedDescription
      )
    }
  }

  private func runSearch(_ query: String) {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    searchText = cleanQuery
    activeQuery = cleanQuery
    searchHits = store.searchAgentKnowledge(cleanQuery)
    store.recordAgentKnowledgeSearch(query: cleanQuery, hits: searchHits)
  }

  private func extractText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let pathExtension = url.pathExtension.lowercased()
    let text: String
    switch pathExtension {
    case "pdf":
      text = try extractPDFText(data)
    case "docx":
      text = try AgentOfficeDocumentExtractor.extractDocx(data)
    case "xlsx":
      text = try AgentOfficeDocumentExtractor.extractXlsx(data)
    case "pptx":
      text = try AgentOfficeDocumentExtractor.extractPptx(data)
    default:
      text = try extractPlainText(data)
    }
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      throw NSError(
        domain: "SignalASIAgentKnowledgeImport",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: t(
            "signalasi.agent_knowledge.no_readable_text",
            "No readable text found in this document"
          )
        ]
      )
    }
    return clean
  }

  private func extractPDFText(_ data: Data) throws -> String {
    guard let document = PDFDocument(data: data) else {
      throw NSError(
        domain: "SignalASIAgentKnowledgeImport",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "PDF could not be opened"]
      )
    }
    let pages = (0..<document.pageCount).compactMap { index in
      document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    return pages.joined(separator: "\n\n")
  }

  private func extractPlainText(_ data: Data) throws -> String {
    if let text = String(data: data, encoding: .utf8), isReadable(text) {
      return text
    }
    if let text = String(data: data, encoding: .utf16), isReadable(text) {
      return text
    }
    let lossy = String(decoding: data.prefix(512_000), as: UTF8.self)
    guard isReadable(lossy) else {
      throw NSError(
        domain: "SignalASIAgentKnowledgeImport",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: t(
            "signalasi.agent_knowledge.no_readable_text",
            "No readable text found in this document"
          )
        ]
      )
    }
    return lossy
  }

  private func isReadable(_ value: String) -> Bool {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let sample = clean.prefix(2_000)
    let badScalars = sample.unicodeScalars.filter { $0.value == 0 || $0.value == 0xfffd }.count
    return badScalars < max(5, sample.count / 8)
  }

  private func knowledgeKind(for url: URL) -> AgentKnowledgeKind {
    switch url.pathExtension.lowercased() {
    case "txt", "md", "markdown":
      return .note
    default:
      return .document
    }
  }

  private func knowledgeTags(for url: URL) -> [String] {
    let ext = url.pathExtension.lowercased()
    return ext.isEmpty ? ["ios_import"] : ["ios_import", ext]
  }

  private func cloudAccessLabel(_ value: AgentKnowledgeCloudAccess) -> String {
    switch value {
    case .deny:
      return t("signalasi.agent_knowledge.access_local_only", "Blocked")
    case .summaryOnly:
      return t("signalasi.agent_knowledge.access_summary", "Summary only")
    case .full:
      return t("signalasi.agent_knowledge.access_full", "Full evidence")
    }
  }

  private func agentAccessLabel(_ value: AgentKnowledgeAgentAccess) -> String {
    switch value {
    case .localOnly:
      return t("signalasi.agent_knowledge.agent_local_only", "Local only")
    case .selectedAgents:
      return t("signalasi.agent_knowledge.agent_selected", "Selected Agents")
    case .anyPairedAgent:
      return t("signalasi.agent_knowledge.agent_any", "Any paired Agent")
    }
  }

  private func evidenceModeSummary(_ modes: [AgentKnowledgeEvidenceMode]) -> String {
    let labels = modes.map { mode -> String in
      switch mode {
      case .full:
        return t("signalasi.agent_knowledge.access_full", "Full evidence")
      case .summary:
        return t("signalasi.agent_knowledge.access_summary", "Summary only")
      }
    }
    return labels.isEmpty ? t("signalasi.common.none", "None") : labels.joined(separator: " / ")
  }

  private func auditTime(_ millis: Int64) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private func displayTitle(_ title: String) -> String {
    title
      .replacingOccurrences(of: "\\s+\\[[0-9]+/[0-9]+\\]$", with: "", options: .regularExpression)
      .ifBlank(t("signalasi.agent_knowledge.title", "Knowledge"))
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

private struct AgentKnowledgeSearchSheet: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  var onSearch: (String) -> Void

  init(initialQuery: String, onSearch: @escaping (String) -> Void) {
    _query = State(initialValue: initialQuery)
    self.onSearch = onSearch
  }

  var body: some View {
    NavigationView {
      Form {
        Section(t("signalasi.agent_knowledge.search", "Search knowledge")) {
          TextField(t("signalasi.agent_knowledge.search_subtitle", "Hybrid phrase, keyword, and semantic similarity retrieval"), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
        }
      }
      .navigationTitle(t("signalasi.agent_knowledge.search", "Search knowledge"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("signalasi.agent_knowledge.search_action", "Search")) {
            onSearch(query)
            dismiss()
          }
          .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentKnowledgeSourceAccessSheet: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  let group: AgentKnowledgeSourceGroup
  var onStatus: (String) -> Void
  @State private var cloudAccess: AgentKnowledgeCloudAccess
  @State private var agentAccess: AgentKnowledgeAgentAccess
  @State private var allowedAgentIds: String

  init(group: AgentKnowledgeSourceGroup, onStatus: @escaping (String) -> Void) {
    self.group = group
    self.onStatus = onStatus
    _cloudAccess = State(initialValue: group.cloudAccess)
    _agentAccess = State(initialValue: group.agentAccess)
    _allowedAgentIds = State(initialValue: group.allowedAgentIds.joined(separator: ", "))
  }

  var body: some View {
    NavigationView {
      Form {
        Section(group.title) {
          Text(String(
            format: t("signalasi.agent_knowledge.source_metadata", "%d chunks / %@"),
            group.chunkCount,
            group.source
          ))
          .font(.caption)
          .foregroundColor(.secondary)
        }
        Section(t("signalasi.agent_knowledge.cloud_access", "Cloud model access")) {
          Picker(t("signalasi.agent_knowledge.cloud_access", "Cloud model access"), selection: $cloudAccess) {
            ForEach(AgentKnowledgeCloudAccess.allCases) { policy in
              Text(cloudAccessLabel(policy)).tag(policy)
            }
          }
        }
        Section(t("signalasi.agent_knowledge.agent_access", "Paired Agent access")) {
          Picker(t("signalasi.agent_knowledge.agent_access", "Paired Agent access"), selection: $agentAccess) {
            ForEach(AgentKnowledgeAgentAccess.allCases) { policy in
              Text(agentAccessLabel(policy)).tag(policy)
            }
          }
          if agentAccess == .selectedAgents {
            TextField(t("signalasi.agent_knowledge.selected_agents", "Allowed Agent IDs"), text: $allowedAgentIds)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled(true)
          }
        }
        Section {
          Button(role: .destructive) {
            let deleted = store.deleteAgentKnowledgeSource(itemIds: group.itemIds)
            onStatus(String(format: t("signalasi.agent_knowledge.source_deleted", "Deleted %d chunks"), deleted))
            dismiss()
          } label: {
            Label(t("signalasi.agent_knowledge.delete_source", "Delete Source"), systemImage: "trash")
          }
        }
      }
      .navigationTitle(t("signalasi.agent_knowledge.manage", "Manage"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("signalasi.common.save", "Save")) {
            save()
          }
        }
      }
    }
  }

  private func save() {
    let ids = agentAccess == .selectedAgents
      ? allowedAgentIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      : []
    let updated = store.updateAgentKnowledgeSourceAccess(
      itemIds: group.itemIds,
      cloudAccess: cloudAccess,
      agentAccess: agentAccess,
      allowedAgentIds: ids
    )
    onStatus(String(format: t("signalasi.agent_knowledge.source_updated", "Updated %d chunks"), updated))
    dismiss()
  }

  private func cloudAccessLabel(_ value: AgentKnowledgeCloudAccess) -> String {
    switch value {
    case .deny:
      return t("signalasi.agent_knowledge.access_local_only", "Blocked")
    case .summaryOnly:
      return t("signalasi.agent_knowledge.access_summary", "Summary only")
    case .full:
      return t("signalasi.agent_knowledge.access_full", "Full evidence")
    }
  }

  private func agentAccessLabel(_ value: AgentKnowledgeAgentAccess) -> String {
    switch value {
    case .localOnly:
      return t("signalasi.agent_knowledge.agent_local_only", "Local only")
    case .selectedAgents:
      return t("signalasi.agent_knowledge.agent_selected", "Selected Agents")
    case .anyPairedAgent:
      return t("signalasi.agent_knowledge.agent_any", "Any paired Agent")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentKnowledgeHeroView: View {
  var title: String
  var subtitle: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.signalASIAccent.opacity(0.16))
        Image(systemName: "book")
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.signalASIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct AgentKnowledgeActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      AgentKnowledgeRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsChevron: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct AgentKnowledgeInfoRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    AgentKnowledgeRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsChevron: false
    )
  }
}

private struct AgentKnowledgeRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsChevron: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.14))
        Image(systemName: systemImage)
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(3)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
