import SwiftUI

@MainActor
struct GalaxySSIPublicNewsHighlightsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var archive: PublicNewsArchive
  @AppStorage("publicNews.highlightInterests") private var interestMask = PublicNewsInterest.allMask
  @State private var selected: PublicNewsArticle?
  @State private var articleIDs: [String] = []
  @State private var loading = true

  private struct SelectionRequest: Equatable {
    var mask: Int
    var refreshing: Bool
  }

  private var articles: [PublicNewsArticle] {
    let indexed = Dictionary(archive.articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return articleIDs.compactMap { indexed[$0] }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("public_news_highlights", "Highlights"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Menu {
            ForEach(PublicNewsInterest.allCases) { interest in
              Toggle(title(interest), isOn: Binding(
                get: { interestMask & interest.bit != 0 },
                set: { enabled in
                  if enabled { interestMask |= interest.bit }
                  else { interestMask &= ~interest.bit }
                }
              ))
            }
          } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 40, height: 44)
          }
          .accessibilityLabel(t("public_news_highlight_interests", "Highlight interests"))
        }
      )
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if loading || (articles.isEmpty && archive.refreshing) {
            ProgressView().frame(maxWidth: .infinity).padding()
          } else if articles.isEmpty {
            Text(t("public_news_highlights_empty", "No highlights"))
              .foregroundColor(.galaxySSITextSecondary).padding(12)
          } else {
            ForEach(articles) { article in
              HStack(spacing: 8) {
                Button {
                  selected = article
                  archive.markRead(article.id)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                      .font(.body.weight(article.read ? .regular : .semibold))
                      .foregroundColor(.galaxySSITextPrimary)
                      .lineLimit(3)
                    GalaxySSIPublicNewsByline(article: article)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 12)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                GalaxySSIPublicNewsBookmark(archive: archive, article: article)
              }
              .padding(.leading, 12)
              .background(Color.galaxySSISurface)
              Divider()
            }
          }
        }
        .padding(.horizontal, 12)
      }
      .refreshable { await archive.refresh(force: true) }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .task(id: SelectionRequest(mask: interestMask, refreshing: archive.refreshing)) {
      if !archive.refreshing { await curate(mask: interestMask) }
    }
    .sheet(item: $selected) { GalaxySSIPublicNewsReader(archive: archive, original: $0) }
  }

  private func curate(mask: Int) async {
    archive.load()
    loading = true
    let archiveSnapshot = archive.articles
    let enabled = Set(PublicNewsInterest.allCases.filter { mask & $0.bit != 0 })
    let worker = Task.detached(priority: .userInitiated) {
      let metadata = archiveSnapshot.map(PublicNewsHighlights.metadata)
      return try PublicNewsHighlights.select(metadata, enabled: enabled, now: Date())
    }
    do {
      let ids = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, interestMask == mask else { return }
      articleIDs = ids
      loading = false
    } catch {
      if !Task.isCancelled, interestMask == mask { loading = false }
    }
  }

  private func title(_ interest: PublicNewsInterest) -> String {
    switch interest {
    case .technology: return t("public_news_interest_technology", "Technology")
    case .finance: return t("public_news_interest_finance", "Finance")
    case .research: return t("public_news_interest_research", "Research")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
