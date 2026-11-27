import SwiftUI

@MainActor
struct GalaxySSIPublicNewsEventButton: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let event: PublicNewsEvent
  var showsExcerpt = true
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 4) {
        if showsExcerpt, let excerpt = event.newExcerpt {
          Text(excerpt.source + ": " + excerpt.text)
            .font(.footnote).foregroundColor(.galaxySSITextPrimary).lineLimit(2)
        }
        HStack(spacing: 6) {
          Image(systemName: "newspaper")
          Text(String(format: t("public_news_event_reports", "%d sources"), event.sources))
          if event.newCount > 0 {
            Text(String(format: t("public_news_event_new_count", "+%d since last read"), event.newCount))
          }
          Image(systemName: "chevron.right").font(.caption)
        }
        .font(.footnote).foregroundColor(.galaxySSIAccent)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("ios.news.event.open")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIPublicNewsEventView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var archive: PublicNewsArchive
  let event: PublicNewsEvent

  var body: some View {
    NavigationView {
      List(event.reports) { report in
        NavigationLink {
          GalaxySSIPublicNewsCachedReportView(archive: archive, report: report)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(report.source).font(.subheadline.weight(.semibold))
              if event.arrivedSinceRead(report) {
                Text(t("public_news_event_new", "New")).font(.caption).foregroundColor(.galaxySSIAccent)
              }
            }
            if let date = report.article.publishedAt {
              HStack {
                Text(date, style: .date)
                Text(date, style: .time)
              }
              .font(.caption).foregroundColor(.secondary)
            }
            Text(report.article.displayTitle).font(.body)
            if let excerpt = report.excerpts.first {
              Text(excerpt).font(.footnote).foregroundColor(.secondary)
            }
          }
          .padding(.vertical, 4)
        }
      }
      .navigationTitle(t("public_news_event_sources", "Reports on this event"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_close", "Close")) { dismiss() }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIPublicNewsCachedReportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var archive: PublicNewsArchive
  let report: PublicNewsEvent.Report
  @State private var checkpoint: PublicNewsBodyCheckpoint?
  @State private var loaded = false
  @State private var isVisible = false

  private var retained: Bool { archive.eligibleArticles.contains { $0.id == report.id } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(report.article.displayTitle).font(.title2.weight(.semibold))
        GalaxySSIPublicNewsByline(article: report.article)
        if !retained {
          Text(t("public_news_event_removed", "This report is no longer in the local archive."))
        } else if let checkpoint {
          // Display the exact cached original, not a merged account or another source's translation.
          Text(checkpoint.source.paragraphs.joined(separator: "\n\n"))
            .textSelection(.enabled)
            .onAppear { markDisplayed() }
        } else if loaded {
          Text(t("public_news_event_no_body", "The original article has not been downloaded on this phone."))
            .foregroundColor(.secondary)
        } else {
          ProgressView()
        }
        if let source = PublicNewsDiscussionSeed.sourceURL(report.article.url) {
          Link(destination: source) {
            Label(t("public_news_original_source", "Original source"), systemImage: "arrow.up.right")
              .frame(minHeight: 44)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }
    .navigationTitle(report.source)
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("ios.news.event.cached-report")
    .onAppear { isVisible = true; markDisplayed() }
    .onDisappear { isVisible = false }
    .task(id: report.id) {
      checkpoint = nil
      loaded = false
      let saved = await archive.articleBodies.load(report.id)
      guard !Task.isCancelled, retained else { loaded = true; return }
      checkpoint = saved
      loaded = true
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active { markDisplayed() }
    }
  }

  private func markDisplayed() {
    guard isVisible, scenePhase == .active, retained, let checkpoint,
          checkpoint.articleID == report.id, !checkpoint.source.paragraphs.isEmpty else { return }
    archive.markRead(report.id)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
