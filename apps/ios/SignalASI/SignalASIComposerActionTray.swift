import SwiftUI

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
            .font(.system(size: 25, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .frame(width: 30, height: 30)
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

enum SignalASIPeerComposerActionPolicy {
  static let actionIDs = SignalASIComposerTrayActionID.allCases

  static func consumesBackAction(actionTrayPresented: Bool) -> Bool {
    actionTrayPresented
  }
}
