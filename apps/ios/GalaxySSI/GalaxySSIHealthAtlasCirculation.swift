import SwiftUI

enum GalaxySSIHealthAtlasCirculation {
  enum Node { case tissues, rightHeart, lungs, leftHeart }
  struct Leg { let from: Node; let to: Node; let oxygenRich: Bool }
  static let source = URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy")!
  static let legs = [
    Leg(from: .tissues, to: .rightHeart, oxygenRich: false),
    Leg(from: .rightHeart, to: .lungs, oxygenRich: false),
    Leg(from: .lungs, to: .leftHeart, oxygenRich: true),
    Leg(from: .leftHeart, to: .tissues, oxygenRich: true)
  ]
  static func supports(_ id: String) -> Bool {
    ["cardio", "heart", "atria", "ventricles", "coronary-vessels",
     "blood-vessels", "arteries", "veins", "capillaries", "blood"].contains(id)
  }
  static func phase(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
  static func stage(_ value: Double) -> Int { min(3, Int(phase(value) * 4)) }
  static func fraction(_ value: Double) -> Double { phase(value) * 4 - Double(stage(value)) }
}

private struct GalaxySSIAtlasCircuitAnchors: PreferenceKey {
  static var defaultValue: [Int: Anchor<CGRect>] = [:]
  static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

struct GalaxySSIHealthAtlasCirculationView: View {
  let phase: Double
  let flow: Double?
  let language: String
  let stages: [String]
  let selected: (Int) -> Void
  let open: (String) -> Void
  @Environment(\.colorScheme) private var scheme
  private var low: Color { scheme == .dark ? Color(red: 131.0 / 255, green: 190.0 / 255, blue: 235.0 / 255) : Color(red: 51.0 / 255, green: 111.0 / 255, blue: 164.0 / 255) }
  private var high: Color { scheme == .dark ? Color(red: 243.0 / 255, green: 152.0 / 255, blue: 160.0 / 255) : Color(red: 183.0 / 255, green: 70.0 / 255, blue: 80.0 / 255) }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_circuit_" + key, language) }
  var body: some View {
    VStack(spacing: 12) {
      node(0, asset: "HealthAtlasLungs", title: "lungs", target: "lungs")
      HStack { stage(1); Spacer(minLength: 24); stage(2) }
      HStack(alignment: .center, spacing: 4) {
        Text(t("right")).font(.caption).foregroundColor(low).frame(maxWidth: .infinity)
        node(1, asset: "HealthAtlasHeart", title: "heart", target: "heart")
        Text(t("left")).font(.caption).foregroundColor(high).frame(maxWidth: .infinity)
      }
      HStack { stage(0); Spacer(minLength: 24); stage(3) }
      node(2, asset: "HealthAtlasBody", title: "tissues", target: nil)
    }
    .backgroundPreferenceValue(GalaxySSIAtlasCircuitAnchors.self) { anchors in
      GeometryReader { proxy in
        if let lungs = anchors[0], let heart = anchors[1], let tissues = anchors[2] {
          routes(width: proxy.size.width, lungs: proxy[lungs], heart: proxy[heart], tissues: proxy[tissues])
        }
      }.accessibilityHidden(true).allowsHitTesting(false)
    }
  }
  private func node(_ index: Int, asset: String, title: String, target: String?) -> some View {
    Button { if let target { open(target) } } label: {
      VStack(spacing: 4) {
        Image(asset).resizable().scaledToFit().frame(height: index == 2 ? 104 : 88).accessibilityHidden(true)
        Text(t(title)).font(.caption).fixedSize(horizontal: false, vertical: true)
        if index == 1, let flow {
          Text(String(format: t("flow"), flow.formatted(.number.locale(GalaxySSILocalization.interfaceLocale(language: language)).precision(.fractionLength(2)))))
            .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
      }.foregroundColor(.primary).frame(maxWidth: .infinity).padding(.vertical, 4)
    }.buttonStyle(.plain).disabled(target == nil)
      .anchorPreference(key: GalaxySSIAtlasCircuitAnchors.self, value: .bounds) { [index: $0] }
      .accessibilityIdentifier("atlas-circulation-node-" + (target ?? "tissues"))
  }
  private func stage(_ index: Int) -> some View {
    Button { selected(index) } label: {
      Text(t("leg_" + String(index))).font(.caption).bold()
        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 48).padding(4)
        .foregroundColor(index == GalaxySSIHealthAtlasCirculation.stage(phase) ? (index < 2 ? low : high) : .primary)
        .background(Color(UIColor.systemBackground))
    }.buttonStyle(.plain)
      .accessibilityLabel(String(format: GalaxySSIHealthAtlasText.get("health_atlas_stage", language),
        Int64(index + 1), Int64(4), GalaxySSIHealthAtlasText.get(stages[index], language)))
      .accessibilityAddTraits(index == GalaxySSIHealthAtlasCirculation.stage(phase) ? .isSelected : [])
      .accessibilityIdentifier("atlas-circulation-stage-" + String(index))
  }
  private func routes(width: CGFloat, lungs: CGRect, heart: CGRect, tissues: CGRect) -> some View {
    ZStack {
      ForEach(0..<4) { index in
        let left = index < 2
        let inner = width * (left ? 0.4 : 0.6), outer = width * (left ? 0.14 : 0.86)
        let starts = [tissues.minY + 52, heart.minY + 26, lungs.minY + 44, heart.minY + 62]
        let ends = [heart.minY + 62, lungs.minY + 44, heart.minY + 26, tissues.minY + 52]
        let points = [CGPoint(x: inner, y: starts[index]), CGPoint(x: outer, y: starts[index]),
          CGPoint(x: outer, y: ends[index]), CGPoint(x: inner, y: ends[index])]
        let color = left ? low : high
        let active = index == GalaxySSIHealthAtlasCirculation.stage(phase)
        Path { p in p.addLines(points) }.stroke(color.opacity(active ? 1 : 0.45), lineWidth: active ? 3 : 1.5)
        let end = points[3], sign: CGFloat = left ? 1 : -1
        Path { p in
          p.move(to: end); p.addLine(to: CGPoint(x: end.x - sign * 8, y: end.y - 4))
          p.addLine(to: CGPoint(x: end.x - sign * 8, y: end.y + 4)); p.closeSubpath()
        }.fill(color)
        if active {
          let point = position(points, fraction: GalaxySSIHealthAtlasCirculation.fraction(phase))
          Circle().fill(color).frame(width: 10, height: 10).position(point)
        }
      }
    }
  }
  private func position(_ points: [CGPoint], fraction: Double) -> CGPoint {
    let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
    var remaining = lengths.reduce(0, +) * CGFloat(fraction)
    for index in lengths.indices {
      let length = lengths[index]
      if remaining <= length, length > 0 {
        let f = remaining / length
        return CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * f,
          y: points[index].y + (points[index + 1].y - points[index].y) * f)
      }
      remaining -= length
    }
    return points.last ?? .zero
  }
}
