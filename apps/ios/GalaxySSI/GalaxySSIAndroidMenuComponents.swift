import SwiftUI

struct GalaxySSIAndroidMenuGroup<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct GalaxySSIAndroidGroupedMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String?
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    assetImageName: String? = nil,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.assetImageName = assetImageName
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      GalaxySSIAndroidGroupedMenuRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint
      )
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSIAndroidGroupedMenuButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String? = nil
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      GalaxySSIAndroidGroupedMenuRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint
      )
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSIAndroidGroupedMenuRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String?
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      GalaxySSIAndroidMenuIcon(systemImage: systemImage, assetImageName: assetImageName, tint: tint)
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
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
  }
}

struct GalaxySSIAndroidMenuIcon: View {
  var systemImage: String
  var assetImageName: String?
  var tint: Color

  var body: some View {
    ZStack {
      if let assetImageName {
        Image(assetImageName)
          .resizable()
          .renderingMode(.original)
          .scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
    }
    .frame(width: 42, height: 42)
  }
}

struct GalaxySSIAndroidMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.galaxySSISeparator)
      .frame(height: 0.5)
      .padding(.leading, 66)
  }
}

struct GalaxySSIAndroidMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
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
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct GalaxySSIAndroidMenuButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
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
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
