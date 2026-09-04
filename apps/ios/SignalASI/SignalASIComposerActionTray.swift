import SwiftUI
import UIKit

enum SignalASIComposerTrayActionID: String, CaseIterable, Identifiable {
  case newSession = "new-session"
  case sessions
  case scan
  case camera
  case file

  var id: String { rawValue }
}

struct SignalASIComposerTrayAction: Identifiable {
  var id: SignalASIComposerTrayActionID
  var title: String
  var systemImage: String
  var perform: () -> Void

  var iconTint: Color {
    switch id {
    case .newSession:
      return Color(red: 16 / 255, green: 175 / 255, blue: 104 / 255)
    case .sessions:
      return Color(red: 119 / 255, green: 87 / 255, blue: 215 / 255)
    case .scan:
      return Color(red: 77 / 255, green: 111 / 255, blue: 245 / 255)
    case .camera:
      return Color(red: 230 / 255, green: 135 / 255, blue: 43 / 255)
    case .file:
      return Color(red: 24 / 255, green: 167 / 255, blue: 189 / 255)
    }
  }
}

struct SignalASIComposerActionTray: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var actions: [SignalASIComposerTrayAction]
  var accessibilityPrefix: String
  var minimumTouchSize: CGFloat
  var onSelect: () -> Void

  var body: some View {
    Group {
      if usesAccessibilityDynamicType {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
          spacing: 0
        ) {
          trayButtons
        }
        .frame(height: 176)
      } else {
        HStack(spacing: 0) {
          trayButtons
        }
        .frame(height: 96)
      }
    }
    .background(Color.signalASIBarBackground)
  }

  @ViewBuilder
  private var trayButtons: some View {
    ForEach(actions) { item in
      Button {
        onSelect()
        item.perform()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: item.systemImage)
            .font(.system(size: 23, weight: .semibold))
            .foregroundColor(item.iconTint)
            .frame(width: 46, height: 46)
            .overlay(
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(item.iconTint, lineWidth: 2)
            )
          Text(item.title)
            .font(.system(size: usesAccessibilityDynamicType ? 13 : 12))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .minimumScaleFactor(usesAccessibilityDynamicType ? 0.85 : 0.72)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: minimumTouchSize)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(item.title))
      .accessibilityIdentifier("\(accessibilityPrefix).\(item.id.rawValue)")
    }
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
  }
}

struct SignalASIComposerMoreButtonIcon: View {
  var expanded: Bool

  var body: some View {
    ZStack {
      if expanded {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(Color.signalASIButtonSoft)
          .frame(width: 32, height: 32)

        Capsule()
          .fill(Color.signalASITextPrimary)
          .frame(width: 12, height: 2.25)
      } else {
        Image(systemName: "square.3.layers.3d")
          .font(.system(size: 22, weight: .medium))
          .foregroundColor(.signalASITextPrimary)
      }
    }
    .frame(width: 46, height: 46)
  }
}

private struct SignalASIComposerTextHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 54

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct SignalASIGrowingComposerEditor: View {
  @Binding var text: String
  var placeholder: String
  var focus: FocusState<Bool>.Binding
  var accessibilityIdentifier: String
  var onTap: () -> Void

  @State private var editorHeight: CGFloat = 54

  private let minimumHeight: CGFloat = 54
  private let maximumHeight: CGFloat = 172

  var body: some View {
    ZStack(alignment: .topLeading) {
      Text(text.isEmpty ? " " : text + "\n")
        .font(.system(size: 15))
        .foregroundColor(.clear)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: SignalASIComposerTextHeightKey.self,
              value: proxy.size.height
            )
          }
        )

      if text.isEmpty {
        Text(placeholder)
          .font(.system(size: 15))
          .foregroundColor(.signalASITextSecondary)
          .padding(.leading, 12)
          .padding(.top, 16)
          .allowsHitTesting(false)
      }

      SignalASIParagraphSelectingTextView(
        text: $text,
        focus: focus,
        accessibilityIdentifier: accessibilityIdentifier,
        onBeginEditing: onTap
      )
    }
    .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: editorHeight)
    .onPreferenceChange(SignalASIComposerTextHeightKey.self) { measuredHeight in
      editorHeight = min(max(measuredHeight, minimumHeight), maximumHeight)
    }
  }
}

enum SignalASIParagraphSelectionPolicy {
  static func range(in text: String, requestedUTF16Offset: Int) -> NSRange {
    let source = text as NSString
    guard source.length > 0 else { return NSRange(location: 0, length: 0) }

    var anchor = min(max(requestedUTF16Offset, 0), source.length)
    if anchor == source.length {
      anchor -= 1
    }
    if source.character(at: anchor) == 10, anchor > 0 {
      anchor -= 1
    }

    var start = 0
    for index in stride(from: anchor, through: 0, by: -1) where source.character(at: index) == 10 {
      start = index + 1
      break
    }

    var end = source.length
    for index in anchor..<source.length where source.character(at: index) == 10 {
      end = index
      break
    }
    if end > start, source.character(at: end - 1) == 13 {
      end -= 1
    }
    return NSRange(location: start, length: max(end - start, 0))
  }
}

private struct SignalASIParagraphSelectingTextView: UIViewRepresentable {
  @Binding var text: String
  var focus: FocusState<Bool>.Binding
  var accessibilityIdentifier: String
  var onBeginEditing: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = .systemFont(ofSize: 15)
    textView.textColor = UIColor(Color.signalASITextPrimary)
    textView.autocapitalizationType = .sentences
    textView.autocorrectionType = .default
    textView.keyboardDismissMode = .interactive
    textView.isEditable = true
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.textContainer.lineFragmentPadding = 0
    textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
    textView.accessibilityIdentifier = accessibilityIdentifier

    let longPress = UILongPressGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.selectParagraph(_:))
    )
    longPress.cancelsTouchesInView = false
    longPress.delegate = context.coordinator
    textView.addGestureRecognizer(longPress)
    context.coordinator.textView = textView
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
      let selection = textView.selectedRange
      textView.text = text
      let textLength = (text as NSString).length
      let location = min(selection.location, textLength)
      textView.selectedRange = NSRange(
        location: location,
        length: min(selection.length, textLength - location)
      )
    }
    textView.accessibilityIdentifier = accessibilityIdentifier
    if focus.wrappedValue, !textView.isFirstResponder {
      textView.becomeFirstResponder()
    } else if !focus.wrappedValue, textView.isFirstResponder {
      textView.resignFirstResponder()
    }
  }

  final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var parent: SignalASIParagraphSelectingTextView
    weak var textView: UITextView?

    init(parent: SignalASIParagraphSelectingTextView) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.focus.wrappedValue = true
      parent.onBeginEditing()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.focus.wrappedValue = false
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    @objc func selectParagraph(_ gesture: UILongPressGestureRecognizer) {
      guard gesture.state == .began,
            let textView,
            textView.isFirstResponder,
            let position = textView.closestPosition(to: gesture.location(in: textView)) else {
        return
      }
      let offset = textView.offset(from: textView.beginningOfDocument, to: position)
      let range = SignalASIParagraphSelectionPolicy.range(
        in: textView.text,
        requestedUTF16Offset: offset
      )
      guard range.length > 0 else { return }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.032) { [weak textView] in
        guard let textView, textView.isFirstResponder else { return }
        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
        let menuRect = textView.selectedTextRange.map { textView.firstRect(for: $0) }
          ?? textView.bounds.insetBy(dx: 12, dy: 12)
        UIMenuController.shared.showMenu(
          from: textView,
          rect: menuRect
        )
      }
    }
  }
}

enum SignalASIPeerComposerActionPolicy {
  static let actionIDs = SignalASIComposerTrayActionID.allCases

  static func consumesBackAction(actionTrayPresented: Bool) -> Bool {
    actionTrayPresented
  }
}
