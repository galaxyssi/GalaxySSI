import SwiftUI
import UIKit

@MainActor
struct GalaxySSIPublicNewsHeadline<Title: View, Detail: View>: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var selection: String?

  let archive: PublicNewsArchive
  let article: PublicNewsArticle
  var reader = false
  var onOpen: (() -> Void)? = nil
  var onDismissArticle: (() -> Void)? = nil
  @ViewBuilder let title: () -> Title
  @ViewBuilder let detail: () -> Detail

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
              .overlay { GalaxySSIPublicNewsNativeSelection(text: selection, reader: reader) }
            Button { self.selection = nil } label: {
              Image(systemName: "checkmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("public_news_done_selecting", "Done selecting"))
          }
          detail()
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
    .onDisappear { selection = nil }
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 6) {
      title()
      detail()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
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
      .disabled(article.read)
      Button {
        if archive.markNotRelevant(article.id) { onDismissArticle?() }
      } label: {
        Label(t("agent_global_feedback_not_relevant", "Not relevant"), systemImage: "xmark.circle")
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}

private struct GalaxySSIPublicNewsNativeSelection: UIViewRepresentable {
  let text: String
  let reader: Bool

  func makeUIView(context: Context) -> SelectionTextView {
    let view = SelectionTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textColor = .label
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
    // The parent freezes the exact headline until selection ends.
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
