import Foundation
import CoreFoundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct GalaxySSIAgentKnowledgeView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var searchText = ""
  @State private var activeQuery = ""
  @State private var searchHits: [AgentKnowledgeHit] = []
  @State private var showingImporter = false
  @State private var showingWebImporter = false
  @State private var showingSearch = false
  @State private var selectedGroup: AgentKnowledgeSourceGroup?
  @State private var statusText = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.agent_knowledge.title", "Knowledge"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button {
            showingImporter = true
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 21, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentKnowledgeHeroView(
            title: t("galaxyssi.agent_knowledge.hero_title", "Private knowledge"),
            subtitle: t(
              "galaxyssi.agent_knowledge.hero_subtitle",
              "Encrypted retrieval with governed model and Agent access"
            ),
            badge: String(
              format: t("galaxyssi.agent_knowledge.source_badge", "%d sources"),
              store.agentKnowledgeStats.sourceCount
            )
          )

          sectionTitle(t("galaxyssi.agent_knowledge.section_actions", "RETRIEVE AND IMPORT"))
          VStack(spacing: 8) {
            AgentKnowledgeActionRow(
              title: t("galaxyssi.agent_knowledge.import", "Import source"),
              subtitle: t(
                "galaxyssi.agent_knowledge.import_subtitle",
                "PDF, Word, Markdown, text, JSON, images, or another readable document"
              ),
              systemImage: "doc.text",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.agent_knowledge.add", "Add")
            ) {
              showingImporter = true
            }
            AgentKnowledgeActionRow(
              title: t("galaxyssi.agent_knowledge.import_web", "Import web page"),
              subtitle: t(
                "galaxyssi.agent_knowledge.import_web_subtitle",
                "Fetch a public HTTP or HTTPS page into private Agent knowledge"
              ),
              systemImage: "globe",
              tint: .orange,
              badge: t("galaxyssi.agent_knowledge.import_web_action", "Web")
            ) {
              showingWebImporter = true
            }
            AgentKnowledgeActionRow(
              title: t("galaxyssi.agent_knowledge.search", "Search knowledge"),
              subtitle: activeQuery.ifBlank(t(
                "galaxyssi.agent_knowledge.search_subtitle",
                "Hybrid phrase, keyword, and semantic similarity retrieval"
              )),
              systemImage: "magnifyingglass",
              tint: .blue,
              badge: t("galaxyssi.agent_knowledge.search_action", "Search")
            ) {
              showingSearch = true
            }
          }

          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
              .padding(.horizontal, 4)
          }

          if !activeQuery.isEmpty {
            sectionTitle(String(
              format: t("galaxyssi.agent_knowledge.section_results", "RESULTS / %d"),
              searchHits.count
            ))
            if searchHits.isEmpty {
              AgentKnowledgeInfoRow(
                title: t("galaxyssi.agent_knowledge.no_results", "No matching knowledge"),
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
                    tint: .galaxySSIAccent,
                    badge: String(
                      format: t("galaxyssi.agent_knowledge.score", "%.1f score"),
                      hit.score
                    )
                  )
                }
              }
            }
          }

          let groups = store.agentKnowledgeSourceGroups()
          sectionTitle(String(
            format: t("galaxyssi.agent_knowledge.section_sources", "SOURCES / %d"),
            groups.count
          ))
          if groups.isEmpty {
            AgentKnowledgeInfoRow(
              title: t("galaxyssi.agent_knowledge.empty_title", "No private sources yet"),
              subtitle: t(
                "galaxyssi.agent_knowledge.empty_subtitle",
                "Import a source to make it available to the on-device Agent."
              ),
              systemImage: "book",
              tint: .galaxySSIAccent,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(groups) { group in
                AgentKnowledgeActionRow(
                  title: group.title,
                  subtitle: String(
                    format: t("galaxyssi.agent_knowledge.source_subtitle", "%d chunks / Cloud: %@ / Agents: %@"),
                    group.chunkCount,
                    cloudAccessLabel(group.cloudAccess),
                    agentAccessLabel(group.agentAccess)
                  ),
                  systemImage: "book",
                  tint: .galaxySSIAccent,
                  badge: t("galaxyssi.agent_knowledge.manage", "Manage")
                ) {
                  selectedGroup = group
                }
              }
            }
          }

          let audit = Array(store.agentKnowledgeAccessAudit.suffix(8).reversed())
          if !audit.isEmpty {
            sectionTitle(t("galaxyssi.agent_knowledge.section_audit", "RECENT KNOWLEDGE ACCESS"))
            VStack(spacing: 8) {
              ForEach(audit) { entry in
                AgentKnowledgeInfoRow(
                  title: entry.targetId,
                  subtitle: String(
                    format: t("galaxyssi.agent_knowledge.audit_subtitle", "%d sources / %@ / %d blocked matches"),
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
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
    .sheet(isPresented: $showingWebImporter) {
      AgentKnowledgeWebImportSheet { value in
        importWebPage(value)
      }
      .environment(\.galaxySSIInterfaceLanguage, interfaceLanguage)
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
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > AgentKnowledgeImportPolicy.maxSourceBytes {
          throw importError(t(
            "galaxyssi.agent_knowledge.import_too_large",
            "Document exceeds the 20 MB import limit"
          ))
        }
        let text = try extractText(from: url)
        let assessment = AgentKnowledgeImportPolicy.assess(text)
        guard assessment.isAllowed else {
          throw importError(t(
            "galaxyssi.agent_knowledge.import_sensitive",
            "Import blocked because the source appears to contain secrets"
          ))
        }
        importedChunks += store.importAgentKnowledge(
          title: url.lastPathComponent.ifBlank(t("galaxyssi.agent_knowledge.title", "Knowledge")),
          content: assessment.indexedContent,
          source: url.absoluteString,
          kind: knowledgeKind(for: url),
          tags: knowledgeTags(for: url)
        ).count
      }
      statusText = String(
        format: t("galaxyssi.agent_knowledge.imported_count", "Imported %d chunks into Agent knowledge"),
        importedChunks
      )
      if !activeQuery.isEmpty {
        runSearch(activeQuery)
      }
    } catch {
      statusText = String(
        format: t("galaxyssi.agent_knowledge.import_failed", "Import failed: %@"),
        error.localizedDescription
      )
    }
  }

  private func importWebPage(_ value: String) {
    statusText = t("galaxyssi.agent_knowledge.import_web_loading", "Fetching web page...")
    Task { @MainActor in
      do {
        let url = try normalizedWebURL(value)
        let request = URLRequest(
          url: url,
          cachePolicy: .reloadIgnoringLocalCacheData,
          timeoutInterval: 12
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard data.count <= AgentKnowledgeImportPolicy.maxWebBytes else {
          throw webImportError(
            t("galaxyssi.agent_knowledge.import_web_too_large", "Web page exceeds the 5 MB import limit")
          )
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
          throw webImportError(String(
            format: t("galaxyssi.agent_knowledge.import_web_http_error", "Web page returned HTTP %d"),
            httpResponse.statusCode
          ))
        }
        let mimeType = response.mimeType?.lowercased() ?? "text/html"
        guard Self.supportedWebMimeTypes.contains(mimeType) else {
          throw webImportError(String(
            format: t("galaxyssi.agent_knowledge.import_web_type_error", "Unsupported web content type: %@"),
            mimeType
          ))
        }
        let body = decodeWebBody(data, response: response)
        let title = webPageTitle(body).ifBlank(url.host?.ifBlank("Web page") ?? "Web page")
        let text = try extractWebText(body)
        let assessment = AgentKnowledgeImportPolicy.assess(text)
        guard assessment.isAllowed else {
          throw webImportError(t(
            "galaxyssi.agent_knowledge.import_sensitive",
            "Import blocked because the source appears to contain secrets"
          ))
        }
        let imported = store.replaceAgentKnowledgeSource(
          title: String(title.prefix(180)),
          content: assessment.indexedContent,
          source: url.absoluteString,
          kind: .document,
          tags: ["web", url.host ?? ""]
        )
        guard !imported.isEmpty else {
          throw webImportError(t(
            "galaxyssi.agent_knowledge.no_readable_text",
            "No readable text found in this web page"
          ))
        }
        statusText = String(
          format: t("galaxyssi.agent_knowledge.imported_web", "Imported %@ as %d knowledge chunks"),
          title,
          imported.count
        )
        if !activeQuery.isEmpty {
          runSearch(activeQuery)
        }
      } catch {
        statusText = String(
          format: t("galaxyssi.agent_knowledge.import_failed", "Import failed: %@"),
          error.localizedDescription
        )
      }
    }
  }

  private func normalizedWebURL(_ value: String) throws -> URL {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      throw webImportError(t("galaxyssi.agent_knowledge.import_web_invalid", "Enter a valid web page URL"))
    }
    let candidate = raw.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil
      ? "https://\(raw)"
      : raw
    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          let host = url.host?.lowercased(),
          !host.isEmpty,
          url.user == nil,
          !isPrivateWebHost(host) else {
      throw webImportError(t(
        "galaxyssi.agent_knowledge.import_web_invalid",
        "Only public HTTP and HTTPS web pages can be imported"
      ))
    }
    return url
  }

  private func isPrivateWebHost(_ host: String) -> Bool {
    if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") {
      return true
    }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    guard octets.count == 4 else {
      return host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
    }
    let first = octets[0]
    let second = octets[1]
    return first == 0 || first == 10 || first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && (16...31).contains(second)) ||
      (first == 192 && second == 168)
  }

  private func decodeWebBody(_ data: Data, response: URLResponse) -> String {
    if let encoding = response.textEncodingName {
      let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encoding as CFString)
      if cfEncoding != kCFStringEncodingInvalidId {
        let stringEncoding = String.Encoding(rawValue: UInt(cfEncoding))
        if let value = String(data: data, encoding: stringEncoding) {
          return value
        }
      }
    }
    return String(decoding: data, as: UTF8.self)
  }

  private func webPageTitle(_ html: String) -> String {
    guard let match = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) else {
      return ""
    }
    let title = String(html[match])
      .replacingOccurrences(of: "^<title[^>]*>|</title>$", with: "", options: [.regularExpression, .caseInsensitive])
    return htmlToPlainText(title).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractWebText(_ html: String) throws -> String {
    let withoutNonContent = html
      .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "<noscript[^>]*>[\\s\\S]*?</noscript>", with: " ", options: [.regularExpression, .caseInsensitive])
    let text = htmlToPlainText(withoutNonContent)
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n{3,}", with: "\\n\\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw webImportError(t("galaxyssi.agent_knowledge.no_readable_text", "No readable text found in this web page"))
    }
    return String(text.prefix(Self.maximumExtractedWebCharacters))
  }

  private func htmlToPlainText(_ html: String) -> String {
    let withBreaks = html
      .replacingOccurrences(of: "<br\\s*/?>", with: "\\n", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "</(p|div|li|h[1-6]|tr|section|article)>", with: "\\n", options: [.regularExpression, .caseInsensitive])
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    if let data = withBreaks.data(using: .utf8),
       let attributed = try? NSAttributedString(
         data: data,
         options: [
           .documentType: NSAttributedString.DocumentType.html,
           .characterEncoding: String.Encoding.utf8.rawValue
         ],
         documentAttributes: nil
       ) {
      return attributed.string
    }
    return withBreaks
  }

  private func webImportError(_ message: String) -> NSError {
    NSError(domain: "GalaxySSIAgentKnowledgeWebImport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func importError(_ message: String) -> NSError {
    NSError(domain: "GalaxySSIAgentKnowledgeImport", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private static let maximumExtractedWebCharacters = AgentKnowledgeImportPolicy.maxExtractedCharacters
  private static let supportedWebMimeTypes: Set<String> = ["text/html", "application/xhtml+xml", "text/plain"]

  private func runSearch(_ query: String) {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    searchText = cleanQuery
    activeQuery = cleanQuery
    searchHits = store.searchAgentKnowledge(cleanQuery)
    store.recordAgentKnowledgeSearch(query: cleanQuery, hits: searchHits)
  }

  private func extractText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    guard data.count <= AgentKnowledgeImportPolicy.maxSourceBytes else {
      throw importError(t(
        "galaxyssi.agent_knowledge.import_too_large",
        "Document exceeds the 20 MB import limit"
      ))
    }
    let pathExtension = url.pathExtension.lowercased()
    let text: String
    switch pathExtension {
    case "png", "jpg", "jpeg", "webp", "bmp", "gif", "heic", "heif", "tif", "tiff":
      text = try extractImageText(data, url: url)
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
        domain: "GalaxySSIAgentKnowledgeImport",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: t(
            "galaxyssi.agent_knowledge.no_readable_text",
            "No readable text found in this document"
          )
        ]
      )
    }
    return clean
  }

  private func extractImageText(_ data: Data, url: URL) throws -> String {
    let maximumBytes = Int(AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes)
    guard data.count <= maximumBytes else {
      throw NSError(
        domain: "GalaxySSIAgentKnowledgeImport",
        code: 5,
        userInfo: [
          NSLocalizedDescriptionKey: t(
            "galaxyssi.agent_knowledge.image_ocr_too_large",
            "Image exceeds the 12 MB OCR limit"
          )
        ]
      )
    }
    let content = AgentIOSWebMediaContent(
      contentURI: url.absoluteString,
      contentType: "image/\(url.pathExtension.lowercased())",
      displayName: url.lastPathComponent,
      data: data
    )
    let request = AgentIOSWebMediaOCRRequest(
      contentURI: url.absoluteString,
      sourceKind: "document",
      scriptHint: "auto",
      maxSourceBytes: AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes,
      timeoutMillis: AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis
    )
    do {
      return try AgentIOSVisionTextOCRRecognizer()
        .recognize(content: content, request: request)
        .text
    } catch {
      throw NSError(
        domain: "GalaxySSIAgentKnowledgeImport",
        code: 6,
        userInfo: [
          NSLocalizedDescriptionKey: String(
            format: t(
              "galaxyssi.agent_knowledge.image_ocr_failed",
              "Image OCR failed: %@"
            ),
            error.localizedDescription
          )
        ]
      )
    }
  }

  private func extractPDFText(_ data: Data) throws -> String {
    guard let document = PDFDocument(data: data) else {
      throw NSError(
        domain: "GalaxySSIAgentKnowledgeImport",
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
        domain: "GalaxySSIAgentKnowledgeImport",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: t(
            "galaxyssi.agent_knowledge.no_readable_text",
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
      return t("galaxyssi.agent_knowledge.access_local_only", "Blocked")
    case .summaryOnly:
      return t("galaxyssi.agent_knowledge.access_summary", "Summary only")
    case .full:
      return t("galaxyssi.agent_knowledge.access_full", "Full evidence")
    }
  }

  private func agentAccessLabel(_ value: AgentKnowledgeAgentAccess) -> String {
    switch value {
    case .localOnly:
      return t("galaxyssi.agent_knowledge.agent_local_only", "Local only")
    case .selectedAgents:
      return t("galaxyssi.agent_knowledge.agent_selected", "Selected Agents")
    case .anyPairedAgent:
      return t("galaxyssi.agent_knowledge.agent_any", "Any paired Agent")
    }
  }

  private func evidenceModeSummary(_ modes: [AgentKnowledgeEvidenceMode]) -> String {
    let labels = modes.map { mode -> String in
      switch mode {
      case .full:
        return t("galaxyssi.agent_knowledge.access_full", "Full evidence")
      case .summary:
        return t("galaxyssi.agent_knowledge.access_summary", "Summary only")
      }
    }
    return labels.isEmpty ? t("galaxyssi.common.none", "None") : labels.joined(separator: " / ")
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
      .ifBlank(t("galaxyssi.agent_knowledge.title", "Knowledge"))
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentKnowledgeSearchSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
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
        Section(t("galaxyssi.agent_knowledge.search", "Search knowledge")) {
          TextField(t("galaxyssi.agent_knowledge.search_subtitle", "Hybrid phrase, keyword, and semantic similarity retrieval"), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
        }
      }
      .navigationTitle(t("galaxyssi.agent_knowledge.search", "Search knowledge"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.agent_knowledge.search_action", "Search")) {
            onSearch(query)
            dismiss()
          }
          .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentKnowledgeWebImportSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var url = ""
  var onImport: (String) -> Void

  var body: some View {
    NavigationView {
      Form {
        Section(t("galaxyssi.agent_knowledge.import_web", "Import web page")) {
          TextField(
            t("galaxyssi.agent_knowledge.import_web_placeholder", "https://example.com/page"),
            text: $url
          )
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          Text(t(
            "galaxyssi.agent_knowledge.import_web_hint",
            "Only public HTTP and HTTPS pages up to 5 MB are imported."
          ))
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
      .navigationTitle(t("galaxyssi.agent_knowledge.import_web", "Import web page"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.agent_knowledge.import_web_action", "Import")) {
            onImport(url)
            dismiss()
          }
          .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentKnowledgeSourceAccessSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
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
            format: t("galaxyssi.agent_knowledge.source_metadata", "%d chunks / %@"),
            group.chunkCount,
            group.source
          ))
          .font(.caption)
          .foregroundColor(.secondary)
        }
        Section(t("galaxyssi.agent_knowledge.cloud_access", "Cloud model access")) {
          Picker(t("galaxyssi.agent_knowledge.cloud_access", "Cloud model access"), selection: $cloudAccess) {
            ForEach(AgentKnowledgeCloudAccess.allCases) { policy in
              Text(cloudAccessLabel(policy)).tag(policy)
            }
          }
        }
        Section(t("galaxyssi.agent_knowledge.agent_access", "Paired Agent access")) {
          Picker(t("galaxyssi.agent_knowledge.agent_access", "Paired Agent access"), selection: $agentAccess) {
            ForEach(AgentKnowledgeAgentAccess.allCases) { policy in
              Text(agentAccessLabel(policy)).tag(policy)
            }
          }
          if agentAccess == .selectedAgents {
            TextField(t("galaxyssi.agent_knowledge.selected_agents", "Allowed Agent IDs"), text: $allowedAgentIds)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled(true)
          }
        }
        Section {
          Button(role: .destructive) {
            let deleted = store.deleteAgentKnowledgeSource(itemIds: group.itemIds)
            onStatus(String(format: t("galaxyssi.agent_knowledge.source_deleted", "Deleted %d chunks"), deleted))
            dismiss()
          } label: {
            Label(t("galaxyssi.agent_knowledge.delete_source", "Delete Source"), systemImage: "trash")
          }
        }
      }
      .navigationTitle(t("galaxyssi.agent_knowledge.manage", "Manage"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.cancel", "Cancel")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("galaxyssi.common.save", "Save")) {
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
    onStatus(String(format: t("galaxyssi.agent_knowledge.source_updated", "Updated %d chunks"), updated))
    dismiss()
  }

  private func cloudAccessLabel(_ value: AgentKnowledgeCloudAccess) -> String {
    switch value {
    case .deny:
      return t("galaxyssi.agent_knowledge.access_local_only", "Blocked")
    case .summaryOnly:
      return t("galaxyssi.agent_knowledge.access_summary", "Summary only")
    case .full:
      return t("galaxyssi.agent_knowledge.access_full", "Full evidence")
    }
  }

  private func agentAccessLabel(_ value: AgentKnowledgeAgentAccess) -> String {
    switch value {
    case .localOnly:
      return t("galaxyssi.agent_knowledge.agent_local_only", "Local only")
    case .selectedAgents:
      return t("galaxyssi.agent_knowledge.agent_selected", "Selected Agents")
    case .anyPairedAgent:
      return t("galaxyssi.agent_knowledge.agent_any", "Any paired Agent")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
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
          .fill(Color.galaxySSIAccent.opacity(0.16))
        Image(systemName: "book")
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.galaxySSIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
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
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
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
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
