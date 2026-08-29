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
        ForEach(0..<4, id: \.self) { index in
          Circle()
            .fill(Color.signalASITextPrimary)
            .frame(width: 4.5, height: 4.5)
            .offset(
              x: index.isMultiple(of: 2) ? -4 : 4,
              y: index < 2 ? -4 : 4
            )
        }
      }
    }
    .frame(width: 46, height: 46)
  }
}

enum SignalASIPeerComposerActionPolicy {
  static let actionIDs = SignalASIComposerTrayActionID.allCases

  static func consumesBackAction(actionTrayPresented: Bool) -> Bool {
    actionTrayPresented
  }
}
