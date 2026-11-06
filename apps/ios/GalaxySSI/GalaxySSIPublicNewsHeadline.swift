import SwiftUI
import UIKit

struct PublicNewsHeadlineReadAppearance {
  private var attachment: (id: String, read: Bool)?

  mutating func attach(id: String, read: Bool) {
    if attachment?.id != id { attachment = (id, read) }
  }

  mutating func detach() { attachment = nil }

  func isRead(id: String, persisted: Bool) -> Bool {
    attachment?.id == id ? (attachment?.read ?? persisted) : persisted
  }

  static func titleColor(read: Bool) -> Color {
    read ? .galaxySSITextPrimary : .galaxySSINewsUnreadTitle
  }
}

@MainActor
struct GalaxySSIPublicNewsHeadline<Title: View, Detail: View>: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var selection: String?
  @State private var readAppearance = PublicNewsHeadlineReadAppearance()
  @ScaledMetric(relativeTo: .body) private var primarySlotHeight = 48.0
  @ScaledMetric(relativeTo: .caption) private var secondarySlotHeight = 36.0

  let archive: PublicNewsArchive
  let article: PublicNewsArticle
  var reader = false
  var expanded = false
  var reservesBilingualSpace = false
  var stabilizesReadAppearance = false
  var onOpen: (() -> Void)? = nil
  var onDismissArticle: (() -> Void)? = nil
  @ViewBuilder let title: () -> Title
  @ViewBuilder let detail: () -> Detail

  private var displayedRead: Bool {
    stabilizesReadAppearance ? readAppearance.isRead(id: article.id, persisted: article.read) : article.read
  }

  private var titleColor: Color? {
    stabilizesReadAppearance ? PublicNewsHeadlineReadAppearance.titleColor(read: displayedRead) : nil
  }

  var body: some View {
    Group {
      if let selection {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 4) {
            Text(selection)
              .font(reader ? .title2 : .body)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
              .hidden()
              .overlay { GalaxySSIPublicNewsNativeSelection(text: selection, reader: reader, color: titleColor) }
            Button { self.selection = nil } label: {
              Image(systemName: "checkmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("public_news_done_selecting", "Done selecting"))
          }
          byline
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else if let onOpen {
        Button(action: onOpen) { headline }
          .buttonStyle(.plain)
          .contextMenu { actions }
      } else {
        headline.contextMenu { actions }
      }
    }
    .onChange(of: scenePhase) { if $0 != .active { selection = nil } }
    .onAppear { readAppearance.attach(id: article.id, read: article.read) }
    .onChange(of: article.id) { readAppearance.attach(id: $0, read: article.read) }
    .onDisappear {
      selection = nil
      readAppearance.detach()
    }
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 6) {
      if reservesBilingualSpace {
        styledTitle.frame(height: primarySlotHeight, alignment: .topLeading)
        Text(article.displayTitle == article.title ? t("public_news_headline_pending", "Translation pending") : article.title)
          .font(.caption).foregroundColor(.secondary).lineLimit(2)
          .frame(height: secondarySlotHeight, alignment: .topLeading)
      } else {
        styledTitle
        if !reader && article.displayTitle != article.title {
          Text(article.title).font(.caption).foregroundColor(.secondary).lineLimit(expanded ? nil : 3)
        }
      }
      byline
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  @ViewBuilder private var styledTitle: some View {
    if let titleColor { title().foregroundColor(titleColor) }
    else { title() }
  }

  @ViewBuilder private var byline: some View {
    if stabilizesReadAppearance && displayedRead {
      HStack(spacing: 6) {
        detail()
        Text(t("public_news_read_status", "Read"))
          .font(.caption)
          .foregroundColor(.galaxySSITextSecondary)
          .layoutPriority(1)
      }
    } else {
      detail()
    }
  }

  private var actions: some View {
    let displayedTitle = article.displayTitle
    return Group {
      Button { UIPasteboard.general.string = displayedTitle } label: {
        Label(t("common_copy", "Copy"), systemImage: "doc.on.doc")
      }
      Button { selection = displayedTitle } label: {
        Label(t("common_select", "Select"), systemImage: "selection.pin.in.out")
      }
      Divider()
      Button { archive.markRead(article.id) } label: {
        Label(t("public_news_mark_read", "Mark as read"), systemImage: "checkmark.circle")
      }
      .disabled(displayedRead || !archive.loaded)
      Button {
        if archive.markNotRelevant(article.id) { onDismissArticle?() }
      } label: {
        Label(t("agent_global_feedback_not_relevant", "Not relevant"), systemImage: "xmark.circle")
      }
      .disabled(!archive.loaded)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct GalaxySSIPublicNewsNativeSelection: UIViewRepresentable {
  let text: String
  let reader: Bool
  let color: Color?

  func makeUIView(context: Context) -> SelectionTextView {
    let view = SelectionTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textColor = color.map { UIColor($0) } ?? .label
    view.textContainerInset = .zero
    view.textContainer.lineFragmentPadding = 0
    view.font = .preferredFont(forTextStyle: reader ? .title2 : .body)
    view.adjustsFontForContentSizeCategory = true
    view.text = text
    view.accessibilityIdentifier = "ios.public-news.selected-headline"
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }

  func updateUIView(_ view: SelectionTextView, context: Context) {
    view.textColor = color.map { UIColor($0) } ?? .label
  }

  static func dismantleUIView(_ view: SelectionTextView, coordinator: ()) {
    view.resignFirstResponder()
    view.selectedTextRange = nil
  }

  final class SelectionTextView: UITextView {
    private var didSelect = false

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard window != nil, !didSelect else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window != nil, !self.didSelect else { return }
        self.didSelect = true
        if self.becomeFirstResponder() {
          self.selectedRange = NSRange(location: 0, length: (self.text as NSString).length)
        }
      }
    }
  }
}
