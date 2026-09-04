import SwiftUI

struct GalaxySSILocalModelLabHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 54, height: 54)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
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

struct GalaxySSILocalModelLabSectionTitle: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }
}

struct GalaxySSILocalModelLabNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    monospacedSubtitle: Bool = false,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.monospacedSubtitle = monospacedSubtitle
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      GalaxySSILocalModelLabRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSILocalModelLabActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      GalaxySSILocalModelLabRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSILocalModelLabToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var isOn: Bool
  var isEnabled: Bool = true
  var onToggle: (Bool) -> Void

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      Toggle(title, isOn: Binding(
        get: { isOn },
        set: { onToggle($0) }
      ))
      .labelsHidden()
      .tint(tint)
      .disabled(!isEnabled)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct GalaxySSILocalModelLabStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool = false

  var body: some View {
    GalaxySSILocalModelLabRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      monospacedSubtitle: monospacedSubtitle,
      showsDisclosure: false
    )
  }
}

private struct GalaxySSILocalModelLabRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(monospacedSubtitle ? .system(size: 12, design: .monospaced) : .system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(monospacedSubtitle ? 3 : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
